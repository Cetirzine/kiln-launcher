import SwiftUI
import LauncherCore
import AppKit

struct SetupPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PageHeader(T("设置", "Settings"))
            HStack {
                SegmentBar(items: [
                    (AppState.SetupSection.game, T("游戏", "Game"), "play.circle.fill"),
                    (.performance, T("性能", "Performance"), "gauge.with.dots.needle.67percent"),
                    (.java, "Java", "cup.and.saucer.fill"),
                    (.download, T("下载", "Downloads"), "arrow.down.circle.fill"),
                    (.other, T("其他", "Other"), "ellipsis.circle.fill"),
                ], selection: $state.setupSection)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            PageScroll {
                VStack(spacing: 14) {
                    switch state.setupSection {
                    case .game: LaunchSettings()
                    case .performance: PerformanceSettings()
                    case .java: JavaSettings()
                    case .download: DownloadSettings()
                    case .other: LanguageSettings(); SystemSettings()
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}

struct LaunchSettings: View {
    @PState private var s = LauncherSettings.shared

    var body: some View {
        Card(T("游戏", "Game")) {
            SettingRow(title: T("新版本的游戏目录", "Game directory for new instances"), help: T("新安装的版本是否使用自己的游戏目录（存档、Mod、设置各自独立）", "Whether new instances get their own game directory (separate worlds, mods and options)")) {
                Picker("", selection: $s.isolation) {
                    Text(T("全部共用", "Shared by all")).tag(LauncherSettings.Isolation.none)
                    Text(T("Mod 版本与非正式版独立", "Separate for modded & previews")).tag(LauncherSettings.Isolation.moddedAndPreview)
                    Text(T("全部独立", "Separate for all")).tag(LauncherSettings.Isolation.all)
                }
                .labelsHidden().frame(maxWidth: 320)
            }
            SettingRow(title: T("游戏窗口", "Game window")) {
                Picker("", selection: $s.windowMode) {
                    Text(T("全屏", "Fullscreen")).tag(LauncherSettings.WindowMode.fullscreen)
                    Text(T("默认（854×480）", "Default (854×480)")).tag(LauncherSettings.WindowMode.defaultSize)
                    Text(T("自定义", "Custom")).tag(LauncherSettings.WindowMode.custom)
                }
                .labelsHidden().frame(maxWidth: 200)
                if s.windowMode == .custom {
                    TextField("", value: $s.windowWidth, format: .number).frame(width: 64)
                    Text("×").foregroundStyle(Theme.text3)
                    TextField("", value: $s.windowHeight, format: .number).frame(width: 64)
                }
            }
            SettingRow(title: T("游戏启动后", "After launching")) {
                Picker("", selection: $s.visibility) {
                    Text(T("启动后退出启动器", "Quit after launch")).tag(LauncherSettings.Visibility.closeOnStart)
                    Text(T("游戏运行时隐藏，退出后关闭启动器", "Hide while playing, quit after exit")).tag(LauncherSettings.Visibility.hideAndClose)
                    Text(T("游戏运行时隐藏，退出后恢复", "Hide while playing, show after exit")).tag(LauncherSettings.Visibility.hideAndReopen)
                    Text(T("启动后最小化", "Minimize after launch")).tag(LauncherSettings.Visibility.minimize)
                    Text(T("保持打开", "Keep open")).tag(LauncherSettings.Visibility.keep)
                }
                .labelsHidden().frame(maxWidth: 320)
            }
            SettingRow(title: T("版本类型文字", "Version type text"), help: T("显示在游戏主菜单左下角与 F3 调试界面", "Shown in the title screen corner and the F3 screen")) {
                TextField(AppInfo.shortName, text: $s.customInfo).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            }
        }
        Card(T("内存", "Memory")) {
            SettingRow(title: T("自动分配", "Automatic"), help: T("根据 Mod 数量与统一内存大小自动分配", "Allocates automatically based on mods and unified memory")) {
                Toggle("", isOn: $s.memoryAuto).toggleStyle(.switch).labelsHidden()
            }
            if !s.memoryAuto {
                SettingRow(title: T("手动", "Manual")) {
                    Slider(value: $s.memoryGB, in: 1...max(2, totalGB * 0.8), step: 0.5).frame(maxWidth: 300)
                    Text(String(format: "%.1f GB", s.memoryGB)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
                }
            }
            MemoryBar(allocated: s.memoryAuto ? nil : s.memoryGB, total: totalGB)
        }
        Card(T("高级", "Advanced")) {
            SettingRow(title: T("额外 JVM 参数", "Extra JVM arguments"), help: T("追加在 JVM 参数末尾；填写 -Xmx 或 GC 参数会覆盖自动设置", "Appended to the JVM arguments; -Xmx or GC flags override the automatic ones")) {
                TextField("-XX:+UseZGC", text: $s.jvmArgs).textFieldStyle(.roundedBorder)
            }
            SettingRow(title: T("额外游戏参数", "Extra game arguments"), help: T("追加在游戏参数末尾", "Appended to the game arguments")) {
                TextField("", text: $s.gameArgs).textFieldStyle(.roundedBorder)
            }
            SettingRow(title: T("跳过资源检查", "Skip asset check"),
                       help: T("跳过资源文件检查（仅在网络不佳时使用）", "Skip checking asset files (only for poor connections)")) {
                Toggle("", isOn: $s.skipAssetCheck).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private var totalGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024 }
}

/// 统一内存使用情况
struct MemoryBar: View {
    let allocated: Double?
    let total: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.panel2)
                    Rectangle().fill(Theme.text2)
                        .frame(width: g.size.width * min(1, (allocated ?? total * 0.25) / total))
                }
            }
            .frame(height: 8)
            Text(T("统一内存 \(String(format: "%.0f", total)) GB · 游戏分配：\(allocated.map { String(format: "%.1f GB", $0) } ?? T("自动", "Automatic"))", "Unified memory \(String(format: "%.0f", total)) GB · Game: \(allocated.map { String(format: "%.1f GB", $0) } ?? T("自动", "Automatic"))"))
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
    }
}

struct PerformanceSettings: View {
    @PState private var s = LauncherSettings.shared

    var body: some View {
        if Arch.isAppleSilicon {
            Card(T("Apple 芯片", "Apple Silicon")) {
                SettingRow(title: T("原生运行旧版本", "Run older versions natively"), help: T("1.13 ~ 1.18 替换为 arm64 版 LWJGL 3；1.12.2 及更早的版本替换为 arm64 版 LWJGL 2 并使用 arm64 Java 8。关闭后这些版本通过 Rosetta 2 运行。", "Swaps in arm64 LWJGL 3 for 1.13–1.18, and arm64 LWJGL 2 with arm64 Java 8 for 1.12.2 and older. When off, these run through Rosetta 2.")) {
                    Toggle("", isOn: $s.arm64Native).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(title: "Rosetta 2", help: T("仅在关闭“原生运行旧版本”或无法获取 arm64 Java 时使用", "Only used when \"Run older versions natively\" is off or no arm64 Java is available")) {
                    if Arch.rosettaInstalled {
                        Badge(text: T("已安装", "Installed"), color: Theme.green)
                    } else {
                        Badge(text: T("未安装", "Not installed"), color: Theme.yellow)
                        Button(T("复制安装命令", "Copy install command")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("softwareupdate --install-rosetta --agree-to-license", forType: .string)
                            Hint.show(T("已复制！", "Copied!"), .green)
                        }.buttonStyle(.kiln)
                    }
                }
            }
        }
        Card(T("Java 虚拟机", "Java virtual machine")) {
            SettingRow(title: T("垃圾回收器", "Garbage collector"),
                       help: T("G1 适合大多数情况；分代 ZGC 停顿更短，但占用更多内存（需要 Java 21+）。", "G1 suits most setups; generational ZGC has shorter pauses but uses more memory (Java 21+).")) {
                Picker("", selection: $s.gcMode) {
                    Text(T("G1（推荐）", "G1 (recommended)")).tag(LauncherSettings.GCMode.g1)
                    Text(T("分代 ZGC", "Generational ZGC")).tag(LauncherSettings.GCMode.zgc)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
            }
            SettingRow(title: T("类数据共享（CDS）", "Class data sharing (CDS)"),
                       help: T("Java 19+ 会为每个版本生成类缓存，之后启动更快。", "With Java 19+, a per-instance class archive is created so later launches start faster.")) {
                Toggle("", isOn: $s.classDataSharing).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: T("紧凑对象头", "Compact object headers"),
                       help: T("Java 24+ 可减少约 10%～20% 的堆内存占用。", "With Java 24+, reduces heap usage by roughly 10–20%.")) {
                Toggle("", isOn: $s.compactHeaders).toggleStyle(.switch).labelsHidden()
            }
        }
        Card(T("启动速度", "Launch speed")) {
            SettingRow(title: T("快速校验", "Fast verification"),
                       help: T("文件未被修改时跳过 SHA-1 校验。", "Skip SHA-1 checks for files that haven't changed.")) {
                Toggle("", isOn: $s.fastVerify).toggleStyle(.switch).labelsHidden()
            }
        }
        Text(T("游戏进程会以高优先级运行，在 Apple 芯片上优先调度到性能核心。",
               "The game process runs at high priority so Apple Silicon schedules it on performance cores."))
            .font(.system(size: 11.5)).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JavaSettings: View {
    @PState private var s = LauncherSettings.shared
    @PState private var javas: [JavaInfo] = []
    @PState private var searching = false

    var body: some View {
        Card(T("Java", "Java"),
             trailing: AnyView(HStack(spacing: 6) {
                 Button(T("添加…", "Add…")) { importJava() }.buttonStyle(.kiln)
                 Button(T("重新扫描", "Rescan")) { Task { await search() } }.buttonStyle(.kiln)
             })) {
            ListItem(systemIcon: "wand.and.stars", title: T("自动选择（推荐）", "Automatic (recommended)"),
                     info: T("优先使用 Apple 芯片原生的 Java；缺少时自动下载 Mojang 官方 Java。", "Prefers native Apple Silicon Java; downloads Mojang's official Java when needed."), selected: s.javaPath.isEmpty, action: { s.javaPath = "" })
            if searching { ProgressView().controlSize(.small) }
            ForEach(javas) { j in
                ListItem(systemIcon: j.arch == "arm64" ? "bolt.fill" : "cpu", title: j.displayName, info: j.home,
                         selected: s.javaPath == j.path, action: { s.javaPath = j.path }) {
                    if s.customJavas.contains(j.path) {
                        IconButton(systemImage: "minus.circle", help: T("移除", "Remove")) {
                            s.customJavas.removeAll { $0 == j.path }
                            if s.javaPath == j.path { s.javaPath = "" }
                            Task { await search() }
                        }
                    }
                }
            }
            if !searching && javas.isEmpty {
                Text(T("未找到 Java。启动游戏时会自动下载。", "No Java found. It will be downloaded automatically when launching.")).font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        }
        .task { await search() }
    }

    private func search() async {
        searching = true
        javas = await JavaManager.search()
        searching = false
    }

    private func importJava() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = T("选择 Java 可执行文件或 JDK 文件夹", "Choose a Java executable or JDK folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let candidates = [url.path, url.appendingPathComponent("bin/java").path, url.appendingPathComponent("Contents/Home/bin/java").path]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) && !$0.hasSuffix("/") }),
              JavaManager.inspect(path) != nil else {
            Hint.show(T("无法识别这个 Java", "This Java couldn't be recognized"), .red)
            return
        }
        if !s.customJavas.contains(path) { s.customJavas.append(path) }
        Hint.show(T("已添加 Java", "Java added"), .green)
        Task { await search() }
    }
}

struct DownloadSettings: View {
    @PState private var s = LauncherSettings.shared

    var body: some View {
        Card(T("下载", "Downloads")) {
            SettingRow(title: T("版本列表来源", "Version list source")) {
                sourcePicker($s.versionListSource)
            }
            SettingRow(title: T("文件下载来源", "File download source")) {
                sourcePicker($s.fileSource)
            }
            SettingRow(title: T("并发下载数", "Concurrent downloads"), help: T("同时进行的下载数量", "How many files to download at once")) {
                Slider(value: Binding(get: { Double(s.downloadThreads) }, set: { s.downloadThreads = Int($0) }), in: 1...128, step: 1)
                    .frame(maxWidth: 260)
                Text("\(s.downloadThreads)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
            }
            SettingRow(title: T("新版本使用与启动器相同的语言", "Use the launcher language for new instances")) {
                Toggle("", isOn: $s.gameLanguageAuto).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private func sourcePicker(_ b: Binding<LauncherSettings.DownloadSource>) -> some View {
        Picker("", selection: b) {
            Text(T("优先使用镜像（BMCLAPI）", "Prefer mirror (BMCLAPI)")).tag(LauncherSettings.DownloadSource.mirrorFirst)
            Text(T("官方源，较慢时改用镜像", "Official, mirror when slow")).tag(LauncherSettings.DownloadSource.officialSlowFallback)
            Text(T("优先使用官方源", "Prefer official")).tag(LauncherSettings.DownloadSource.officialFirst)
        }
        .labelsHidden().frame(maxWidth: 320)
    }

}

struct LanguageSettings: View {
    @PState private var s = LauncherSettings.shared
    var body: some View {
        Card(T("语言", "Language")) {
            Picker("", selection: $s.language) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            Text(T("繁体中文由简体中文自动转换生成。", "Traditional Chinese is converted automatically from Simplified Chinese."))
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
    }
}

struct SystemSettings: View {
    @PState private var s = LauncherSettings.shared
    var body: some View {
        Card(T("微软账号登录", "Microsoft sign-in")) {
            SettingRow(title: "Azure Client ID",
                       help: s.hasEmbeddedClientId
                        ? T("启动器已内置 Client ID。只有想换用自己的应用时才需要填写。", "A Client ID is built into the launcher. Fill this in only to use your own app instead.")
                        : T("微软登录需要一个在 Azure 注册、并获准使用 Minecraft API 的应用 ID。", "Microsoft sign-in needs an Azure app ID that has been approved for the Minecraft API.")) {
                TextField(s.hasEmbeddedClientId ? T("使用内置 ID", "Use the built-in ID") : "00000000-0000-0000-0000-000000000000",
                          text: $s.msClientId).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
            }
        }
        Card(T("更新", "Updates")) {
            SettingRow(title: T("自动检查更新", "Check for updates automatically"),
                       help: T("当前版本 \(AppInfo.version)。有新版本时会提示，确认后自动下载并替换。", "Current version \(AppInfo.version). When a new version is out you'll be asked, then it downloads and replaces itself.")) {
                Toggle("", isOn: $s.autoCheckUpdates).toggleStyle(.switch).labelsHidden()
                Button(T("立即检查", "Check now")) { Task { await AppState.shared.checkForUpdates(userInitiated: true) } }
                    .buttonStyle(.kiln)
                    .disabled(AppState.shared.checkingForUpdates)
            }
        }
        Card(T("数据与日志", "Data & logs")) {
            HStack(spacing: 8) {
                Button(T("打开日志文件夹", "Open log folder")) { NSWorkspace.shared.open(Paths.logs) }.buttonStyle(.kiln)
                Button(T("打开数据文件夹", "Open data folder")) { NSWorkspace.shared.open(Paths.support) }.buttonStyle(.kiln)
                Button(T("清理缓存", "Clear cache")) {
                    try? FileManager.default.removeItem(at: Paths.cache)
                    Hint.show(T("缓存已清理", "Cache cleared"), .green)
                }.buttonStyle(.kiln)
            }
        }
    }
}
