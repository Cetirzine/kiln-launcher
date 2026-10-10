import Foundation
import Observation

/// 全局设置，存储在 UserDefaults 中
@Observable
package final class LauncherSettings {
    package static let shared = LauncherSettings()
    @ObservationIgnored private let d = UserDefaults.standard

    package enum DownloadSource: Int, CaseIterable { case mirrorFirst = 0, officialSlowFallback = 1, officialFirst = 2 }
    /// 新版本是否使用独立的游戏目录
    package enum Isolation: Int, CaseIterable { case none = 0, moddedAndPreview = 1, all = 2 }
    package enum WindowMode: Int, CaseIterable { case fullscreen = 0, defaultSize = 1, custom = 2 }
    package enum Visibility: Int, CaseIterable { case closeOnStart = 0, hideAndClose = 1, hideAndReopen = 2, minimize = 3, keep = 4 }
    package enum GCMode: Int, CaseIterable { case g1 = 0, zgc = 1 }

    package var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language"); Localizer.shared.language = language } }
    package var minecraftFolder: String { didSet { d.set(minecraftFolder, forKey: "minecraftFolder") } }
    package var extraFolders: [String] { didSet { d.set(extraFolders, forKey: "extraFolders") } }
    package var selectedInstance: String { didSet { d.set(selectedInstance, forKey: "selectedInstance") } }

    /// 空字符串表示自动选择
    package var javaPath: String { didSet { d.set(javaPath, forKey: "javaPath") } }
    package var customJavas: [String] { didSet { d.set(customJavas, forKey: "customJavas") } }
    package var memoryAuto: Bool { didSet { d.set(memoryAuto, forKey: "memoryAuto") } }
    package var memoryGB: Double { didSet { d.set(memoryGB, forKey: "memoryGB") } }
    package var windowMode: WindowMode { didSet { d.set(windowMode.rawValue, forKey: "windowMode") } }
    package var windowWidth: Int { didSet { d.set(windowWidth, forKey: "windowWidth") } }
    package var windowHeight: Int { didSet { d.set(windowHeight, forKey: "windowHeight") } }
    package var visibility: Visibility { didSet { d.set(visibility.rawValue, forKey: "visibility") } }
    package var isolation: Isolation { didSet { d.set(isolation.rawValue, forKey: "isolation") } }
    package var customInfo: String { didSet { d.set(customInfo, forKey: "customInfo") } }
    package var jvmArgs: String { didSet { d.set(jvmArgs, forKey: "jvmArgs") } }
    package var gameArgs: String { didSet { d.set(gameArgs, forKey: "gameArgs") } }
    package var skipAssetCheck: Bool { didSet { d.set(skipAssetCheck, forKey: "skipAssetCheck") } }

    // 性能
    package var gcMode: GCMode { didSet { d.set(gcMode.rawValue, forKey: "gcMode") } }
    package var classDataSharing: Bool { didSet { d.set(classDataSharing, forKey: "classDataSharing") } }
    package var compactHeaders: Bool { didSet { d.set(compactHeaders, forKey: "compactHeaders") } }
    /// 启动时只校验大小与修改时间已变化的文件
    package var fastVerify: Bool { didSet { d.set(fastVerify, forKey: "fastVerify") } }
    /// Apple 芯片原生模式：为 1.13 ~ 1.18 替换 arm64 版 LWJGL
    package var arm64Native: Bool { didSet { d.set(arm64Native, forKey: "arm64Native") } }

    package var versionListSource: DownloadSource { didSet { d.set(versionListSource.rawValue, forKey: "versionListSource") } }
    package var fileSource: DownloadSource { didSet { d.set(fileSource.rawValue, forKey: "fileSource") } }
    package var downloadThreads: Int { didSet { d.set(downloadThreads, forKey: "downloadThreads") } }
    package var gameLanguageAuto: Bool { didSet { d.set(gameLanguageAuto, forKey: "gameLanguageAuto") } }

    package var msClientId: String { didSet { d.set(msClientId, forKey: "msClientId") } }
    package var debugLog: Bool { didSet { d.set(debugLog, forKey: "debugLog") } }

    private init() {
        d.register(defaults: [
            "memoryAuto": true, "memoryGB": 4.0, "windowMode": 1, "windowWidth": 854, "windowHeight": 480,
            "visibility": 4, "isolation": 1, "customInfo": AppInfo.shortName,
            "versionListSource": 1, "fileSource": 1, "downloadThreads": 32, "gameLanguageAuto": true,
            "gcMode": 0, "classDataSharing": true, "compactHeaders": true, "fastVerify": true, "arm64Native": true,
        ])
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        minecraftFolder = d.string(forKey: "minecraftFolder") ?? Paths.defaultMinecraft.path
        extraFolders = d.stringArray(forKey: "extraFolders") ?? []
        selectedInstance = d.string(forKey: "selectedInstance") ?? ""
        javaPath = d.string(forKey: "javaPath") ?? ""
        customJavas = d.stringArray(forKey: "customJavas") ?? []
        memoryAuto = d.bool(forKey: "memoryAuto")
        memoryGB = d.double(forKey: "memoryGB")
        windowMode = WindowMode(rawValue: d.integer(forKey: "windowMode")) ?? .defaultSize
        windowWidth = d.integer(forKey: "windowWidth")
        windowHeight = d.integer(forKey: "windowHeight")
        visibility = Visibility(rawValue: d.integer(forKey: "visibility")) ?? .keep
        isolation = Isolation(rawValue: d.integer(forKey: "isolation")) ?? .moddedAndPreview
        customInfo = d.string(forKey: "customInfo") ?? AppInfo.shortName
        jvmArgs = d.string(forKey: "jvmArgs") ?? ""
        gameArgs = d.string(forKey: "gameArgs") ?? ""
        skipAssetCheck = d.bool(forKey: "skipAssetCheck")
        gcMode = GCMode(rawValue: d.integer(forKey: "gcMode")) ?? .g1
        classDataSharing = d.bool(forKey: "classDataSharing")
        compactHeaders = d.bool(forKey: "compactHeaders")
        fastVerify = d.bool(forKey: "fastVerify")
        arm64Native = d.bool(forKey: "arm64Native")
        versionListSource = DownloadSource(rawValue: d.integer(forKey: "versionListSource")) ?? .officialSlowFallback
        fileSource = DownloadSource(rawValue: d.integer(forKey: "fileSource")) ?? .officialSlowFallback
        downloadThreads = max(1, min(256, d.integer(forKey: "downloadThreads")))
        gameLanguageAuto = d.bool(forKey: "gameLanguageAuto")
        msClientId = d.string(forKey: "msClientId") ?? ""
        debugLog = d.bool(forKey: "debugLog") || ProcessInfo.processInfo.environment["KILN_DEBUG"] != nil
        Localizer.shared.language = language
    }

    /// 微软登录的 Client ID：设置中手动填写 → 环境变量 → 启动器内置
    package var effectiveClientId: String {
        let s = msClientId.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        if let env = ProcessInfo.processInfo.environment["KILN_MS_CLIENT_ID"], !env.isEmpty { return env }
        return EmbeddedClientID.value
    }

    /// 启动器是否内置了 Client ID
    package var hasEmbeddedClientId: Bool { !EmbeddedClientID.value.isEmpty }

    package var minecraftURL: URL { URL(fileURLWithPath: minecraftFolder, isDirectory: true) }

    // MARK: 版本独立设置（versions/<name>/.kiln/setup.json）

    package struct InstanceSetup: Codable, Equatable {
        package var isolation: Bool?
        package var javaPath: String?
        package var memoryGB: Double?
        package var jvmArgs: String?
        package var gameArgs: String?
        package var serverEnter: String?
        package var customInfo: String?
        package var lastPlayed: Date?
        /// 自定义图标（方块），为空时按版本类型自动选择
        package var icon: String?
        package init() {}
    }

    package func instanceSetup(_ versionDir: URL) -> InstanceSetup {
        let url = versionDir.appendingPathComponent(".kiln/setup.json")
        guard let data = try? Data(contentsOf: url) else { return InstanceSetup() }
        return (try? JSONDecoder().decode(InstanceSetup.self, from: data)) ?? InstanceSetup()
    }

    package func saveInstanceSetup(_ setup: InstanceSetup, _ versionDir: URL) {
        let dir = versionDir.appendingPathComponent(".kiln")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(setup).write(to: dir.appendingPathComponent("setup.json"))
    }
}

package enum Paths {
    /// macOS 上官方启动器的默认游戏目录
    package static let defaultMinecraft = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/minecraft", isDirectory: true)

    /// 启动器自身的数据目录（Java 运行时、日志、账号等）
    package static let support: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(AppInfo.shortName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    package static var runtime: URL { support.appendingPathComponent("runtime", isDirectory: true) }
    package static var logs: URL {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(AppInfo.shortName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    package static var cache: URL {
        let u = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(AppInfo.shortName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
