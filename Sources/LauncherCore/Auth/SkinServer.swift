import Foundation
import Network
import Security
import CryptoKit

/// 离线账号的皮肤：在本机运行一个最小的 Yggdrasil 服务（只监听 127.0.0.1），
/// 游戏通过 authlib-injector 向它查询皮肤。材质属性用本次运行生成的 RSA 密钥签名。
package final class SkinServer: @unchecked Sendable {
    package static let shared = SkinServer()

    private let queue = DispatchQueue(label: "kiln.skinserver")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let lock = NSLock()
    /// 玩家：无连字符 UUID → (名称, 皮肤文件, 是否纤细模型)
    private var players: [String: (name: String, skin: URL?, slim: Bool)] = [:]
    private let privateKey: SecKey
    private let publicKeyPEM: String

    private init() {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error)!
        let pub = SecKeyCopyPublicKey(privateKey)!
        let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil)! as Data
        publicKeyPEM = Self.pem(spki: Self.spki(pkcs1))
    }

    /// 服务器根地址（首次调用时启动）
    package func start() throws -> String {
        lock.lock(); defer { lock.unlock() }
        if listener == nil {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
            let l = try NWListener(using: params)
            let ready = DispatchSemaphore(value: 0)
            l.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
                if case .failed = state { ready.signal() }
            }
            l.newConnectionHandler = { [weak self] c in self?.handle(c) }
            l.start(queue: queue)
            _ = ready.wait(timeout: .now() + 5)
            guard let p = l.port?.rawValue, p != 0 else { throw LauncherError(T("无法启动本地皮肤服务", "Couldn't start the local skin service")) }
            port = p
            listener = l
            log("[Skin] 本地皮肤服务：127.0.0.1:\(p)")
        }
        return "http://127.0.0.1:\(port)"
    }

    package func register(uuid: String, name: String, skin: URL?, slim: Bool) {
        lock.lock(); defer { lock.unlock() }
        players[uuid.replacingOccurrences(of: "-", with: "").lowercased()] = (name, skin, slim)
    }

    /// 元数据（启动时预先传给 authlib-injector）
    package var metadata: JSON {
        .object([
            "meta": .object(["serverName": .string(AppInfo.shortName), "implementationName": .string("Kiln offline skins"),
                             "implementationVersion": .string(AppInfo.version), "feature.no_mojang_namespace": .bool(true)]),
            "skinDomains": .array([.string("127.0.0.1"), .string("localhost")]),
            "signaturePublickey": .string(publicKeyPEM),
        ])
    }

    // MARK: HTTP

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let parts = lines.first?.split(separator: " ").map(String.init) ?? []
                let length = lines.compactMap { l -> Int? in
                    let kv = l.split(separator: ":", maxSplits: 1)
                    return kv.count == 2 && kv[0].lowercased() == "content-length" ? Int(kv[1].trimmingCharacters(in: .whitespaces)) : nil
                }.first ?? 0
                let body = buf[end.upperBound...]
                if body.count >= length, parts.count >= 2 {
                    let (status, type, payload) = self.route(method: parts[0], target: parts[1], body: Data(body.prefix(length)))
                    self.respond(c, status: status, type: type, body: payload)
                    return
                }
            }
            if done || error != nil || buf.count > 1 << 20 { c.cancel(); return }
            self.receive(c, buffer: buf)
        }
    }

    private func respond(_ c: NWConnection, status: Int, type: String, body: Data) {
        let reason = [200: "OK", 204: "No Content", 404: "Not Found"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: \(type)\r\n" }
        head += "\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func route(method: String, target: String, body: Data) -> (Int, String, Data) {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        let json = "application/json; charset=utf-8"
        lock.lock(); let all = players; lock.unlock()
        if path != "/" { log("[Skin] \(method) \(path)") }

        if path == "/" || path.isEmpty { return (200, json, metadata.data(pretty: false)) }
        // 按 UUID 查询档案（含签名的材质属性）
        if path.hasPrefix("/sessionserver/session/minecraft/profile/") {
            let id = String(path.dropFirst("/sessionserver/session/minecraft/profile/".count)).replacingOccurrences(of: "-", with: "").lowercased()
            guard let p = all[id] else { return (204, json, Data()) }
            return (200, json, profile(id: id, p).data(pretty: false))
        }
        // 按名称批量查询 UUID
        if path == "/api/profiles/minecraft" && method == "POST" {
            let names = Set((try? JSON(data: body))?.array.compactMap { $0.string?.lowercased() } ?? [])
            let found = all.filter { names.contains($0.value.name.lowercased()) }
                .map { JSON.object(["id": .string($0.key), "name": .string($0.value.name)]) }
            return (200, json, JSON.array(found).data(pretty: false))
        }
        // 局域网联机：加入与验证
        if path == "/sessionserver/session/minecraft/join" { return (204, json, Data()) }
        if path == "/sessionserver/session/minecraft/hasJoined" {
            let query = URLComponents(string: target)?.queryItems ?? []
            let name = query.first { $0.name == "username" }?.value?.lowercased() ?? ""
            guard let (id, p) = all.first(where: { $0.value.name.lowercased() == name }) else { return (204, json, Data()) }
            return (200, json, profile(id: id, p).data(pretty: false))
        }
        // 材质
        if path.hasPrefix("/textures/") {
            let hash = String(path.dropFirst("/textures/".count))
            if let p = all.values.first(where: { $0.skin.flatMap(Self.textureHash) == hash }), let file = p.skin,
               let data = try? Data(contentsOf: file) {
                return (200, "image/png", data)
            }
            return (404, json, Data())
        }
        // 1.19+ 的玩家属性：允许聊天与多人游戏
        if path == "/minecraftservices/player/attributes" {
            let attrs = JSON.object(["privileges": .object([
                "onlineChat": .object(["enabled": .bool(true)]), "multiplayerServer": .object(["enabled": .bool(true)]),
                "multiplayerRealms": .object(["enabled": .bool(false)]), "telemetry": .object(["enabled": .bool(false)]),
            ]), "profanityFilterPreferences": .object(["profanityFilterOn": .bool(false)])])
            return (200, json, attrs.data(pretty: false))
        }
        if path.hasPrefix("/minecraftservices/") { return (204, json, Data()) }
        return (404, json, Data())
    }

    private func profile(id: String, _ p: (name: String, skin: URL?, slim: Bool)) -> JSON {
        var textures: [String: JSON] = [:]
        if let skin = p.skin, let hash = Self.textureHash(skin) {
            var s: [String: JSON] = ["url": .string("http://127.0.0.1:\(port)/textures/\(hash)")]
            if p.slim { s["metadata"] = .object(["model": .string("slim")]) }
            textures["SKIN"] = .object(s)
        }
        let value = JSON.object(["timestamp": .number(Date().timeIntervalSince1970 * 1000), "profileId": .string(id),
                                 "profileName": .string(p.name), "textures": .object(textures)])
            .data(pretty: false).base64EncodedString()
        var property: [String: JSON] = ["name": .string("textures"), "value": .string(value)]
        if let sig = sign(value) { property["signature"] = .string(sig) }
        return .object(["id": .string(id), "name": .string(p.name), "properties": .array([.object(property)])])
    }

    /// SHA1withRSA 签名（authlib 校验材质属性所用的算法）
    private func sign(_ value: String) -> String? {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA1, Data(value.utf8) as CFData, &error) else { return nil }
        return (sig as Data).base64EncodedString()
    }

    /// 材质地址中的哈希：文件内容的 SHA-256
    static func textureHash(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 密钥格式

    /// PKCS#1 RSAPublicKey → X.509 SubjectPublicKeyInfo
    static func spki(_ pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bitString = [0x03] + derLength(pkcs1.count + 1) + [0x00] + [UInt8](pkcs1)
        let content = algorithm + bitString
        return Data([0x30] + derLength(content.count) + content)
    }

    static func derLength(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func pem(spki: Data) -> String {
        let b64 = spki.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(b64)\n-----END PUBLIC KEY-----\n"
    }
}
