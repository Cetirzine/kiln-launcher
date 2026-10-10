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
            CommandGroup(after: .appInfo) {
                Button(T("检查更新…", "Check for Updates…")) { Task { await state.checkForUpdates(userInitiated: true) } }
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
            AccountCommands(state: state)
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
        // 启动后在后台检查更新
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await AppState.shared.checkForUpdates(userInitiated: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Links {
    static let buyMinecraft = "https://www.minecraft.net/store/minecraft-java-bedrock-edition-pc"
    /// 署名：Plain Craft Launcher 2（龙腾猫跃）
    static let pcl2 = "https://github.com/Meloong-Git/PCL"
    static let repository = "https://github.com/\(Updater.repository)"
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

    // MARK: 账号

    /// 显示账号弹窗（右上角）
    var showAccounts = false
    /// 版本固定账号变化时递增，用于刷新界面
    var pinRevision = 0

    /// 版本固定使用的账号（账号已删除时为 nil）
    func pinnedAccount(_ instance: McInstance?) -> Account? {
        _ = pinRevision
        guard let instance else { return nil }
        return AccountStore.shared.account(id: instance.setup.account)
    }

    /// 选中版本启动时实际使用的账号
    var effectiveAccount: Account? { pinnedAccount(selectedInstance) ?? AccountStore.shared.selected }

    func pin(_ account: Account?, to instance: McInstance) {
        var setup = instance.setup
        setup.account = account?.id
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)
        pinRevision += 1
    }

    /// 离线账号改名后，把固定使用旧账号的版本改为新账号
    func repin(from old: String, to new: String) {
        for i in instances where i.setup.account == old {
            var setup = i.setup
            setup.account = new
            LauncherSettings.shared.saveInstanceSetup(setup, i.dir)
        }
        pinRevision += 1
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
        if let pinned = instance.setup.account, AccountStore.shared.account(id: pinned) == nil {
            Hint.show(T("\(instance.name) 固定使用的账号已删除，改用当前账号", "The account pinned to \(instance.name) was removed; using the current account"), .blue)
        }
        guard let account = AccountStore.shared.account(for: instance.setup) else {
            Hint.show(T("请先在右上角添加账号", "Add an account in the top-right corner first"), .red)
            showAccounts = true
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
                // 微软账号登录失效时，可以直接重新登录
                let expired = AccountStore.shared.account(id: account.id)?.needsLogin == true
                let choice = await MsgBox.show(title: T("无法启动", "Couldn't launch"), content: error.friendly,
                                               buttons: expired ? [T("重新登录", "Sign in again"), T("好", "OK")] : [T("好", "OK")], warn: true)
                if expired && choice == 1 { self.showAccounts = true }
                throw error
            }
        }
    }

    func cancelLaunch() { launchJob?.cancel() }

    // MARK: 自动更新

    var checkingForUpdates = false

    /// 检查新版本。自动检查时遵循设置，并且最多每 6 小时检查一次
    func checkForUpdates(userInitiated: Bool) async {
        let settings = LauncherSettings.shared
        if !userInitiated {
            guard settings.autoCheckUpdates else { return }
            if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        }
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        do {
            let release = try await Updater.check()
            settings.lastUpdateCheck = Date()
            guard let release else {
                if userInitiated { Hint.show(T("已是最新版本（\(AppInfo.version)）", "You're up to date (\(AppInfo.version))"), .green) }
                return
            }
            let notes = Self.plainNotes(release.notes)
            let r = await MsgBox.show(
                title: T("发现新版本 \(release.version)", "Kiln \(release.version) is available"),
                content: T("当前版本 \(AppInfo.version)。", "You have \(AppInfo.version).") + (notes.isEmpty ? "" : "\n\n" + notes),
                buttons: [T("立即更新", "Update now"), T("查看发布页", "View release"), T("稍后", "Later")])
            switch r {
            case 1: performUpdate(release)
            case 2: Links.open(release.pageURL)
            default: break
            }
        } catch {
            log("[Update] 检查更新失败：\(error.friendly)")
            if userInitiated { Hint.show(T("检查更新失败：\(error.friendly)", "Couldn't check for updates: \(error.friendly)"), .red) }
        }
    }

    /// 下载、校验并替换为新版本，然后重新打开
    func performUpdate(_ release: Updater.Release) {
        guard let app = Updater.currentApp else {
            Hint.show(Updater.UpdateError.notInstalledAsApp.localizedDescription, .red)
            Links.open(release.pageURL)
            return
        }
        do { try Updater.checkReplaceable(app) } catch {
            Hint.show(error.friendly, .red)
            return
        }
        if games.contains(where: { $0.state == .running || $0.state == .starting }) {
            Hint.show(T("请先退出正在运行的游戏，再更新启动器。", "Quit the running game before updating the launcher."), .red)
            return
        }
        JobCenter.shared.start(T("更新到 Kiln \(release.version)", "Update to Kiln \(release.version)")) { job in
            job.enter(T("下载新版本", "Downloading the update"), index: 0, of: 2)
            let staged = try await Updater.prepare(release, replacing: app, job: job)
            job.enter(T("安装并重新打开", "Installing and relaunching"), index: 1, of: 2)
            try Updater.launchReplacement(staged: staged, app: app)
            NSApp.terminate(nil)
        }
    }

    /// 发布说明转为纯文本：去掉 Markdown 标记，只取中文部分（分隔线之前），并限制长度
    static func plainNotes(_ md: String) -> String {
        var text = md.components(separatedBy: "\n---").first ?? md
        text = text.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 700 ? String(text.prefix(700)) + "…" : text
    }

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
