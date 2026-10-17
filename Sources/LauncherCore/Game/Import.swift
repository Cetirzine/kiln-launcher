import Foundation

/// 从其他启动器导入版本：Prism Launcher / MultiMC / PolyMC（instance.cfg + mmc-pack.json）、
/// CurseForge App（minecraftinstance.json）、官方启动器（launcher_profiles.json 中使用独立游戏目录的配置）。
/// 导入时在 Kiln 中重新安装同样的游戏与加载器，再把 Mod、存档、配置等复制到新版本的独立游戏目录。
package enum LauncherImport {
    package enum Source: String, Sendable, CaseIterable {
        case prism = "Prism Launcher", multimc = "MultiMC", polymc = "PolyMC", curseforge = "CurseForge", official = "Minecraft Launcher"
    }

    package struct Loader: Hashable, Sendable {
        package let kind: String
        package let version: String
        package init(kind: String, version: String) { self.kind = kind; self.version = version }
    }

    package struct Candidate: Identifiable, Hashable, Sendable {
        package var id: String { contentDir.path + "|" + name }
        package let source: Source
        package let name: String
        package let gameVersion: String
        package let loader: Loader?
        /// 游戏目录（mods、saves、config 等所在的位置）
        package let contentDir: URL
        package var jvmArgs: String?
        package var memoryGB: Double?
        package var lastPlayed: Date?

        package init(source: Source, name: String, gameVersion: String, loader: Loader?, contentDir: URL) {
            self.source = source; self.name = name; self.gameVersion = gameVersion; self.loader = loader; self.contentDir = contentDir
        }

        package var modCount: Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: contentDir.appendingPathComponent("mods").path)) ?? [])
                .filter { $0.hasSuffix(".jar") || $0.hasSuffix(".jar.disabled") }.count
        }
        package var worldCount: Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: contentDir.appendingPathComponent("saves").path)) ?? [])
                .filter { !$0.hasPrefix(".") }.count
        }
        package var summary: String {
            ([gameVersion] + (loader.map { ["\($0.kind) \($0.version)"] } ?? [])).joined(separator: " · ")
        }
    }

    /// 复制时跳过的内容：游戏文件由 Kiln 重新安装，日志与缓存没有意义
    static let skipped: Set<String> = ["versions", "libraries", "assets", "runtime", "natives", "logs", ".fabric", ".quilt", ".mixin.out",
                                       "instance.cfg", "mmc-pack.json", "minecraftinstance.json", ".curseclient", "profileImage",
                                       "launcher_profiles.json", "launcher_accounts.json", "launcher_settings.json", "usercache.json",
                                       "crash-reports", ".DS_Store", "patches"]

    // MARK: 查找

    package static func discover() -> [Candidate] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        var result: [Candidate] = []
        // Prism / PolyMC / MultiMC：实例目录可以在配置中修改
        let mmcLike: [(Source, URL, String)] = [
            (.prism, support.appendingPathComponent("PrismLauncher"), "prismlauncher.cfg"),
            (.polymc, support.appendingPathComponent("PolyMC"), "polymc.cfg"),
            (.multimc, support.appendingPathComponent("MultiMC"), "multimc.cfg"),
            (.multimc, URL(fileURLWithPath: "/Applications/MultiMC.app/Data"), "multimc.cfg"),
        ]
        for (source, dataDir, cfgName) in mmcLike {
            var instances = dataDir.appendingPathComponent("instances")
            if let cfg = try? String(contentsOf: dataDir.appendingPathComponent(cfgName), encoding: .utf8),
               let custom = ini(cfg)["InstanceDir"], !custom.isEmpty {
                instances = custom.hasPrefix("/") ? URL(fileURLWithPath: custom) : dataDir.appendingPathComponent(custom)
            }
            for dir in subdirectories(instances) {
                if let c = mmcInstance(dir, source: source) { result.append(c) }
            }
        }
        // CurseForge App
        for dir in subdirectories(home.appendingPathComponent("Documents/curseforge/minecraft/Instances")) {
            if let c = curseForgeInstance(dir) { result.append(c) }
        }
        // 官方启动器
        result += officialProfiles(Paths.defaultMinecraft)
        return result.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    /// 识别用户选择的文件夹（某个启动器的实例文件夹）
    package static func inspect(folder: URL) -> Candidate? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("minecraftinstance.json").path) { return curseForgeInstance(folder) }
        if fm.fileExists(atPath: folder.appendingPathComponent("instance.cfg").path) {
            // Prism 的 instance.cfg 带有 [General] 分节，MultiMC 没有
            let cfg = (try? String(contentsOf: folder.appendingPathComponent("instance.cfg"), encoding: .utf8)) ?? ""
            let source: Source = folder.path.contains("PolyMC") ? .polymc
                : (folder.path.contains("PrismLauncher") || cfg.contains("[General]") ? .prism : .multimc)
            return mmcInstance(folder, source: source)
        }
        return nil
    }

    // MARK: Prism / MultiMC

    static func mmcInstance(_ dir: URL, source: Source) -> Candidate? {
        guard let cfgText = try? String(contentsOf: dir.appendingPathComponent("instance.cfg"), encoding: .utf8) else { return nil }
        let cfg = ini(cfgText)
        var game = cfg["IntendedVersion"]
        var loader: Loader?
        if let data = try? Data(contentsOf: dir.appendingPathComponent("mmc-pack.json")), let pack = try? JSON(data: data) {
            for c in pack["components"].array {
                guard let uid = c["uid"].string, let v = c["version"].string ?? c["cachedVersion"].string else { continue }
                switch uid {
                case "net.minecraft": game = v
                case "net.fabricmc.fabric-loader": loader = Loader(kind: "Fabric", version: v)
                case "org.quiltmc.quilt-loader": loader = Loader(kind: "Quilt", version: v)
                case "net.minecraftforge": loader = Loader(kind: "Forge", version: v)
                case "net.neoforged": loader = Loader(kind: "NeoForge", version: v)
                default: break
                }
            }
        } else if let forge = cfg["ForgeVersion"], !forge.isEmpty {
            loader = Loader(kind: "Forge", version: forge)
        }
        guard let game, !game.isEmpty else { return nil }
        let fm = FileManager.default
        let content = [".minecraft", "minecraft"].map { dir.appendingPathComponent($0) }.first { fm.fileExists(atPath: $0.path) }
            ?? dir.appendingPathComponent(".minecraft")
        var c = Candidate(source: source, name: cfg["name"] ?? dir.lastPathComponent, gameVersion: game, loader: loader, contentDir: content)
        if cfg["OverrideJavaArgs"] == "true", let args = cfg["JvmArgs"], !args.isEmpty { c.jvmArgs = args }
        if cfg["OverrideMemory"] == "true", let mb = cfg["MaxMemAlloc"].flatMap(Double.init), mb > 0 { c.memoryGB = mb / 1024 }
        if let ms = cfg["lastLaunchTime"].flatMap(Double.init), ms > 0 { c.lastPlayed = Date(timeIntervalSince1970: ms / 1000) }
        return c
    }

    // MARK: CurseForge

    static func curseForgeInstance(_ dir: URL) -> Candidate? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("minecraftinstance.json")), let j = try? JSON(data: data),
              let game = j["gameVersion"].string ?? j["baseModLoader"]["minecraftVersion"].string, !game.isEmpty else { return nil }
        var loader: Loader?
        // baseModLoader.name：forge-47.2.0、neoforge-21.1.77、fabric-0.15.7-1.20.1、quilt-0.26.0-1.20.1
        if let name = j["baseModLoader"]["name"].string {
            let parts = name.split(separator: "-").map(String.init)
            if parts.count >= 2 {
                switch parts[0].lowercased() {
                case "forge": loader = Loader(kind: "Forge", version: j["baseModLoader"]["forgeVersion"].string ?? parts[1])
                case "neoforge": loader = Loader(kind: "NeoForge", version: parts[1])
                case "fabric": loader = Loader(kind: "Fabric", version: parts[1])
                case "quilt": loader = Loader(kind: "Quilt", version: parts[1])
                default: break
                }
            }
        }
        var c = Candidate(source: .curseforge, name: j["name"].string ?? dir.lastPathComponent, gameVersion: game, loader: loader, contentDir: dir)
        if let mb = j["allocatedMemory"].double, mb > 0 { c.memoryGB = mb / 1024 }
        if let s = j["lastPlayed"].string { c.lastPlayed = parseDate(s) }
        return c
    }

    // MARK: 官方启动器

    /// 只导入使用自己游戏目录的配置；使用默认目录的版本在 Kiln 中本来就能看到
    package static func officialProfiles(_ folder: URL) -> [Candidate] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("launcher_profiles.json")), let j = try? JSON(data: data) else { return [] }
        let defaultDir = folder.standardizedFileURL.path
        var result: [Candidate] = []
        for (_, p) in j["profiles"].object {
            guard let dirPath = p["gameDir"].string, !dirPath.isEmpty,
                  let versionId = p["lastVersionId"].string, !versionId.hasPrefix("latest-") else { continue }
            let dir = URL(fileURLWithPath: (dirPath as NSString).expandingTildeInPath)
            guard dir.standardizedFileURL.path != defaultDir, FileManager.default.fileExists(atPath: dir.path) else { continue }
            let instance = McInstance(folder: folder, name: versionId)
            guard instance.raw.exists else { continue }
            var loader: Loader?
            if let kind = instance.loaders.first(where: { ["Fabric", "Quilt", "Forge", "NeoForge"].contains($0) }),
               let v = instance.loaderVersion(kind) {
                loader = Loader(kind: kind, version: v)
            }
            let name = p["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? versionId
            var c = Candidate(source: .official, name: name, gameVersion: instance.vanillaVersion, loader: loader, contentDir: dir)
            if let args = p["javaArgs"].string, !args.isEmpty {
                let parts = Launcher.split(args)
                if let xmx = parts.first(where: { $0.hasPrefix("-Xmx") }) { c.memoryGB = memoryGB(String(xmx.dropFirst(4))) }
                let rest = parts.filter { !$0.hasPrefix("-Xmx") && !$0.hasPrefix("-Xms") && !$0.hasPrefix("-XX:+Use") && !$0.hasPrefix("-XX:G1")
                    && !$0.hasPrefix("-XX:MaxGCPauseMillis") && !$0.hasPrefix("-XX:+UnlockExperimentalVMOptions") }
                if !rest.isEmpty { c.jvmArgs = rest.joined(separator: " ") }
            }
            if let s = p["lastUsed"].string { c.lastPlayed = parseDate(s) }
            result.append(c)
        }
        return result
    }

    // MARK: 导入

    /// 安装游戏与加载器，并复制游戏目录内容；返回新版本的名称
    @discardableResult
    package static func run(_ c: Candidate, name: String, folder: URL, job: Job) async throws -> String {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent("versions/\(name)", isDirectory: true)
        if fm.fileExists(atPath: dir.path) { throw LauncherError(T("已存在名为 \(name) 的版本", "An instance named \(name) already exists")) }
        var finished = false
        defer { if !finished { try? fm.removeItem(at: dir) } }

        try await Modpack.installGame(c.gameVersion, loader: c.loader.map { ($0.kind, $0.version) }, name: name, folder: folder, job: job)
        let instance = McInstance(folder: folder, name: name)
        var setup = instance.setup
        setup.isolation = true
        setup.jvmArgs = c.jvmArgs
        setup.memoryGB = c.memoryGB
        setup.lastPlayed = c.lastPlayed
        setup.importedFrom = c.contentDir.path
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)

        await job.enter(T("复制 Mod、存档与设置", "Copying mods, worlds and settings"), index: 0, of: 1)
        let content = c.contentDir
        try await Task.detached {
            try copyContent(from: content, to: dir)
        }.value
        finished = true
        return name
    }

    /// 逐项复制（APFS 上为写时克隆，几乎不占用额外空间）；跳过符号链接
    package static func copyContent(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] {
            let name = item.lastPathComponent
            guard !skipped.contains(name), name != ".kiln", !name.hasPrefix("hs_err_pid"),
                  name != dst.lastPathComponent + ".json", name != dst.lastPathComponent + ".jar",
                  (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            let target = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) {
                // 新安装的版本里可能已经有 options.txt 等文件
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: item, to: target)
        }
    }

    /// 不与已有版本重名的名称
    package static func availableName(_ name: String, folder: URL) -> String {
        var base = name.trimmingCharacters(in: .whitespaces)
        base = String(base.map { "/\\:!*?\"<>|".contains($0) ? "-" : $0 })
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Imported" }
        var n = base, i = 2
        while InstanceManager.validateName(n, folder: folder) != nil { n = "\(base) (\(i))"; i += 1 }
        return n
    }

    // MARK: 工具

    /// 解析 key=value 格式的配置（忽略 [General] 等分节）
    static func ini(_ text: String) -> [String: String] {
        var r: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            // Qt 的 INI 会给含特殊字符的值加引号
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            r[line[..<eq].trimmingCharacters(in: .whitespaces)] = value
        }
        return r
    }

    static func subdirectories(_ dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "4G" / "4096M" → GB
    static func memoryGB(_ s: String) -> Double? {
        let unit = s.last?.lowercased() ?? ""
        guard let v = Double(s.dropLast()) ?? Double(s) else { return nil }
        switch unit {
        case "g": return v
        case "m": return v / 1024
        case "k": return v / 1024 / 1024
        default: return v / 1024 / 1024 / 1024
        }
    }
}
