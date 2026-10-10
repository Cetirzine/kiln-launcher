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
