import AppIntents
import LauncherCore

/// “快捷指令”与聚焦搜索：启动某个版本、继续上次的游戏。
/// 构建脚本会用 appintentsmetadataprocessor 生成 Metadata.appintents，系统据此发现这些操作。

struct InstanceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Minecraft 版本"
    static let defaultQuery = InstanceQuery()

    let id: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)", subtitle: "\(detail)")
    }

    init(_ instance: McInstance) {
        id = instance.name
        detail = instance.description
    }
}

struct InstanceQuery: EntityStringQuery {
    private func all() -> [InstanceEntity] {
        InstanceScanner.scan(LauncherSettings.shared.minecraftURL)
            .filter { $0.category != .error }
            .sorted { ($0.setup.lastPlayed ?? .distantPast) > ($1.setup.lastPlayed ?? .distantPast) }
            .map(InstanceEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [InstanceEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [InstanceEntity] {
        all().filter { $0.id.localizedCaseInsensitiveContains(string) || $0.detail.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [InstanceEntity] { all() }
}

struct LaunchInstanceIntent: AppIntent {
    static let title: LocalizedStringResource = "启动 Minecraft 版本"
    static let description = IntentDescription("用 Kiln 启动指定的 Minecraft 版本。")
    static let openAppWhenRun = true

    @Parameter(title: "版本") var instance: InstanceEntity

    static var parameterSummary: some ParameterSummary { Summary("启动 \(\.$instance)") }

    init() {}
    init(instance: InstanceEntity) { self.instance = instance }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.launch(named: instance.id)
        return .result()
    }
}

struct ContinueGameIntent: AppIntent {
    static let title: LocalizedStringResource = "继续游戏"
    static let description = IntentDescription("用 Kiln 启动上次玩过的版本。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.launch(named: AppState.shared.recentInstances.first?.name)
        return .result()
    }
}

struct KilnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LaunchInstanceIntent(),
                    phrases: ["用 \(.applicationName) 启动 \(\.$instance)", "\(.applicationName) 启动 \(\.$instance)",
                              "Play \(\.$instance) in \(.applicationName)", "Launch \(\.$instance) with \(.applicationName)"],
                    shortTitle: "启动版本", systemImageName: "play.fill")
        AppShortcut(intent: ContinueGameIntent(),
                    phrases: ["用 \(.applicationName) 继续游戏", "\(.applicationName) 继续游戏",
                              "Continue playing in \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "继续游戏", systemImageName: "gamecontroller.fill")
    }
}
