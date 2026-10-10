import Foundation
import CryptoKit

/// 启动器自动更新：从 GitHub Release 获取新版本，校验后替换自身
package enum Updater {
    package static let repository = "Cetirzine/kiln-launcher"
    package static let bundleIdentifier = "app.kiln.launcher"

    package struct Release: Sendable {
        package let version: String
        package let notes: String
        package let pageURL: String
        package let dmgURL: String
        package let dmgName: String
        package let sha256: String?
        package let size: Int64?
    }

    package enum UpdateError: LocalizedError {
        case notInstalledAsApp, translocated, notWritable(String), verification(String)
        package var errorDescription: String? {
            switch self {
            case .notInstalledAsApp:
                return T("当前不是从 Kiln.app 运行的，无法自动更新。", "Kiln isn't running from Kiln.app, so it can't update itself.")
            case .translocated:
                return T("请先把 Kiln 拖到“应用程序”文件夹并从那里打开，然后再更新。", "Move Kiln to the Applications folder and open it from there, then update.")
            case .notWritable(let path):
                return T("没有权限替换 \(path)，请手动下载新版本。", "No permission to replace \(path). Download the new version manually.")
            case .verification(let reason):
                return T("更新包校验失败：\(reason)", "The update failed verification: \(reason)")
            }
        }
    }

    // MARK: 检查

    /// 获取最新版本；比当前版本新时返回 Release
    package static func check() async throws -> Release? {
        let j = try await Net.json(urls: ["https://api.github.com/repos/\(repository)/releases/latest"])
        guard let tag = j["tag_name"].string, j["draft"].bool != true, j["prerelease"].bool != true else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: AppInfo.version) else { return nil }
        guard let dmg = j["assets"].array.first(where: { ($0["name"].string ?? "").hasSuffix(".dmg") }),
              let url = dmg["browser_download_url"].string else { return nil }
        let digest = dmg["digest"].string.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return Release(version: version, notes: j["body"].string ?? "", pageURL: j["html_url"].string ?? "",
                       dmgURL: url, dmgName: dmg["name"].string ?? "Kiln-\(version).dmg",
                       sha256: digest, size: dmg["size"].double.map { Int64($0) })
    }

    /// 语义化版本比较（1.2.10 > 1.2.9）
    package static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// 当前运行的 App 位置；不是以 .app 运行时返回 nil
    package static var currentApp: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// 检查能否原地替换当前 App
    package static func checkReplaceable(_ app: URL) throws {
        // macOS 会把从下载位置直接打开的带隔离属性的 App 放到只读的临时位置运行
        if app.path.contains("/AppTranslocation/") || app.path.hasPrefix("/Volumes/") { throw UpdateError.translocated }
        let parent = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isWritableFile(atPath: app.path) else {
            throw UpdateError.notWritable(app.path)
        }
    }

    // MARK: 下载与准备

    /// 下载并校验新版本，复制到当前 App 旁边，返回准备好的新 App 位置
    package static func prepare(_ release: Release, replacing app: URL, job: Job?) async throws -> URL {
        let fm = FileManager.default
        let dmg = Paths.cache.appendingPathComponent(release.dmgName)
        try? fm.removeItem(at: dmg)
        var item = DownloadItem(url: release.dmgURL, destination: dmg, size: release.size)
        item.urls = [release.dmgURL]
        try await Downloader.run([item], job: job, checkHash: false)
        defer { try? fm.removeItem(at: dmg) }

        // 校验 SHA-256（GitHub 为每个附件提供摘要）
        if let expected = release.sha256?.lowercased() {
            let actual = try sha256(of: dmg)
            guard actual == expected else { throw UpdateError.verification(T("SHA-256 不一致", "SHA-256 mismatch")) }
        }

        // 挂载 DMG，取出 Kiln.app
        let mount = Paths.cache.appendingPathComponent("update-mount-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: mount)
        }
        guard let newApp = (try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.verification(T("安装包中没有找到应用", "No app found in the update"))
        }
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw UpdateError.verification(T("应用标识不符", "Bundle identifier mismatch"))
        }
        guard info?["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError.verification(T("版本号不符", "Version mismatch"))
        }
        // 签名必须完整（未被修改）
        do { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) }
        catch { throw UpdateError.verification(T("签名无效", "Invalid code signature")) }

        // 复制到当前 App 旁边（同一卷上，替换时只需重命名）
        let staged = app.deletingLastPathComponent().appendingPathComponent(".Kiln-update-\(release.version).app")
        try? fm.removeItem(at: staged)
        try run("/usr/bin/ditto", [newApp.path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    // MARK: 替换

    /// 生成替换脚本：等待当前进程退出 → 备份旧版 → 换上新版 → 失败时恢复 → 重新打开
    package static func replaceScript(staged: URL, app: URL, pid: Int32, relaunch: Bool) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let backup = app.deletingLastPathComponent().appendingPathComponent(".Kiln-previous.app")
        return """
        #!/bin/bash
        # 由 Kiln 自动更新生成
        for i in $(seq 1 300); do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done
        rm -rf \(q(backup.path))
        if mv \(q(app.path)) \(q(backup.path)) && mv \(q(staged.path)) \(q(app.path)); then
            rm -rf \(q(backup.path))
        else
            # 替换失败：恢复旧版
            [ -d \(q(app.path)) ] || mv \(q(backup.path)) \(q(app.path))
            rm -rf \(q(staged.path))
        fi
        \(relaunch ? "open \(q(app.path))" : "")
        """
    }

    /// 启动替换脚本（脱离当前进程运行），调用方随后退出应用
    package static func launchReplacement(staged: URL, app: URL, relaunch: Bool = true) throws {
        let script = Paths.cache.appendingPathComponent("kiln-update.sh")
        try replaceScript(staged: staged, app: app, pid: ProcessInfo.processInfo.processIdentifier, relaunch: relaunch)
            .write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        log("[Update] 已启动替换脚本：\(staged.lastPathComponent) → \(app.path)")
    }

    // MARK: 工具

    static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw LauncherError("\((tool as NSString).lastPathComponent) \(p.terminationStatus): \(out.suffix(300))")
        }
        return out
    }
}
