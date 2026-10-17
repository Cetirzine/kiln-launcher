import Foundation

/// 版本 JSON 中 rules 的判定环境
package struct RuleContext {
    /// "arm64" 或 "x86_64"，取决于将要使用的 Java 架构
    package var arch: String = Arch.native
    package var demo = false
    package var customResolution = true

    package init(arch: String = Arch.native, demo: Bool = false, customResolution: Bool = true) {
        self.arch = arch; self.demo = demo; self.customResolution = customResolution
    }

    package static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 对应原版 McJsonRuleCheck，但以 macOS 为目标系统
    package func check(_ rules: JSON) -> Bool {
        let list = rules.array
        if list.isEmpty { return true }
        var allowed = false
        for rule in list {
            var match = true
            let os = rule["os"]
            if let name = os["name"].string {
                if name == "osx" || name == "macos" {
                    if let v = os["version"].string, (try? NSRegularExpression(pattern: v))?
                        .firstMatch(in: RuleContext.osVersion, range: NSRange(location: 0, length: RuleContext.osVersion.utf16.count)) == nil {
                        match = false
                    }
                } else if name != "unknown" {
                    match = false
                }
            }
            if let a = os["arch"].string {
                switch a {
                case "x86": match = false
                case "arm64", "aarch64": match = match && arch == "arm64"
                case "x86_64", "x64", "amd64": match = match && arch == "x86_64"
                default: break
                }
            }
            let features = rule["features"].object
            if !features.isEmpty {
                for (k, v) in features {
                    let want = v.bool ?? true
                    let have: Bool
                    switch k {
                    case "is_demo_user": have = demo
                    case "has_custom_resolution": have = customResolution
                    default: have = false // quick play 等由启动器另行处理
                    }
                    if want != have { match = false }
                }
            }
            if rule["action"].string == "allow" {
                if match { allowed = true }
            } else if match {
                allowed = false
            }
        }
        return allowed
    }
}

package enum Arch {
    package static var native: String {
        #if arch(arm64)
        return "arm64"
        #else
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // Rosetta 下运行时依然认为是 Apple 芯片
        if sysctlbyname("sysctl.proc_translated", &ret, &size, nil, 0) == 0, ret == 1 { return "arm64" }
        return "x86_64"
        #endif
    }
    package static var isAppleSilicon: Bool { native == "arm64" }

    package static var rosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
            || FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }
}

/// 支持库
package struct McLibrary: Hashable {
    package var name: String
    package var path: URL
    package var url: String?
    package var sha1: String?
    package var size: Int64?
    /// 旧式 natives（需要解压到 natives 文件夹）
    package var isNatives: Bool
    /// 新式 natives（natives-macos / natives-macos-arm64），既在 classpath 中，也需要按架构解压
    package var nativeArch: String?
    package var exclude: [String] = []

    package var download: DownloadItem? {
        guard let url, !url.isEmpty else { return nil }
        return DownloadItem(url: url, destination: path, sha1: sha1, size: size)
    }
}

package enum Maven {
    /// group:artifact:version[:classifier][@ext] → group/artifact/version/artifact-version[-classifier].ext
    package static func path(_ name: String, classifier: String? = nil) -> String? {
        var main = name
        var ext = "jar"
        if let at = name.lastIndex(of: "@") {
            ext = String(name[name.index(after: at)...])
            main = String(name[..<at])
        }
        let parts = main.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return nil }
        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1], version = parts[2]
        var cls = parts.count >= 4 ? parts[3] : nil
        if let classifier { cls = classifier }
        let file = "\(artifact)-\(version)" + (cls.map { "-\($0)" } ?? "") + ".\(ext)"
        return "\(group)/\(artifact)/\(version)/\(file)"
    }

    /// 用于去重的键（group:artifact[:classifier]）
    package static func key(_ name: String) -> String {
        let parts = name.split(separator: "@")[0].split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return name }
        return ([parts[0], parts[1]] + parts.dropFirst(3)).joined(separator: ":")
    }
}

