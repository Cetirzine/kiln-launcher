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
        /// 不能导入的原因（使用了 Kiln 不支持的加载器或组件）
        package var unsupported: String?
        /// 可以导入，但需要注意的地方
        package var warning: String?
        /// 从压缩包解压出的临时目录，导入结束后删除
        package var temporary: URL?

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

    // MARK: 导出的压缩包

    /// 压缩包是否是 Prism / MultiMC 导出的实例（含 instance.cfg）
    package static func isInstanceArchive(_ archive: URL) -> Bool { instanceEntry(archive) != nil }

    /// instance.cfg 在压缩包中的路径（取层级最浅的一个）
    static func instanceEntry(_ archive: URL) -> String? {
        Zip.list(archive).filter { ($0 == "instance.cfg" || $0.hasSuffix("/instance.cfg")) && !$0.hasPrefix("__MACOSX") }
            .min { $0.split(separator: "/").count < $1.split(separator: "/").count }
    }

    /// 解压 Prism / MultiMC 导出的实例压缩包并识别
    package static func inspect(archive: URL) throws -> Candidate {
        guard let entry = instanceEntry(archive) else {
            throw LauncherError(T("压缩包中没有 instance.cfg，不是 Prism 或 MultiMC 导出的实例", "There's no instance.cfg in the archive, so it isn't a Prism or MultiMC instance export"))
        }
        let tmp = Paths.cache.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Zip.extractAll(archive, to: tmp)
        let root = entry.split(separator: "/").dropLast().reduce(tmp) { $0.appendingPathComponent(String($1)) }
        guard var c = inspect(folder: root) else {
            try? FileManager.default.removeItem(at: tmp)
            throw LauncherError(T("无法识别压缩包中的实例（缺少 Minecraft 版本）", "Couldn't read the instance in the archive (no Minecraft version)"))
        }
        c.temporary = tmp
        return c
    }

    // MARK: Prism / MultiMC

    /// Kiln 能够还原的组件；unsup（整合包自动同步）不影响游戏本身，忽略
    static let knownComponents: Set<String> = ["net.minecraft", "org.lwjgl", "org.lwjgl3", "net.fabricmc.intermediary", "net.fabricmc.fabric-loader",
                                               "org.quiltmc.quilt-loader", "org.quiltmc.hashed", "net.minecraftforge", "net.neoforged",
                                               "com.unascribed.unsup"]

    static func mmcInstance(_ dir: URL, source: Source) -> Candidate? {
        let fm = FileManager.default
        guard let cfgText = try? String(contentsOf: dir.appendingPathComponent("instance.cfg"), encoding: .utf8) else { return nil }
        let cfg = ini(cfgText)
        var game = cfg["IntendedVersion"]
        var loader: Loader?
        var unknown: [String] = []
        if let data = try? Data(contentsOf: dir.appendingPathComponent("mmc-pack.json")), let pack = try? JSON(data: data) {
            for c in pack["components"].array {
                guard let uid = c["uid"].string else { continue }
                let display = c["cachedName"].string ?? uid
                let v = c["version"].string ?? c["cachedVersion"].string
                if uid == "net.minecraft", let v { game = v }
                // 不认识的组件（Babric、Cleanroom、jar mod 等）无法在 Kiln 中还原；被 patches/ 覆盖的组件同理
                if !knownComponents.contains(uid) || display == "Cleanroom"
                    || fm.fileExists(atPath: dir.appendingPathComponent("patches/\(uid).json").path) && uid != "org.lwjgl" && uid != "org.lwjgl3" {
                    unknown.append(uid == "net.minecraft" ? T("修改过的 Minecraft", "a modified Minecraft") : display)
                    continue
                }
                guard let v else { continue }
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
        let content = [".minecraft", "minecraft"].map { dir.appendingPathComponent($0) }.first { fm.fileExists(atPath: $0.path) }
            ?? dir.appendingPathComponent(".minecraft")
        var c = Candidate(source: source, name: cfg["name"] ?? dir.lastPathComponent, gameVersion: game, loader: loader, contentDir: content)
        if cfg["OverrideJavaArgs"] == "true", let args = cfg["JvmArgs"] { c.jvmArgs = cleanJvmArgs(args) }
        if cfg["OverrideMemory"] == "true", let mb = cfg["MaxMemAlloc"].flatMap(Double.init), mb > 0 { c.memoryGB = mb / 1024 }
        if let ms = cfg["lastLaunchTime"].flatMap(Double.init), ms > 0 { c.lastPlayed = Date(timeIntervalSince1970: ms / 1000) }
        // 启动前命令（packwiz 等）通常用来下载或更新 Mod，Kiln 不会运行
        if cfg["OverrideCommands"] == "true", let pre = cfg["PreLaunchCommand"], !pre.isEmpty {
            c.warning = T("这个实例在启动前运行命令（\(pre.prefix(60))）来下载或更新 Mod，Kiln 不会运行它，导入的 Mod 可能不全",
                          "This instance runs a pre-launch command (\(pre.prefix(60))) to download or update mods. Kiln won't run it, so some mods may be missing")
        }
        if !unknown.isEmpty { c.unsupported = T("使用了 Kiln 暂不支持的组件：", "Uses components Kiln doesn't support: ") + unknown.joined(separator: T("、", ", ")) }
        return c
    }

    // MARK: CurseForge

    static func curseForgeInstance(_ dir: URL) -> Candidate? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("minecraftinstance.json")), let j = try? JSON(data: data) else { return nil }
        // 旧版 Curse / Twitch 客户端的字段首字母大写（Name、MinecraftVersion）
        let base = j["baseModLoader"]
        func field(_ key: String) -> String? { base[key].string ?? base[key.prefix(1).uppercased() + key.dropFirst()].string }
        guard let game = j["gameVersion"].string ?? field("minecraftVersion"), !game.isEmpty else { return nil }
        var loader: Loader?
        // name：forge-47.2.0、neoforge-21.1.77、fabric-0.15.7-1.20.1、quilt-0.26.0-1.20.1
        let loaderName = field("name") ?? ""
        let parts = loaderName.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            switch parts[0].lowercased() {
            case "forge": loader = Loader(kind: "Forge", version: field("forgeVersion") ?? parts[1])
            case "neoforge": loader = Loader(kind: "NeoForge", version: parts[1])
            case "fabric": loader = Loader(kind: "Fabric", version: parts[1])
            case "quilt": loader = Loader(kind: "Quilt", version: parts[1])
            default: break
            }
        }
        var c = Candidate(source: .curseforge, name: j["name"].string ?? dir.lastPathComponent, gameVersion: game, loader: loader, contentDir: dir)
        // 只有单独设置过内存时才沿用，否则跟随 Kiln 的自动分配
        if j["isMemoryOverride"].bool ?? true, let mb = j["allocatedMemory"].double, mb > 0 { c.memoryGB = mb / 1024 }
        if let args = j["javaArgsOverride"].string { c.jvmArgs = cleanJvmArgs(args) }
        if let s = j["lastPlayed"].string { c.lastPlayed = parseDate(s) }
        if loader == nil && !loaderName.isEmpty { c.unsupported = T("使用了 Kiln 暂不支持的加载器：", "Uses a loader Kiln doesn't support: ") + loaderName }
        return c
    }

    // MARK: 官方启动器

    /// 只导入使用自己游戏目录的配置；使用默认目录的版本在 Kiln 中本来就能看到
    /// requireFiles 为 false 时不检查游戏目录与版本文件是否存在（用于检查解析）
    package static func officialProfiles(_ folder: URL, requireFiles: Bool = true) -> [Candidate] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("launcher_profiles.json")), let j = try? JSON(data: data) else { return [] }
        let defaultDir = folder.standardizedFileURL.path
        var result: [Candidate] = []
        for (_, p) in j["profiles"].object {
            guard let dirPath = p["gameDir"].string, !dirPath.isEmpty,
                  let versionId = p["lastVersionId"].string, !versionId.hasPrefix("latest-") else { continue }
            let dir = URL(fileURLWithPath: (dirPath as NSString).expandingTildeInPath)
            guard dir.standardizedFileURL.path != defaultDir, !requireFiles || FileManager.default.fileExists(atPath: dir.path) else { continue }
            let instance = McInstance(folder: folder, name: versionId)
            guard instance.raw.exists || !requireFiles else { continue }
            var loader: Loader?
            if let kind = instance.loaders.first(where: { ["Fabric", "Quilt", "Forge", "NeoForge"].contains($0) }),
               let v = instance.loaderVersion(kind) {
                loader = Loader(kind: kind, version: v)
            }
            let name = p["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? versionId
            let extra = instance.loaders.filter { !["Fabric", "Quilt", "Forge", "NeoForge"].contains($0) }
            var c = Candidate(source: .official, name: name, gameVersion: instance.raw.exists ? instance.vanillaVersion : versionId, loader: loader, contentDir: dir)
            if let args = p["javaArgs"].string, !args.isEmpty {
                if let xmx = Launcher.split(args).first(where: { $0.hasPrefix("-Xmx") }) { c.memoryGB = memoryGB(String(xmx.dropFirst(4))) }
                c.jvmArgs = cleanJvmArgs(args)
            }
            if let s = p["lastUsed"].string { c.lastPlayed = parseDate(s) }
            if !extra.isEmpty {
                c.unsupported = T("\(extra.joined(separator: "、")) 安装在版本里，导入后需要重新安装", "\(extra.joined(separator: ", ")) is installed into the version; reinstall it after importing")
            }
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
        defer { if let t = c.temporary { try? fm.removeItem(at: t) } }
        if fm.fileExists(atPath: dir.path) { throw LauncherError(T("已存在名为 \(name) 的版本", "An instance named \(name) already exists")) }
        if let reason = c.unsupported { throw LauncherError(reason) }
        try await checkAvailable(c)
        var finished = false
        defer { if !finished { try? fm.removeItem(at: dir) } }

        try await Modpack.installGame(c.gameVersion, loader: c.loader.map { ($0.kind, $0.version) }, name: name, folder: folder, job: job)
        let instance = McInstance(folder: folder, name: name)
        var setup = instance.setup
        setup.isolation = true
        setup.jvmArgs = c.jvmArgs
        setup.memoryGB = c.memoryGB
        setup.lastPlayed = c.lastPlayed
        setup.importedFrom = c.temporary == nil ? c.contentDir.path : nil
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)

        await job.enter(T("复制 Mod、存档与设置", "Copying mods, worlds and settings"), index: 0, of: 1)
        let content = c.contentDir
        try await Task.detached {
            try copyContent(from: content, to: dir)
        }.value
        finished = true
        return name
    }

    /// 安装前确认游戏与加载器版本存在，给出比 HTTP 404 更清楚的错误
    static func checkAvailable(_ c: Candidate) async throws {
        _ = try await VersionManifest.find(c.gameVersion)
        guard let l = c.loader, let kind = ModLoaderKind(rawValue: l.kind) else { return }
        let list: [ModLoaderKind.LoaderVersion]
        do { list = try await kind.versions(for: c.gameVersion) } catch {
            throw LauncherError(T("\(l.kind) 官方不支持 Minecraft \(c.gameVersion)（可能使用了 Babric 等第三方分支）", "\(l.kind) doesn't officially support Minecraft \(c.gameVersion) (it may use a fork such as Babric)"))
        }
        if list.isEmpty || !list.contains(where: { $0.version == l.version }) {
            throw LauncherError(T("找不到 \(l.kind) \(l.version)（Minecraft \(c.gameVersion)）", "\(l.kind) \(l.version) for Minecraft \(c.gameVersion) wasn't found"))
        }
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

    /// 去掉内存与 -XX: 调优参数：内存单独设置，JVM 由 Kiln 按 Java 版本调优。
    /// 其他启动器的 -XX: 参数常常只适用于特定的 Java 或 GC，混用会让 JVM 拒绝启动；保留 -D 等其他参数
    package static func cleanJvmArgs(_ args: String) -> String? {
        let rest = Launcher.split(args).filter { a in
            !a.hasPrefix("-XX:") && !a.hasPrefix("-Xmx") && !a.hasPrefix("-Xms") && !a.hasPrefix("-Xmn") && !a.hasPrefix("-Xincgc")
        }
        return rest.isEmpty ? nil : rest.joined(separator: " ")
    }

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
