import Foundation
import LauncherCore

/// 程序入口：`--self-test` 运行自检，`--launch-test <版本> <目录> [Fabric|Forge|NeoForge]` 运行完整的安装与启动测试，否则启动界面。
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            exit(SelfTest.runUnit() ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--launch-test"), args.count > i + 2 {
            let loader = args.count > i + 3 ? args[i + 3] : nil
            let ok = SelfTest.runLaunch(version: args[i + 1], folder: URL(fileURLWithPath: args[i + 2]), loader: loader)
            exit(ok ? 0 : 1)
        }
        // 更新测试：检查、下载、校验并替换当前 App（不重新打开）
        if args.contains("--update-test") {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var code: Int32 = 1
            Task {
                defer { sem.signal() }
                do {
                    print("当前版本：\(AppInfo.version)，位置：\(Updater.currentApp?.path ?? "非 App")")
                    guard let release = try await Updater.check() else { print("没有新版本"); code = 0; return }
                    print("发现新版本：\(release.version)，SHA-256：\(release.sha256 ?? "无")")
                    guard let app = Updater.currentApp else { print("✘ 不是以 App 运行"); return }
                    try Updater.checkReplaceable(app)
                    let staged = try await Updater.prepare(release, replacing: app, job: nil)
                    print("已准备：\(staged.path)")
                    try Updater.launchReplacement(staged: staged, app: app, relaunch: false)
                    print("✔ 已启动替换，进程退出后完成")
                    code = 0
                } catch { print("✘ \(error.friendly)") }
            }
            while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            exit(code)
        }
        if args.contains("--mod-search-check") {
            ModSearchCheck.run()
            exit(0)
        }
        if let i = args.firstIndex(of: "--modpack-install-test"), args.count > i + 2 {
            exit(ModpackInstallCheck.run(source: args[i + 1], folder: URL(fileURLWithPath: args[i + 2])) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--import-test"), args.count > i + 2 {
            exit(ImportCheck.run(source: URL(fileURLWithPath: args[i + 1]), folder: URL(fileURLWithPath: args[i + 2])) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--diagnostics-check"), args.count > i + 3 {
            exit(DiagnosticsCheck.run(folder: URL(fileURLWithPath: args[i + 1]), name: args[i + 2], output: URL(fileURLWithPath: args[i + 3])) ? 0 : 1)
        }
        if args.contains("--skin-check") {
            exit(SkinCheck.run() ? 0 : 1)
        }
        if args.contains("--profile-check") {
            exit(ProfileCheck.run() ? 0 : 1)
        }
        if args.contains("--mod-core-check") {
            exit(ModCoreCheck.run() ? 0 : 1)
        }
        if args.contains("--modrinth-check") {
            ModrinthCheck.run()
            exit(0)
        }
        if let i = args.firstIndex(of: "--download-bench"), args.count > i + 1 {
            DownloadBench.run(folder: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            let folder = args.count > i + 2 ? URL(fileURLWithPath: args[i + 2]) : nil
            Task { @MainActor in
                await Snapshot.run(to: URL(fileURLWithPath: args[i + 1]), folder: folder)
                exit(0)
            }
            RunLoop.main.run()
        }
        KilnApp.main()
    }
}
