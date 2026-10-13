import Foundation
import CryptoKit

/// 外置登录（authlib-injector / Yggdrasil 协议），如 LittleSkin。
/// 只保存服务器下发的令牌（本机的 Tokens.json），不保存密码；令牌失效时再请用户输入密码。
package enum Yggdrasil {
    package struct Profile: Hashable, Sendable { package let id: String; package let name: String }

    package struct Session: Sendable {
        package let accessToken: String
        package let clientToken: String
        package let profiles: [Profile]
        package let selected: Profile?
    }

    /// 常用的皮肤站
    package static let presets: [(name: String, url: String)] = [("LittleSkin", "https://littleskin.cn/api/yggdrasil")]

    /// 解析用户输入的地址：补全 https，按 authlib-injector 的 API 地址指示（ALI）找到真正的 API 根地址，并读取元数据
    package static func resolve(_ input: String) async throws -> (root: String, meta: JSON) {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard var url = URL(string: s) else { throw LauncherError(T("地址无效", "Invalid address")) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let (_, resp) = try? await Net.session.data(for: req), let http = resp as? HTTPURLResponse,
           let ali = http.value(forHTTPHeaderField: "X-Authlib-Injector-API-Location"),
           let resolved = URL(string: ali, relativeTo: url)?.absoluteURL {
            // 不接受从 https 降级到 http
            if !(url.scheme == "https" && resolved.scheme == "http") { url = resolved }
        }
        var root = url.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        let meta = try await Net.json(urls: [root])
        guard meta["meta"].exists || meta["skinDomains"].exists else {
            throw LauncherError(T("这个地址不是 authlib-injector 认证服务器", "This address isn't an authlib-injector authentication server"))
        }
        return (root, meta)
    }

    package static func serverName(_ meta: JSON, root: String) -> String {
        meta["meta"]["serverName"].string ?? URL(string: root)?.host ?? root
    }

    private static func post(_ url: String, _ body: JSON) async throws -> (Int, JSON) {
        try await Net.request(url, body: body.data(pretty: false), contentType: "application/json")
    }

    private static func check(_ code: Int, _ j: JSON) throws {
        guard code >= 200 && code < 300 else {
            let msg = j["errorMessage"].string ?? j["error"].string ?? "HTTP \(code)"
            if j["error"].string == "ForbiddenOperationException" {
                throw LauncherError(T("账号或密码错误，或登录已失效：\(msg)", "Wrong email or password, or the session expired: \(msg)"))
            }
            throw LauncherError(msg)
        }
    }

    private static func profiles(_ j: JSON) -> [Profile] {
        j.array.compactMap { p in p["id"].string.flatMap { id in p["name"].string.map { Profile(id: id, name: $0) } } }
    }

    /// 用账号密码登录（密码只用于这一次请求）
    package static func authenticate(root: String, username: String, password: String) async throws -> Session {
        let body = JSON.object(["agent": .object(["name": .string("Minecraft"), "version": .number(1)]),
                                "username": .string(username), "password": .string(password),
                                "clientToken": .string(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
                                "requestUser": .bool(false)])
        let (code, j) = try await post(root + "/authserver/authenticate", body)
        try check(code, j)
        guard let access = j["accessToken"].string else { throw LauncherError(T("登录失败", "Sign-in failed")) }
        let selected = j["selectedProfile"]["id"].string.map { Profile(id: $0, name: j["selectedProfile"]["name"].string ?? "") }
        return Session(accessToken: access, clientToken: j["clientToken"].string ?? "", profiles: profiles(j["availableProfiles"]), selected: selected)
    }

    /// 刷新令牌；可同时选择角色
    package static func refresh(root: String, accessToken: String, clientToken: String, select: Profile? = nil) async throws -> Session {
        var body: [String: JSON] = ["accessToken": .string(accessToken), "clientToken": .string(clientToken), "requestUser": .bool(false)]
        if let select { body["selectedProfile"] = .object(["id": .string(select.id), "name": .string(select.name)]) }
        let (code, j) = try await post(root + "/authserver/refresh", .object(body))
        try check(code, j)
        guard let access = j["accessToken"].string else { throw LauncherError(T("登录失败", "Sign-in failed")) }
        let selected = j["selectedProfile"]["id"].string.map { Profile(id: $0, name: j["selectedProfile"]["name"].string ?? "") } ?? select
        return Session(accessToken: access, clientToken: j["clientToken"].string ?? clientToken, profiles: [], selected: selected)
    }

    /// 令牌是否仍然有效
    package static func validate(root: String, accessToken: String, clientToken: String) async -> Bool {
        let body = JSON.object(["accessToken": .string(accessToken), "clientToken": .string(clientToken)])
        guard let (code, _) = try? await post(root + "/authserver/validate", body) else { return false }
        return code == 204 || code == 200
    }
}

// MARK: - authlib-injector

package enum AuthlibInjector {
    static var jar: URL { Paths.support.appendingPathComponent("authlib-injector.jar") }

    /// 获取 authlib-injector（每天最多检查一次新版本），返回 jar 位置
    package static func ensure() async throws -> URL {
        let fm = FileManager.default
        let stamp = Paths.support.appendingPathComponent("authlib-injector.checked")
        if fm.fileExists(atPath: jar.path),
           let d = (try? stamp.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(d) < 24 * 3600 {
            return jar
        }
        do {
            let info = try await Net.json(urls: ["https://authlib-injector.yushi.moe/artifact/latest.json",
                                                 "https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json"])
            guard let url = info["download_url"].string else { throw LauncherError("authlib-injector") }
            let sha256 = info["checksums"]["sha256"].string?.lowercased()
            if !(fm.fileExists(atPath: jar.path) && sha256 != nil && fileSHA256(jar) == sha256) {
                let tmp = jar.appendingPathExtension("download")
                try? fm.removeItem(at: tmp)
                var item = DownloadItem(url: url, destination: tmp)
                item.urls = [url, url.replacingOccurrences(of: "https://authlib-injector.yushi.moe/", with: "https://bmclapi2.bangbang93.com/mirrors/authlib-injector/")]
                try await Downloader.fetch(item)
                if let sha256, fileSHA256(tmp) != sha256 {
                    try? fm.removeItem(at: tmp)
                    throw LauncherError(T("authlib-injector 校验失败", "authlib-injector failed verification"))
                }
                try? fm.removeItem(at: jar)
                try fm.moveItem(at: tmp, to: jar)
                log("[Auth] 已下载 authlib-injector \(info["version"].string ?? "")")
            }
            try? Data().write(to: stamp)
        } catch {
            // 网络不可用时继续使用已有的版本
            if fm.fileExists(atPath: jar.path) { return jar }
            throw error
        }
        return jar
    }

    static func fileSHA256(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// 启动参数：加载 authlib-injector 并指定认证服务器（附带预先取得的元数据，省去一次请求）
    package static func jvmArgs(root: String, meta: JSON?) async throws -> [String] {
        let jar = try await ensure()
        var args = ["-javaagent:\(jar.path)=\(root)"]
        if let meta { args.append("-Dauthlibinjector.yggdrasil.prefetched=\(meta.data(pretty: false).base64EncodedString())") }
        return args
    }
}
