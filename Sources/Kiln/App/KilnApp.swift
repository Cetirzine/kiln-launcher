import SwiftUI
import AppKit
import Observation
import LauncherCore

struct KilnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @PState private var state = AppState.shared

    var body: some Scene {
        Window(AppInfo.shortName, id: "main") {
            MainView()
                .environment(state)
                .frame(minWidth: 860, minHeight: 540)
                .onAppear { state.refreshInstances() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(T("关于 \(AppInfo.shortName)", "About \(AppInfo.shortName)")) {
                    state.page = .about
                    state.subPage = nil
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(T("游戏", "Game")) {
                Button(T("开始游戏", "Play")) { state.launchSelected() }
                    .keyboardShortcut("l", modifiers: .command)
                Button(T("版本", "Instances")) { state.subPage = nil; state.page = .instances }
                    .keyboardShortcut("i", modifiers: .command)
                Button(T("打开游戏文件夹", "Open game folder")) { NSWorkspace.shared.open(LauncherSettings.shared.minecraftURL) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(T("刷新", "Refresh")) { state.refreshInstances() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button(T("设置…", "Settings…")) { state.page = .setup; state.subPage = nil }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("[Start] \(AppInfo.shortName) \(AppInfo.version)，macOS \(RuleContext.osVersion)，\(Arch.native)，内存 \(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024) GB")
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Links {
    static let buyMinecraft = "https://www.minecraft.net/store/minecraft-java-bedrock-edition-pc"
    /// 署名：Plain Craft Launcher 2（龙腾猫跃）
    static let pcl2 = "https://github.com/Meloong-Git/PCL"
    static let pcl2Author = "https://space.bilibili.com/11343203"
    static let hmcl = "https://github.com/HMCL-dev/HMCL"
    static let metalUniversal = MetalRenderer.homepage
    static let bmclapi = "https://bmclapi.bangbang93.com"

    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

/// 全局界面状态
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    enum Page: String, CaseIterable { case home, instances, download, setup, about }
    enum SubPage: Equatable {
        case instanceSetup(McInstance), log(GameProcess)
        static func == (a: SubPage, b: SubPage) -> Bool {
            switch (a, b) {
            case let (.instanceSetup(x), .instanceSetup(y)): return x == y
            case let (.log(x), .log(y)): return x === y
            default: return false
            }
        }
    }
    enum DownloadSection: Hashable { case game, mod, resourcepack, shader, manager }
    enum SetupSection: Hashable { case game, performance, java, download, other }

    var page: Page = .home { didSet { if page != oldValue { refreshInstances() } } }
    /// 游戏目录中的版本或 Mod 发生变化时递增，用于刷新 Mod 列表等界面
    var fileRevision = 0
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var watchedFolder: String?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    var downloadSection: DownloadSection = .game
    var setupSection: SetupSection = .game
    var subPage: SubPage? { didSet { if subPage != oldValue { refreshInstances() } } }
    var instances: [McInstance] = []
    var loadingInstances = false
    var games: [GameProcess] = []
    var launchJob: Job?

    var showLog: GameProcess? {
        get { if case .log(let g) = subPage { return g }; return nil }
        set { subPage = newValue.map { .log($0) } }
    }

    var selectedInstance: McInstance? {
        instances.first { $0.name == LauncherSettings.shared.selectedInstance } ?? instances.first { $0.category != .error }
    }

    /// 开始监视游戏目录，并在 App 回到前台时刷新
    func startAutoRefresh() {
        let folder = LauncherSettings.shared.minecraftURL
        if watchedFolder != folder.path {
            watchedFolder = folder.path
            if watcher == nil {
                watcher = FolderWatcher { [weak self] in
                    self?.fileRevision += 1
                    self?.refreshInstances()
                }
            }
            watcher?.watch(folder)
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AppState.shared.fileRevision += 1
                    AppState.shared.refreshInstances()
                }
            }
        }
    }

    func refreshInstances() {
        startAutoRefresh()
        loadingInstances = true
        let folder = LauncherSettings.shared.minecraftURL
        Task.detached(priority: .userInitiated) {
            let list = InstanceScanner.scan(folder)
            await MainActor.run {
                self.instances = list
                self.loadingInstances = false
            }
            await BlockTextures.shared.load(from: list)
        }
    }

    func select(_ instance: McInstance) {
        LauncherSettings.shared.selectedInstance = instance.name
    }

    var isLaunching: Bool { launchJob?.state == .running }

    func launchSelected(options: LaunchOptions = LaunchOptions()) {
        guard !isLaunching else { return }
        guard let instance = selectedInstance else {
            Hint.show(T("还没有安装任何版本", "No instances installed"), .red)
            page = .download
            return
        }
        guard let account = AccountStore.shared.selected else {
            Hint.show(T("请先在右上角添加账号", "Add an account in the top-right corner first"), .red)
            return
        }
        let callbacks = LaunchCallbacks(onWindow: { _ in Self.onGameWindow() }, onExit: { Self.onGameExit($0, instance: instance) })
        launchJob = JobCenter.shared.start(T("启动 \(instance.name)", "Launch \(instance.name)"), silent: true) { job in
            do {
                if let game = try await Launcher.launch(instance, account: account, options: options, job: job, callbacks: callbacks) {
                    self.games.insert(game, at: 0)
                } else {
                    Hint.show(T("启动脚本已导出", "Launch script exported"), .green)
                }
            } catch is CancellationError {
                Hint.show(T("已取消启动", "Launch cancelled"), .blue)
                throw CancellationError()
            } catch {
                _ = await MsgBox.show(title: T("无法启动", "Couldn't launch"), content: error.friendly,
                                      buttons: [T("好", "OK")], warn: true)
                throw error
            }
        }
    }

    func cancelLaunch() { launchJob?.cancel() }

    // MARK: 游戏进程事件

    static func onGameWindow() {
        Hint.show(T("游戏已启动", "Game started"), .green)
        switch LauncherSettings.shared.visibility {
        case .closeOnStart: NSApp.terminate(nil)
        case .hideAndClose, .hideAndReopen: NSApp.hide(nil)
        case .minimize: NSApp.windows.forEach { $0.miniaturize(nil) }
        case .keep: break
        }
    }

    static func onGameExit(_ game: GameProcess, instance: McInstance) {
        switch LauncherSettings.shared.visibility {
        case .hideAndClose where game.state != .crashed:
            NSApp.terminate(nil)
            return
        case .hideAndReopen, .hideAndClose:
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
        default: break
        }
        guard game.state == .crashed else { return }
        let finding = CrashAnalyzer.analyze(game.lines, gameDir: instance.gameDir)
        var content = T("游戏异常退出（返回值 \(game.exitCode ?? -1)）。", "The game exited unexpectedly (exit code \(game.exitCode ?? -1)).")
        if let f = finding {
            content += "\n\n" + T("可能原因：", "Likely cause: ") + f.reason
            if let d = f.detail { content += "\n" + T("相关：", "Related: ") + d }
        }
        Task { @MainActor in
            let r = await MsgBox.show(title: T("游戏崩溃", "Game crashed"), content: content,
                                      buttons: [T("查看日志", "View log"), T("好", "OK")], warn: true)
            if r == 1 { AppState.shared.showLog = game }
        }
    }
}

/// 后台任务列表（安装、下载等），在“任务”页显示
@MainActor
@Observable
final class JobCenter {
    static let shared = JobCenter()
    var jobs: [Job] = []

    var running: [Job] { jobs.filter { $0.state == .running } }

    /// 启动一个后台任务，结束后自动提示
    @discardableResult
    func start(_ title: String, silent: Bool = false, _ body: @escaping @MainActor (Job) async throws -> Void) -> Job {
        let job = Job(title: title)
        jobs.insert(job, at: 0)
        job.task = Task { @MainActor in
            do {
                try await body(job)
                job.state = .success
                job.stage = T("完成", "Done")
                if !silent { Hint.show(T("\(title) 已完成", "\(title) finished"), .green) }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    job.state = .cancelled
                    job.stage = T("已取消", "Cancelled")
                } else {
                    job.state = .failed
                    job.error = error.friendly
                    job.stage = T("失败", "Failed")
                    log("[Job] \(title) 失败：\(error.friendly)")
                    if !silent { Hint.show(T("\(title) 失败：\(error.friendly)", "\(title) failed: \(error.friendly)"), .red) }
                }
            }
        }
        return job
    }

    func clearFinished() {
        jobs.removeAll { $0.state != .running }
    }
}