/// 本地的一个 Minecraft 版本（实例）
package final class McInstance: Identifiable, Hashable {
    package enum Category: Int, Comparable {
        case modded = 0, release, snapshot, old, aprilFool, error
        package static func < (a: Category, b: Category) -> Bool { a.rawValue < b.rawValue }
    }

    package let name: String
    package let folder: URL
    package let dir: URL
    package var id: String { dir.path }
    /// 自身的 JSON
    package let raw: JSON
    /// 与 inheritsFrom 合并后的 JSON
    private(set) var json: JSON = .null
    package private(set) var error: String?
    package private(set) var parents: [String] = []

    package static func == (a: McInstance, b: McInstance) -> Bool { a.dir == b.dir }
    package func hash(into hasher: inout Hasher) { hasher.combine(dir) }

    package init(folder: URL, name: String) {
        self.folder = folder
        self.name = name
        self.dir = folder.appendingPathComponent("versions/\(name)", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("\(name).json")
        if let data = try? Data(contentsOf: jsonURL), let j = try? JSON(data: data) {
            raw = j
        } else {
            raw = .null
            error = T("缺少版本 JSON 文件", "Missing version JSON")
        }
        reload()
    }

    package func reload() {
        guard raw.exists else { return }
        error = nil
        parents = []
        var merged = raw
        var current = raw
        var depth = 0
        while let parent = current["inheritsFrom"].string, !parent.isEmpty, depth < 8 {
            depth += 1
            parents.append(parent)
            let url = folder.appendingPathComponent("versions/\(parent)/\(parent).json")
            guard let data = try? Data(contentsOf: url), let pj = try? JSON(data: data) else {
                // 依赖的原版尚未下载，启动/补全文件时会自动下载
                json = merged
                return
            }
            merged = McInstance.merge(child: merged, parent: pj)
            current = pj
        }
        json = merged
    }

    package var missingParent: String? {
        guard let p = parents.last else { return nil }
        let url = folder.appendingPathComponent("versions/\(p)/\(p).json")
        return FileManager.default.fileExists(atPath: url.path) ? nil : p
    }

    package static func merge(child: JSON, parent: JSON) -> JSON {
        var result = parent.object
        for (k, v) in child.object {
            switch k {
            case "libraries":
                result[k] = .array(v.array + parent["libraries"].array)
            case "arguments":
                var args = parent["arguments"].object
                for (ak, av) in v.object { args[ak] = .array(args[ak, default: .array([])].array + av.array) }
                result[k] = .object(args)
            case "inheritsFrom":
                continue
            default:
                result[k] = v
            }
        }
        result["inheritsFrom"] = parent["inheritsFrom"].exists ? parent["inheritsFrom"] : nil
        result["id"] = child["id"]
        return .object(result)
    }

    // MARK: 版本信息

    package var releaseTime: Date {
        let s = json["releaseTime"].string ?? json["time"].string ?? ""
        return ISO8601DateFormatter().date(from: s) ?? Date(timeIntervalSince1970: 0)
    }

    package var type: String { json["type"].string ?? "release" }

    /// 支持 Quick Play（--quickPlaySingleplayer / --quickPlayMultiplayer）：23w14a（1.20 快照）及以后
    package var supportsQuickPlay: Bool { releaseTime > ISO8601DateFormatter().date(from: "2023-04-04T00:00:00Z")! }

    /// 原版版本号
    package var vanillaVersion: String {
        if let c = raw["clientVersion"].string { return c }
        if let p = parents.last { return p }
        if let j = raw["jar"].string, !j.isEmpty { return j }
        // 某些整合包的 patches 字段（HMCL 格式）
        for p in raw["patches"].array where p["id"].string == "game" {
            if let v = p["version"].string { return v }
        }
        return raw["id"].string ?? name
    }

    private var libraryNames: [String] { json["libraries"].array.compactMap { $0["name"].string } }

    package var loaders: [String] {
        var r: [String] = []
        let names = libraryNames
        if names.contains(where: { $0.hasPrefix("net.fabricmc:fabric-loader:") }) { r.append("Fabric") }
        if names.contains(where: { $0.hasPrefix("org.quiltmc:quilt-loader:") }) { r.append("Quilt") }
        if names.contains(where: { $0.hasPrefix("net.neoforged") }) { r.append("NeoForge") }
        else if names.contains(where: { $0.hasPrefix("net.minecraftforge:forge:") || $0.hasPrefix("net.minecraftforge:fmlloader:") || $0.hasPrefix("net.minecraftforge:minecraftforge:") }) { r.append("Forge") }
        if names.contains(where: { $0.lowercased().hasPrefix("optifine:optifine") }) { r.append("OptiFine") }
        if names.contains(where: { $0.hasPrefix("com.mumfrey:liteloader:") }) { r.append("LiteLoader") }
        return r
    }

    package func loaderVersion(_ loader: String) -> String? {
        let prefix: String
        switch loader {
        case "Fabric": prefix = "net.fabricmc:fabric-loader:"
        case "Quilt": prefix = "org.quiltmc:quilt-loader:"
        case "Forge", "NeoForge":
            // 1.17+：游戏参数中带有版本号
            let key = loader == "Forge" ? "--fml.forgeVersion" : "--fml.neoForgeVersion"
            let args = json["arguments"]["game"].array.compactMap(\.string)
            if let i = args.firstIndex(of: key), i + 1 < args.count { return args[i + 1] }
            // 旧版：net.minecraftforge:forge:1.12.2-14.23.5.2864
            let lib = loader == "Forge" ? "net.minecraftforge:forge:" : "net.neoforged:neoforge:"
            guard let name = libraryNames.first(where: { $0.hasPrefix(lib) }) else { return nil }
            var v = String(name.dropFirst(lib.count).split(separator: ":")[0])
            let game = vanillaVersion
            if v.hasPrefix(game + "-") { v = String(v.dropFirst(game.count + 1)) }
            if v.hasSuffix("-" + game) { v = String(v.dropLast(game.count + 1)) }
            return v
        default: return nil
        }
        return libraryNames.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    package var isModded: Bool { !loaders.filter { $0 != "OptiFine" }.isEmpty }

    package var category: Category {
        if error != nil || !json.exists { return .error }
        if isModded { return .modded }
        if McVersionKind.isAprilFool(vanillaVersion) { return .aprilFool }
        switch type {
        case "release": return .release
        case "snapshot", "pending": return .snapshot
        default: return .old
        }
    }

    /// 版本图标：优先使用自定义的方块
    package var icon: String {
        if let custom = setup.icon, !custom.isEmpty { return custom }
        return defaultIcon
    }

    /// 按版本类型自动选择的图标
    package var defaultIcon: String {
        if category == .error { return "RedstoneBlock" }
        let l = loaders
        if l.contains("NeoForge") { return "NeoForge" }
        if l.contains("Fabric") || l.contains("Quilt") { return "Fabric" }
        if l.contains("Forge") { return "Anvil" }
        if l.contains("OptiFine") { return "GrassPath" }
        switch category {
        case .snapshot: return "CommandBlock"
        case .old: return "CobbleStone"
        case .aprilFool: return "GoldBlock"
        default: return "Grass"
        }
    }

    package var description: String {
        if let error { return error }
        var parts = [vanillaVersion]
        for l in loaders { parts.append(loaderVersion(l).map { "\(l) \($0)" } ?? l) }
        if parts.count == 1 {
            switch category {
            case .release: parts.append(T("正式版", "Release"))
            case .snapshot: parts.append(T("快照", "Snapshot"))
            case .old: parts.append(T("远古版", "Old Alpha/Beta"))
            case .aprilFool: parts.append(T("愚人节版", "April Fools"))
            default: break
            }
        }
        return parts.joined(separator: ", ")
    }

    /// 所需的 Java 主版本
    package var javaMajor: Int {
        if let m = json["javaVersion"]["majorVersion"].int { return m }
        // 没有 javaVersion 字段的老版本
        return 8
    }

    package var javaComponent: String {
        if let c = json["javaVersion"]["component"].string { return c }
        return "jre-legacy"
    }

    package var setup: LauncherSettings.InstanceSetup { LauncherSettings.shared.instanceSetup(dir) }

    /// 游戏时长的文字：“3 小时 20 分钟”；compact 时为“3.3 小时”。从未玩过时为 nil
    package static func formatPlayTime(_ seconds: Double?, compact: Bool = false) -> String? {
        guard let seconds, seconds >= 1 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return T("不到 1 分钟", "< 1 min") }
        if minutes < 60 { return T("\(minutes) 分钟", "\(minutes) min") }
        let hours = Double(minutes) / 60
        if compact {
            let h = hours < 100 ? String(format: "%.1f", hours) : String(Int(hours))
            return T("\(h) 小时", "\(h) h")
        }
        let h = minutes / 60, m = minutes % 60
        if m == 0 { return T("\(h) 小时", "\(h) h") }
        return T("\(h) 小时 \(m) 分钟", "\(h) h \(m) min")
    }

    /// 是否开启版本隔离
    package var isolated: Bool {
        if let v = setup.isolation { return v }
        // 已有 mods、saves 等文件夹时视为已隔离（与原版的判定思路一致）
        let fm = FileManager.default
        for sub in ["mods", "saves", "resourcepacks", "options.txt"] where fm.fileExists(atPath: dir.appendingPathComponent(sub).path) {
            return true
        }
        switch LauncherSettings.shared.isolation {
        case .none: return false
        case .all: return true
        case .moddedAndPreview: return isModded || category == .snapshot || category == .old || category == .aprilFool
        }
    }

    package var gameDir: URL { isolated ? dir : folder }

    /// 支持 inheritsFrom 的客户端 jar 位置
    package var clientJar: URL {
        let own = dir.appendingPathComponent("\(name).jar")
        if FileManager.default.fileExists(atPath: own.path) { return own }
        if let jar = raw["jar"].string, !jar.isEmpty {
            return folder.appendingPathComponent("versions/\(jar)/\(jar).jar")
        }
        if let p = parents.last {
            return folder.appendingPathComponent("versions/\(p)/\(p).jar")
        }
        return own
    }

    package var nativesDir: URL { dir.appendingPathComponent("\(name)-natives", isDirectory: true) }

    // MARK: 支持库

    package func libraries(_ ctx: RuleContext) -> [McLibrary] {
        var result: [McLibrary] = []
        var seen = Set<String>()
        let libDir = folder.appendingPathComponent("libraries", isDirectory: true)
        // Apple 芯片原生模式：将 LWJGL 3.1/3.2 替换为带 arm64 原生库的 3.3.1
        let patchLwjgl = ctx.arch == "arm64" && Arch.isAppleSilicon && lwjglNeedsArm64Patch
        let patchLwjgl2 = ctx.arch == "arm64" && Arch.isAppleSilicon && isLwjgl2 && LauncherSettings.shared.arm64Native
        func add(_ lib: McLibrary, key: String) {
            if seen.insert(key).inserted { result.append(lib) }
        }
        func artifact(_ name: String, _ art: JSON, _ lib: JSON) -> McLibrary? {
            guard let rel = art["path"].string ?? Maven.path(name) else { return nil }
            var url = art["url"].string
            if url == nil, !lib["downloads"].exists {
                let base = lib["url"].string ?? "https://libraries.minecraft.net/"
                url = (base.hasSuffix("/") ? base : base + "/") + rel
            }
            var nativeArch: String?
            if name.contains(":natives-macos") || name.contains(":natives-osx") {
                nativeArch = name.hasSuffix("arm64") ? "arm64" : "x86_64"
            }
            return McLibrary(name: name, path: libDir.appendingPathComponent(rel), url: url,
                             sha1: art["sha1"].string, size: art["size"].double.map { Int64($0) },
                             isNatives: false, nativeArch: nativeArch)
        }
        for lib in json["libraries"].array {
            guard let name = lib["name"].string else { continue }
            if lib["rules"].exists && !ctx.check(lib["rules"]) { continue }
            if patchLwjgl2, let patched = Lwjgl.lwjgl2Arm64Replacement(name, libDir: libDir) {
                for p in patched { add(p, key: Maven.key(p.name)) }
                continue
            }
            if patchLwjgl, let patched = Lwjgl.arm64Replacement(name, libDir: libDir) {
                for p in patched { add(p, key: Maven.key(p.name)) }
                continue
            }
            let natives = lib["natives"]
            if natives.exists {
                // 旧式 natives：同一条目中也可能带有需要加入 classpath 的 artifact（如 java-objc-bridge）
                if lib["downloads"]["artifact"].exists, let a = artifact(name, lib["downloads"]["artifact"], lib) {
                    add(a, key: Maven.key(name))
                }
                guard var cls = natives["osx"].string ?? natives["macos"].string else { continue }
                cls = cls.replacingOccurrences(of: "${arch}", with: "64")
                let art = lib["downloads"]["classifiers"][cls]
                let rel = art["path"].string ?? Maven.path(name, classifier: cls) ?? ""
                let base = lib["url"].string ?? "https://libraries.minecraft.net/"
                add(McLibrary(
                    name: name, path: libDir.appendingPathComponent(rel),
                    url: art["url"].string ?? (base.hasSuffix("/") ? base : base + "/") + rel,
                    sha1: art["sha1"].string, size: art["size"].double.map { Int64($0) },
                    isNatives: true, nativeArch: nil,
                    exclude: lib["extract"]["exclude"].array.compactMap(\.string)), key: Maven.key(name) + ":" + cls)
                continue
            }
            if let a = artifact(name, lib["downloads"]["artifact"], lib) { add(a, key: Maven.key(name)) }
        }
        return result
    }

    /// 使用的 LWJGL 版本（如 "3.2.2"、"2.9.4-nightly-20150209"）
    package var lwjglVersion: String? {
        for n in libraryNames where n.hasPrefix("org.lwjgl:lwjgl:") || n.hasPrefix("org.lwjgl.lwjgl:lwjgl:") {
            let parts = n.split(separator: ":")
            if parts.count >= 3 { return String(parts[2]) }
        }
        return nil
    }

    /// LWJGL 3.1 / 3.2 没有 arm64 原生库，但可以安全替换为 3.3.1
    package var lwjglNeedsArm64Patch: Bool {
        guard let v = lwjglVersion, v.hasPrefix("3.") else { return false }
        return !hasArm64Natives && (v.hasPrefix("3.1") || v.hasPrefix("3.2"))
    }

    /// 是否为 LWJGL 2（1.12.2 及以前），只能通过 Rosetta 2 运行
    package var isLwjgl2: Bool { lwjglVersion?.hasPrefix("2.") ?? false }

    /// 该版本是否自带 Apple 芯片原生库（1.19 起）
    package var hasArm64Natives: Bool {
        libraryNames.contains { $0.hasSuffix("natives-macos-arm64") }
    }

    /// 是否需要原生库
    package var needsNatives: Bool {
        json["libraries"].array.contains { $0["natives"].exists || ($0["name"].string ?? "").contains("natives-macos") }
    }

    /// 能否在 Apple 芯片上原生运行（不经过 Rosetta 2）
    package var canRunNativelyOnArm: Bool {
        !needsNatives || hasArm64Natives || lwjglNeedsArm64Patch || isLwjgl2
    }

    // MARK: 资源文件

    package var assetIndexId: String { json["assetIndex"]["id"].string ?? json["assets"].string ?? "legacy" }
}

/// 版本文件夹扫描
package enum InstanceScanner {
    package static func scan(_ folder: URL) -> [McInstance] {
        let versions = folder.appendingPathComponent("versions", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: versions.path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .filter { n in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: versions.appendingPathComponent(n).path, isDirectory: &isDir) && isDir.boolValue
            }
            .map { McInstance(folder: folder, name: $0) }
            .filter { $0.raw.exists || FileManager.default.fileExists(atPath: $0.dir.appendingPathComponent("\($0.name).jar").path) }
            .sorted { a, b in
                if a.category != b.category { return a.category < b.category }
                return a.releaseTime > b.releaseTime
            }
    }
}
