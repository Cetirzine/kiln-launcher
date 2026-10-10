import Foundation
import Observation
import Security

package struct Account: Codable, Identifiable, Hashable {
    package enum Kind: String, Codable { case offline, microsoft }
    package var id: String { "\(kind.rawValue):\(uuid)" }
    package var kind: Kind
    package var name: String
    package var uuid: String
    /// 微软账号的登录已失效（刷新令牌被撤销或过期），需要重新登录
    package var needsLogin: Bool?

    package init(kind: Kind, name: String, uuid: String) {
        self.kind = kind; self.name = name; self.uuid = uuid
    }

    package var typeText: String {
        kind == .microsoft ? T("微软账号", "Microsoft") : T("离线账号", "Offline")
    }

    /// 与原版服务端一致的离线 UUID（UUID v3，"OfflinePlayer:" + 玩家名）
    package static func offlineUUID(_ name: String) -> String {
        var bytes = Hash.md5(Data("OfflinePlayer:\(name)".utf8))
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// 启动时实际使用的登录结果
package struct LoginResult {
    package var name: String
    package var uuid: String
    package var accessToken: String
    package var userType: String
    package var xuid: String = "0"

    package init(name: String, uuid: String, accessToken: String, userType: String, xuid: String = "0") {
        self.name = name; self.uuid = uuid; self.accessToken = accessToken; self.userType = userType; self.xuid = xuid
    }
}

@MainActor
@Observable
package final class AccountStore {
    package static let shared = AccountStore()

    package var accounts: [Account] = []
    package var selectedId: String? { didSet { save() } }
    @ObservationIgnored private var tokenCache: [String: (token: String, expires: Date)] = [:]

    private var file: URL { Paths.support.appendingPathComponent("Accounts.json") }

    private struct Stored: Codable { var accounts: [Account]; var selected: String? }

    private init() {
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            accounts = s.accounts
            selectedId = s.selected
        }
    }

    package var selected: Account? { accounts.first { $0.id == selectedId } ?? accounts.first }

    package func account(id: String?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    /// 某个版本启动时使用的账号：版本指定了且仍存在时用指定的，否则用当前账号
    package func account(for setup: LauncherSettings.InstanceSetup) -> Account? {
        account(id: setup.account) ?? selected
    }

    package func select(_ acc: Account) { selectedId = acc.id }

    /// 按列表位置切换（菜单栏 ⌃⌘1～9）
    package func select(at index: Int) {
        guard accounts.indices.contains(index) else { return }
        selectedId = accounts[index].id
    }

    /// 调整顺序
    package func move(_ acc: Account, by offset: Int) {
        guard let i = accounts.firstIndex(where: { $0.id == acc.id }) else { return }
        let j = min(max(i + offset, 0), accounts.count - 1)
        guard i != j else { return }
        accounts.insert(accounts.remove(at: i), at: j)
        save()
    }

    /// 修改离线账号名称；UUID 随名称重新计算（与服务端离线模式一致）。返回新账号，名称已被占用时返回 nil
    @discardableResult
    package func renameOffline(_ acc: Account, to name: String) -> Account? {
        guard acc.kind == .offline, let i = accounts.firstIndex(where: { $0.id == acc.id }) else { return nil }
        let renamed = Account(kind: .offline, name: name, uuid: Account.offlineUUID(name))
        if renamed.id != acc.id && accounts.contains(where: { $0.id == renamed.id }) { return nil }
        let wasSelected = selected?.id == acc.id
        accounts[i] = renamed
        if wasSelected { selectedId = renamed.id }
        save()
        return renamed
    }

    package func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try? enc.encode(Stored(accounts: accounts, selected: selectedId)).write(to: file, options: .atomic)
    }

    /// 校验离线玩家名（对应原版 McLoginAble）
    nonisolated package static func validateOffline(_ name: String) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return T("请输入名称", "Enter a name") }
        if name.contains("\"") { return T("名称不能包含引号", "The name can't contain quotes") }
        return nil
    }

    package func addOffline(_ name: String) {
        let acc = Account(kind: .offline, name: name, uuid: Account.offlineUUID(name))
        accounts.removeAll { $0.id == acc.id }
        accounts.insert(acc, at: 0)
        selectedId = acc.id
        save()
    }

    package func remove(_ acc: Account) {
        accounts.removeAll { $0.id == acc.id }
        if acc.kind == .microsoft { Keychain.delete(acc.uuid) }
        if selectedId == acc.id { selectedId = accounts.first?.id }
        save()
    }

    package func addMicrosoft(profile: (name: String, uuid: String), refreshToken: String, accessToken: String, expires: Date) {
        let acc = Account(kind: .microsoft, name: profile.name, uuid: profile.uuid)
        // 重新登录已有账号时保持原来的位置
        if let i = accounts.firstIndex(where: { $0.id == acc.id }) {
            accounts[i] = acc
        } else {
            accounts.insert(acc, at: 0)
        }
        Keychain.set(refreshToken, for: acc.uuid)
        tokenCache[acc.uuid] = (accessToken, expires)
        selectedId = acc.id
        save()
    }

    private func setNeedsLogin(_ acc: Account, _ value: Bool) {
        guard let i = accounts.firstIndex(where: { $0.id == acc.id }) else { return }
        accounts[i].needsLogin = value ? true : nil
        save()
    }

    /// 启动前登录
    package func login(_ acc: Account) async throws -> LoginResult {
        switch acc.kind {
        case .offline:
            return LoginResult(name: acc.name, uuid: acc.uuid, accessToken: acc.uuid, userType: "legacy")
        case .microsoft:
            if let c = tokenCache[acc.uuid], c.expires > Date().addingTimeInterval(300) {
                return LoginResult(name: acc.name, uuid: acc.uuid, accessToken: c.token, userType: "msa")
            }
            guard let refresh = Keychain.get(acc.uuid) else {
                setNeedsLogin(acc, true)
                throw LauncherError(T("正版登录已过期，请重新登录。", "Your Microsoft login expired. Please sign in again."))
            }
            let r: MicrosoftAuth.Result
            do {
                r = try await MicrosoftAuth.refresh(refresh)
            } catch {
                // 网络问题不代表登录失效
                if !Net.isTransient(error) { setNeedsLogin(acc, true) }
                throw error
            }
            Keychain.set(r.refreshToken, for: acc.uuid)
            tokenCache[acc.uuid] = (r.accessToken, r.expires)
            if let i = accounts.firstIndex(where: { $0.id == acc.id }), accounts[i].name != r.name || accounts[i].needsLogin == true {
                accounts[i].name = r.name
                accounts[i].needsLogin = nil
                save()
            }
            return LoginResult(name: r.name, uuid: r.uuid, accessToken: r.accessToken, userType: "msa")
        }
    }
}

