import Foundation

/// 微软正版账号的 Minecraft 服务接口（api.minecraftservices.com）：改名、拥有的游戏、联机与聊天权限、封禁状态
package enum MinecraftServices {
    static let root = "https://api.minecraftservices.com"

    private static func get(_ path: String, token: String) async throws -> (Int, JSON) {
        try await Net.request(root + path, method: "GET", headers: ["Authorization": "Bearer \(token)"])
    }

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: 改名

    package struct NameChange: Sendable {
        /// 上次改名的时间（没改过名时是档案创建时间）
        package let changedAt: Date?
        package let allowed: Bool
        /// 改名间隔 30 天，到这个时间才能再改
        package var nextChange: Date? { changedAt.map { $0.addingTimeInterval(30 * 24 * 3600) } }
    }

    package static func nameChange(token: String) async throws -> NameChange {
        let (code, j) = try await get("/minecraft/profile/namechange", token: token)
        guard code == 200 else { throw LauncherError(T("无法读取改名信息（HTTP \(code)）", "Couldn't read name change info (HTTP \(code))")) }
        return NameChange(changedAt: date(j["changedAt"].string) ?? date(j["createdAt"].string), allowed: j["nameChangeAllowed"].bool ?? false)
    }

    package enum NameStatus: Sendable { case available, taken, notAllowed }

    package static func nameStatus(_ name: String, token: String) async throws -> NameStatus {
        let (code, j) = try await get("/minecraft/profile/name/\(name)/available", token: token)
        guard code == 200 else { throw LauncherError("HTTP \(code)") }
        switch j["status"].string {
        case "AVAILABLE": return .available
        case "DUPLICATE": return .taken
        default: return .notAllowed
        }
    }

    /// 合法的 Java 版玩家名：3～16 个字母、数字或下划线
    package static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil
    }

    /// 改名，返回新的名称
    package static func changeName(to name: String, token: String) async throws -> String {
        let (code, j) = try await Net.request(root + "/minecraft/profile/name/\(name)", method: "PUT",
                                              headers: ["Authorization": "Bearer \(token)"])
        switch code {
        case 200: return j["name"].string ?? name
        case 400: throw LauncherError(T("名称不合法：只能用 3～16 个字母、数字或下划线。", "Invalid name: use 3–16 letters, digits or underscores."))
        case 403: throw LauncherError(T("现在还不能改名：距离上次改名需要满 30 天。", "You can't change your name yet: it's been less than 30 days since the last change."))
        case 409: throw LauncherError(T("这个名称已经被别人用了。", "That name is already taken."))
        case 429: throw LauncherError(T("请求过于频繁，请稍后再试。", "Too many requests. Try again in a little while."))
        default:
            let detail = j["errorMessage"].string ?? j["details"]["status"].string ?? ""
            throw LauncherError(T("改名失败（HTTP \(code)）", "Couldn't change the name (HTTP \(code))") + (detail.isEmpty ? "" : "：\(detail)"))
        }
    }

    // MARK: 拥有的游戏

    package struct Ownership: Sendable {
        /// 买断了 Java 版（否则多半是 Xbox Game Pass）
        package let javaPurchased: Bool
        package let bedrock: Bool
        package let dungeons: Bool
        package let legends: Bool
    }

    package static func ownership(token: String) async throws -> Ownership {
        let (code, j) = try await get("/entitlements/mcstore", token: token)
        guard code == 200 else { throw LauncherError(T("无法读取拥有的游戏（HTTP \(code)）", "Couldn't read owned games (HTTP \(code))")) }
        let names = Set(j["items"].array.compactMap { $0["name"].string })
        return Ownership(javaPurchased: names.contains("game_minecraft") || names.contains("product_minecraft"),
                         bedrock: names.contains("game_minecraft_bedrock") || names.contains("product_minecraft_bedrock"),
                         dungeons: names.contains("game_dungeons") || names.contains("product_dungeons"),
                         legends: names.contains("game_legends") || names.contains("product_legends"))
    }

    // MARK: 权限与封禁

    package struct Ban: Sendable {
        package let expires: Date?
        package let reason: String?
    }

    package struct Attributes: Sendable {
        package let multiplayer: Bool
        package let realms: Bool
        package let chat: Bool
        /// 联机封禁（被封禁时不能进入多人服务器和 Realms）
        package let multiplayerBan: Ban?
    }

    package static func attributes(token: String) async throws -> Attributes {
        let (code, j) = try await get("/player/attributes", token: token)
        guard code == 200 else { throw LauncherError(T("无法读取账号状态（HTTP \(code)）", "Couldn't read account status (HTTP \(code))")) }
        let p = j["privileges"]
        var ban: Ban?
        let scope = j["banStatus"]["bannedScopes"]["MULTIPLAYER"]
        if !scope.object.isEmpty {
            let expires = scope["expires"].double.map { Date(timeIntervalSince1970: $0 / 1000) }
            ban = Ban(expires: expires, reason: scope["reasonMessage"].string ?? scope["reason"].string)
        }
        return Attributes(multiplayer: p["multiplayerServer"]["enabled"].bool ?? true,
                          realms: p["multiplayerRealms"]["enabled"].bool ?? true,
                          chat: p["onlineChat"]["enabled"].bool ?? true,
                          multiplayerBan: ban)
    }
}

extension AccountStore {
    /// 正版账号改名后同步本地保存的名称
    package func updateName(_ acc: Account, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == acc.id }) else { return }
        accounts[i].name = name
        save()
    }
}
