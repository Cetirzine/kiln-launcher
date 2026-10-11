import Foundation
import CryptoKit
import ImageIO

/// 皮肤：离线账号的本地皮肤与“同名正版皮肤”，以及微软账号的皮肤上传与披风切换
package enum Skins {
    static var folder: URL { Paths.support.appendingPathComponent("skins", isDirectory: true) }

    package static func file(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// 检查是否为有效的皮肤图片（64×64 或旧版 64×32 的 PNG），返回是否为旧格式
    @discardableResult
    package static func validate(_ data: Data) throws -> Bool {
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw LauncherError(T("皮肤需要是 PNG 图片", "A skin must be a PNG image"))
        }
        guard w == 64 && (h == 64 || h == 32) else {
            throw LauncherError(T("皮肤尺寸需要是 64×64 或 64×32（当前 \(w)×\(h)）", "A skin must be 64×64 or 64×32 (this one is \(w)×\(h))"))
        }
        return h == 32
    }

    /// 导入皮肤文件，返回保存后的文件名（按内容命名，相同皮肤只保存一份）
    package static func importSkin(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        try validate(data)
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16) + ".png"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file(String(name)), options: .atomic)
        return String(name)
    }

    /// 同名正版玩家的皮肤（缓存一天）
    package static func premium(_ name: String) async throws -> (url: URL, slim: Bool) {
        let cache = Paths.cache.appendingPathComponent("skins", isDirectory: true)
        let png = cache.appendingPathComponent("premium-\(name.lowercased()).png")
        let meta = cache.appendingPathComponent("premium-\(name.lowercased()).slim")
        if let d = (try? png.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(d) < 24 * 3600 {
            return (png, FileManager.default.fileExists(atPath: meta.path))
        }
        let (code, user) = try await Net.request("https://api.mojang.com/users/profiles/minecraft/\(name)", method: "GET")
        guard code == 200, let id = user["id"].string else { throw LauncherError(T("没有名为 \(name) 的正版玩家", "There's no Minecraft player named \(name)")) }
        let profile = try await Net.json(urls: ["https://sessionserver.mojang.com/session/minecraft/profile/\(id)"])
        guard let value = profile["properties"].array.first(where: { $0["name"].string == "textures" })?["value"].string,
              let decoded = Data(base64Encoded: value), let textures = try? JSON(data: decoded),
              let url = textures["textures"]["SKIN"]["url"].string else {
            throw LauncherError(T("\(name) 使用的是默认皮肤", "\(name) uses a default skin"))
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let data = try await Net.data([url.replacingOccurrences(of: "http://", with: "https://")])
        try data.write(to: png, options: .atomic)
        let slim = textures["textures"]["SKIN"]["metadata"]["model"].string == "slim"
        if slim { try? Data().write(to: meta) } else { try? FileManager.default.removeItem(at: meta) }
        return (png, slim)
    }

    // MARK: 微软账号

    package struct Cape: Identifiable, Hashable, Sendable {
        package let id: String
        package let alias: String
        package let url: String
        package let active: Bool
    }

    package struct MinecraftProfile: Sendable {
        package let skinURL: String?
        package let slim: Bool
        package let capes: [Cape]
    }

    static let services = "https://api.minecraftservices.com/minecraft/profile"

    package static func profile(token: String) async throws -> MinecraftProfile {
        let (code, j) = try await Net.request(services, method: "GET", headers: ["Authorization": "Bearer \(token)"])
        guard code == 200 else { throw LauncherError(T("无法读取玩家档案（HTTP \(code)）", "Couldn't read the player profile (HTTP \(code))")) }
        let skin = j["skins"].array.first { $0["state"].string == "ACTIVE" }
        let capes = j["capes"].array.compactMap { c -> Cape? in
            guard let id = c["id"].string else { return nil }
            return Cape(id: id, alias: c["alias"].string ?? id, url: c["url"].string ?? "", active: c["state"].string == "ACTIVE")
        }
        return MinecraftProfile(skinURL: skin?["url"].string, slim: skin?["variant"].string?.uppercased() == "SLIM", capes: capes)
    }

    /// 上传皮肤
    package static func upload(token: String, skin: URL, slim: Bool) async throws {
        let data = try Data(contentsOf: skin)
        try validate(data)
        let boundary = "kiln-\(UUID().uuidString)"
        var body = Data()
        func field(_ s: String) { body.append(Data(s.utf8)) }
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"variant\"\r\n\r\n\(slim ? "slim" : "classic")\r\n")
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\nContent-Type: image/png\r\n\r\n")
        body.append(data)
        field("\r\n--\(boundary)--\r\n")
        let (code, j) = try await Net.request(services + "/skins", body: body, contentType: "multipart/form-data; boundary=\(boundary)",
                                              headers: ["Authorization": "Bearer \(token)"])
        guard code == 200 else { throw LauncherError(T("上传皮肤失败：", "Couldn't upload the skin: ") + (j["errorMessage"].string ?? "HTTP \(code)")) }
    }

    /// 恢复默认皮肤
    package static func reset(token: String) async throws {
        let (code, _) = try await Net.request(services + "/skins/active", method: "DELETE", headers: ["Authorization": "Bearer \(token)"])
        guard code == 200 || code == 204 else { throw LauncherError("HTTP \(code)") }
    }

    /// 选择披风；nil 为不显示
    package static func setCape(token: String, id: String?) async throws {
        let (code, _): (Int, JSON)
        if let id {
            (code, _) = try await Net.request(services + "/capes/active", method: "PUT",
                                              body: JSON.object(["capeId": .string(id)]).data(pretty: false),
                                              contentType: "application/json", headers: ["Authorization": "Bearer \(token)"])
        } else {
            (code, _) = try await Net.request(services + "/capes/active", method: "DELETE", headers: ["Authorization": "Bearer \(token)"])
        }
        guard code == 200 || code == 204 else { throw LauncherError("HTTP \(code)") }
    }
}