// MARK: - 微软正版登录（设备代码流）

package enum MicrosoftAuth {
    package struct DeviceCode {
        package let userCode: String
        package let deviceCode: String
        package let verificationURI: String
        package let interval: Int
        package let expiresIn: Int
    }

    package struct Result {
        package let name: String
        package let uuid: String
        package let accessToken: String
        package let refreshToken: String
        package let expires: Date
    }

    package static let scope = "XboxLive.signin offline_access"

    package static func clientId() throws -> String {
        let id = LauncherSettings.shared.effectiveClientId
        if id.isEmpty { throw LauncherError(T("尚未设置微软登录所需的 Client ID。\n请在 设置 → 其他 中填写 Azure 应用 ID。", "The Client ID for Microsoft login is not set.\nEnter your Azure application ID in Settings → Other.")) }
        return id
    }

    package static func requestDeviceCode() async throws -> DeviceCode {
        let (code, j) = try await Net.request(
            "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
            body: Net.formBody(["client_id": try clientId(), "scope": scope]),
            contentType: "application/x-www-form-urlencoded")
        guard code == 200, let user = j["user_code"].string, let device = j["device_code"].string else {
            throw LauncherError(j["error_description"].string ?? "HTTP \(code)")
        }
        return DeviceCode(userCode: user, deviceCode: device,
                          verificationURI: j["verification_uri"].string ?? "https://www.microsoft.com/link",
                          interval: j["interval"].int ?? 5, expiresIn: j["expires_in"].int ?? 900)
    }

    /// 轮询，直到用户在浏览器中完成登录
    package static func poll(_ dc: DeviceCode) async throws -> (access: String, refresh: String) {
        var interval = max(dc.interval, 2)
        let deadline = Date().addingTimeInterval(TimeInterval(dc.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let j: JSON
            do {
                (_, j) = try await Net.request(
                    "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
                    body: Net.formBody(["client_id": try clientId(), "device_code": dc.deviceCode,
                                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]),
                    contentType: "application/x-www-form-urlencoded")
            } catch where Net.isTransient(error) {
                // 网络暂时中断时继续等待，下一轮再查询
                continue
            }
            if let a = j["access_token"].string, let r = j["refresh_token"].string { return (a, r) }
            switch j["error"].string {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "authorization_declined": throw LauncherError(T("登录已取消", "Sign-in cancelled"))
            case "expired_token": throw LauncherError(T("登录代码已过期，请重试。", "The login code expired. Please try again."))
            default: throw LauncherError(j["error_description"].string ?? T("登录失败", "Sign-in failed"))
            }
        }
        throw LauncherError(T("登录代码已过期，请重试。", "The login code expired. Please try again."))
    }

    package static func refresh(_ refreshToken: String) async throws -> Result {
        let (_, j) = try await Net.request(
            "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
            body: Net.formBody(["client_id": try clientId(), "refresh_token": refreshToken,
                                "grant_type": "refresh_token", "scope": scope]),
            contentType: "application/x-www-form-urlencoded")
        guard let a = j["access_token"].string else {
            throw LauncherError(T("正版登录已过期，请重新登录。", "Your Microsoft login expired. Please sign in again.") + "\n" + (j["error_description"].string ?? ""))
        }
        return try await minecraft(msAccess: a, refresh: j["refresh_token"].string ?? refreshToken)
    }

    /// Microsoft → Xbox Live → XSTS → Minecraft
    package static func minecraft(msAccess: String, refresh: String) async throws -> Result {
        let json = "application/json"
        // XBL
        let xblBody = JSON.object([
            "Properties": .object(["AuthMethod": .string("RPS"), "SiteName": .string("user.auth.xboxlive.com"),
                                   "RpsTicket": .string("d=\(msAccess)")]),
            "RelyingParty": .string("http://auth.xboxlive.com"), "TokenType": .string("JWT"),
        ])
        let (_, xbl) = try await Net.request("https://user.auth.xboxlive.com/user/authenticate", body: xblBody.data(pretty: false), contentType: json)
        guard let xblToken = xbl["Token"].string, let uhs = xbl["DisplayClaims"]["xui"][0]["uhs"].string else {
            throw LauncherError(T("登录失败", "Sign-in failed") + " (XBL)")
        }
        // XSTS
        let xstsBody = JSON.object([
            "Properties": .object(["SandboxId": .string("RETAIL"), "UserTokens": .array([.string(xblToken)])]),
            "RelyingParty": .string("rp://api.minecraftservices.com/"), "TokenType": .string("JWT"),
        ])
        let (xstsCode, xsts) = try await Net.request("https://xsts.auth.xboxlive.com/xsts/authorize", body: xstsBody.data(pretty: false), contentType: json)
        if xstsCode == 401 {
            switch xsts["XErr"].double.map({ Int64($0) }) {
            case 2148916233: throw LauncherError(T("该微软账号还没有 Xbox 档案，请先在 xbox.com 登录一次。", "This Microsoft account has no Xbox profile yet. Sign in at xbox.com once first."))
            case 2148916235: throw LauncherError(T("你所在的地区无法使用 Xbox Live，请更换网络后重试。", "Xbox Live isn't available in your region. Try another network."))
            case 2148916236, 2148916237, 2148916238: throw LauncherError(T("该账号为未成年账号，需要家长在 Xbox 家庭设置中允许后才能登录。", "This is a child account; a parent must allow it in Xbox family settings."))
            default: break
            }
        }
        guard let xstsToken = xsts["Token"].string else { throw LauncherError(T("登录失败", "Sign-in failed") + " (XSTS \(xstsCode))") }
        // Minecraft
        let mcBody = JSON.object(["identityToken": .string("XBL3.0 x=\(uhs);\(xstsToken)")])
        let (mcCode, mc) = try await Net.request("https://api.minecraftservices.com/authentication/login_with_xbox", body: mcBody.data(pretty: false), contentType: json)
        guard let mcToken = mc["access_token"].string else {
            let detail = mc["errorMessage"].string ?? mc["error"].string ?? ""
            log("[Auth] login_with_xbox 失败：HTTP \(mcCode) \(detail)")
            if mcCode == 403 || detail.contains("Invalid app registration") {
                throw LauncherError(T("微软账号已验证，但这个启动器的 Client ID 还没有获准使用 Minecraft 接口。需要用该 ID 向微软申请 Minecraft API 访问权限（详见 https://aka.ms/AppRegInfo），批准后即可登录。",
                                      "Your Microsoft account was verified, but this launcher's Client ID isn't approved for the Minecraft API yet. Request Minecraft API access for this ID (see https://aka.ms/AppRegInfo); sign-in will work once it's approved."))
            }
            if mcCode == 429 {
                throw LauncherError(T("请求过于频繁，请稍后再试。", "Too many requests. Try again in a little while."))
            }
            throw LauncherError(T("登录失败（Minecraft，HTTP \(mcCode)）", "Sign-in failed (Minecraft, HTTP \(mcCode))") + (detail.isEmpty ? "" : "：\(detail)"))
        }
        let expires = Date().addingTimeInterval(TimeInterval(mc["expires_in"].int ?? 86400))
        // 档案
        let (pCode, profile) = try await Net.request("https://api.minecraftservices.com/minecraft/profile", method: "GET",
                                                     headers: ["Authorization": "Bearer \(mcToken)"])
        if pCode == 404 { throw LauncherError(T("该账号没有 Minecraft: Java Edition，或 Game Pass 已过期。", "This account doesn't own Minecraft: Java Edition, or Game Pass has expired.")) }
        guard let id = profile["id"].string, let name = profile["name"].string else {
            throw LauncherError(T("请先在 minecraft.net 创建玩家档案。", "Create a player profile at minecraft.net first."))
        }
        return Result(name: name, uuid: id, accessToken: mcToken, refreshToken: refresh, expires: expires)
    }
}

// MARK: - 钥匙串

package enum Keychain {
    package static let service = "\(AppInfo.shortName).MicrosoftRefreshToken"

    package static func set(_ value: String, for account: String) {
        delete(account)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    package static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    package static func delete(_ account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
