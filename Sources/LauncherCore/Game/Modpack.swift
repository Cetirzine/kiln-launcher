import Foundation

/// 整合包：安装 Modrinth（.mrpack）与 CurseForge（manifest.json）格式，导出为 .mrpack。
/// CurseForge 的文件信息一次批量查询；作者禁止第三方下载的文件会列出来，由用户手动下载后自动放入。
package enum Modpack {
    package enum Format: String, Sendable { case modrinth = "Modrinth", curseforge = "CurseForge" }

    package struct Info: Sendable {
        package let format: Format
        package let name: String
        package let version: String
        package let summary: String
        package let gameVersion: String
        /// 加载器：Fabric / Quilt / Forge / NeoForge 及版本
        package let loader: (kind: String, version: String)?
        package let fileCount: Int
        let manifest: JSON
    }

    /// 需要手动下载的文件（CurseForge 作者禁止第三方下载）
    package struct ManualFile: Sendable, Hashable, Identifiable {
        package var id: String { destination.path }
        package let title: String
        package let fileName: String
        package let pageURL: String
        package let destination: URL
        package let sha1: String?

        package init(title: String, fileName: String, pageURL: String, destination: URL, sha1: String?) {
            self.title = title; self.fileName = fileName; self.pageURL = pageURL; self.destination = destination; self.sha1 = sha1
        }
    }

    // MARK: 读取

    package static func inspect(_ archive: URL) throws -> Info {
        if let data = Zip.read(archive, "modrinth.index.json"), let j = try? JSON(data: data) {
            let deps = j["dependencies"]
            guard let game = deps["minecraft"].string else { throw LauncherError(T("整合包缺少 Minecraft 版本", "The modpack doesn't specify a Minecraft version")) }
            var loader: (String, String)?
            for (key, kind) in [("fabric-loader", "Fabric"), ("quilt-loader", "Quilt"), ("neoforge", "NeoForge"), ("forge", "Forge")] {
                if let v = deps[key].string { loader = (kind, v); break }
            }
            let files = j["files"].array.filter { $0["env"]["client"].string != "unsupported" }
            return Info(format: .modrinth, name: j["name"].string ?? archive.deletingPathExtension().lastPathComponent,
                        version: j["versionId"].string ?? "", summary: j["summary"].string ?? "",
                        gameVersion: game, loader: loader, fileCount: files.count, manifest: j)
        }
        if let data = Zip.read(archive, "manifest.json"), let j = try? JSON(data: data), j["manifestType"].string == "minecraftModpack" {
            let mc = j["minecraft"]
            guard let game = mc["version"].string else { throw LauncherError(T("整合包缺少 Minecraft 版本", "The modpack doesn't specify a Minecraft version")) }
            let loaders = mc["modLoaders"].array
            let primary = loaders.first { $0["primary"].bool == true } ?? loaders.first
            var loader: (String, String)?
            if let id = primary?["id"].string, let dash = id.firstIndex(of: "-") {
                let kind = id[..<dash].lowercased(), ver = String(id[id.index(after: dash)...])
                switch kind {
                case "forge": loader = ("Forge", ver)
                case "neoforge": loader = ("NeoForge", ver)
                case "fabric": loader = ("Fabric", ver)
                case "quilt": loader = ("Quilt", ver)
                default: break
                }
            }
            return Info(format: .curseforge, name: j["name"].string ?? archive.deletingPathExtension().lastPathComponent,
                        version: j["version"].string ?? "", summary: j["author"].string.map { T("作者：\($0)", "By \($0)") } ?? "",
                        gameVersion: game, loader: loader, fileCount: j["files"].array.count, manifest: j)
        }
        throw LauncherError(T("不是支持的整合包（需要 Modrinth 的 .mrpack 或 CurseForge 整合包）",
                              "Not a supported modpack (expected a Modrinth .mrpack or a CurseForge modpack)"))
    }

    // MARK: 安装

    /// 安装整合包为新版本；返回需要手动下载的文件
    package static func install(_ archive: URL, name: String, folder: URL, job: Job) async throws -> [ManualFile] {
        let info = try inspect(archive)
        let fm = FileManager.default
        let dir = folder.appendingPathComponent("versions/\(name)", isDirectory: true)
        if fm.fileExists(atPath: dir.path) { throw LauncherError(T("已存在名为 \(name) 的版本", "An instance named \(name) already exists")) }
        // 安装失败时删除未完成的版本，避免留下无法启动的版本
        var finished = false
        defer { if !finished { try? fm.removeItem(at: dir) } }

        // 1. 游戏与加载器
        try await installGame(info.gameVersion, loader: info.loader, name: name, folder: folder, job: job)
        let instance = McInstance(folder: folder, name: name)
        // 整合包总是使用独立的游戏目录
        var setup = instance.setup
        setup.isolation = true
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)
        let gameDir = instance.dir

        // 2. 解压覆盖文件
        await job.enter(T("解压整合包", "Extracting the modpack"), index: 0, of: 2)
        let tmp = Paths.cache.appendingPathComponent("modpack-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try Zip.extractAll(archive, to: tmp)
        let overrideDirs: [String]
        switch info.format {
        case .modrinth: overrideDirs = ["overrides", "client-overrides"]
        case .curseforge: overrideDirs = [info.manifest["overrides"].string ?? "overrides"]
        }
        for sub in overrideDirs { try merge(tmp.appendingPathComponent(sub), into: gameDir) }

        // 3. 下载文件
        await job.enter(T("下载整合包文件", "Downloading modpack files"), index: 1, of: 2)
        var manual: [ManualFile] = []
        switch info.format {
        case .modrinth:
            var items: [DownloadItem] = []
            for f in info.manifest["files"].array where f["env"]["client"].string != "unsupported" {
                guard let path = f["path"].string, let dest = safePath(path, in: gameDir) else { continue }
                let urls = f["downloads"].array.compactMap(\.string)
                guard !urls.isEmpty else { continue }
                var item = DownloadItem(url: urls[0], destination: dest, sha1: f["hashes"]["sha1"].string,
                                        size: f["fileSize"].double.map { Int64($0) })
                item.urls = urls
                items.append(item)
            }
            try await Downloader.run(items, job: job)
        case .curseforge:
            let entries = info.manifest["files"].array.filter { $0["required"].bool != false }
            let fileIds = entries.compactMap { $0["fileID"].int }
            let projectIds = Array(Set(entries.compactMap { $0["projectID"].int }))
            async let filesTask = CurseForge.files(ids: fileIds)
            async let projectsTask = CurseForge.projects(ids: projectIds)
            let files = try await filesTask
            let projects = (try? await projectsTask) ?? [:]
            var items: [DownloadItem] = []
            var missing: [String] = []
            for e in entries {
                guard let fid = e["fileID"].int, let pid = e["projectID"].int else { continue }
                guard let v = files[fid] else { missing.append("\(pid)/\(fid)"); continue }
                let classId = projects[pid]?.classId ?? 6
                let sub: String
                switch classId {
                case 12: sub = "resourcepacks"
                case 6552: sub = "shaderpacks"
                default: sub = "mods"
                }
                guard let dest = safePath("\(sub)/\(v.fileName)", in: gameDir) else { continue }
                if v.blocked {
                    let page = projects[pid].map { CurseForge.pageURL(classId: classId, slug: $0.project.slug) + "/files/\(fid)" }
                        ?? "https://www.curseforge.com/projects/\(pid)"
                    manual.append(ManualFile(title: projects[pid]?.project.title ?? v.fileName, fileName: v.fileName,
                                             pageURL: page, destination: dest, sha1: v.sha1))
                    continue
                }
                var item = DownloadItem(url: v.fileURL, destination: dest, sha1: v.sha1, size: v.size)
                item.urls = CurseForge.downloadURLs(v)
                items.append(item)
            }
            if !missing.isEmpty { log("[Modpack] CurseForge 上找不到 \(missing.count) 个文件：\(missing.joined(separator: ", "))") }
            // 作者禁止第三方下载的文件：如果作者也在 Modrinth 上发布了同一个文件（SHA-1 相同），从 Modrinth 下载
            let hashes = manual.compactMap(\.sha1)
            if !hashes.isEmpty, let found = try? await Modrinth.versionsByHash(hashes) {
                manual = manual.filter { m in
                    guard let sha1 = m.sha1, let v = found[sha1],
                          let file = v["files"].array.first(where: { $0["hashes"]["sha1"].string == sha1 }),
                          let url = file["url"].string else { return true }
                    items.append(DownloadItem(url: url, destination: m.destination, sha1: sha1, size: file["size"].double.map { Int64($0) }))
                    log("[Modpack] \(m.fileName) 改从 Modrinth 下载（SHA-1 一致）")
                    return false
                }
            }
            try await Downloader.run(items, job: job)
        }

        // 记录来源，便于以后识别
        let meta = JSON.object(["format": .string(info.format.rawValue), "name": .string(info.name), "version": .string(info.version)])
        try? meta.data().write(to: instance.dir.appendingPathComponent(".kiln/modpack.json"))
        finished = true
        return manual
    }

    /// 在“下载”文件夹中查找用户手动下载的文件（校验 SHA-1 后移到目标位置），返回仍未找到的文件
    package static func collectManualDownloads(_ files: [ManualFile]) -> [ManualFile] {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return files.filter { m in
            // 浏览器可能把空格等字符替换掉，同时比较原名与常见变体
            let candidates = [m.fileName, m.fileName.replacingOccurrences(of: " ", with: "+"), m.fileName.replacingOccurrences(of: " ", with: "_")]
            for name in candidates {
                let src = downloads.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                if let sha1 = m.sha1, Hash.sha1(file: src) != sha1 { continue }
                try? fm.createDirectory(at: m.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: m.destination)
                if (try? fm.moveItem(at: src, to: m.destination)) != nil { return false }
            }
            return true
        }
    }

    /// 安装游戏与加载器（Fabric / Quilt / Forge / NeoForge）为新版本
    package static func installGame(_ gameVersion: String, loader: (kind: String, version: String)?, name: String, folder: URL, job: Job) async throws {
        let game = try await VersionManifest.find(gameVersion)
        switch loader?.kind {
        case "Fabric"?, "Quilt"?:
            let kind = ModLoaderKind(rawValue: loader!.kind)!
            try await Installer.install(version: game, name: name, loader: (kind, loader!.version), folder: folder, job: job)
        case "Forge"?, "NeoForge"?:
            let kind = ForgeKind(rawValue: loader!.kind)!
            let maven = try await mavenVersion(kind, loader!.version, game: gameVersion)
            try await ForgeInstaller.install(kind, version: maven, game: game, name: name, folder: folder, job: job)
        default:
            try await Installer.install(version: game, name: name, loader: nil, folder: folder, job: job)
        }
    }

    /// 整合包中的加载器版本 → Forge / NeoForge 的 Maven 版本号
    package static func mavenVersion(_ kind: ForgeKind, _ v: String, game: String) async throws -> String {
        let list = (try? await ForgeInstaller.versions(kind, game: game)) ?? []
        // 早期 NeoForge 带 -beta 后缀：21.0.18 → 21.0.18-beta
        if let hit = list.first(where: { $0.version == v || $0.display == v || $0.version == "\(game)-\(v)" })
            ?? list.first(where: { $0.version.hasPrefix(v + "-") || $0.version.hasPrefix("\(game)-\(v)-") }) {
            return hit.version
        }
        if kind == .forge && !v.hasPrefix(game) { return "\(game)-\(v)" }
        return v
    }

    /// 相对路径解析到游戏目录内；拒绝绝对路径与 ..
    package static func safePath(_ path: String, in root: URL) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard !path.hasPrefix("/"), !parts.isEmpty, !parts.contains(".."), !parts.contains(where: { $0.contains("\\") }) else { return nil }
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    /// 把目录内容合并复制到目标（覆盖同名文件，跳过符号链接）
    static func merge(_ src: URL, into dst: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue else { return }
        guard let e = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        // /tmp 等路径经过符号链接，先统一解析再计算相对路径
        let base = src.resolvingSymlinksInPath().path
        for case let url as URL in e {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            guard let target = safePath(rel, in: dst) else { continue }
            if values?.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: url, to: target)
            }
        }
    }

    // MARK: 导出

    /// 可以选择导出的内容（游戏目录顶层）
    package struct ExportItem: Identifiable, Hashable, Sendable {
        package var id: String { path }
        package let path: String
        package let size: Int64
        package let isDirectory: Bool
        /// 默认选中
        package let suggested: Bool
    }

    /// 不应导出的内容：缓存、日志、账号信息与启动器文件
    static let excluded: Set<String> = ["logs", "crash-reports", "versions", "assets", "libraries", "natives", ".kiln", ".fabric",
                                        ".mixin.out", "debug", "downloads", "usercache.json", "usernamecache.json",
                                        "launcher_profiles.json", "command_history.txt", ".DS_Store", "backups", ".cache", "local"]
    /// 默认不勾选：个人数据
    static let personal: Set<String> = ["saves", "screenshots", "servers.dat", "servers.dat_old", "options.txt", "optionsof.txt",
                                        "optionsshaders.txt", "schematics", "replay_recordings", "journeymap", "xaero", "XaeroWorldMap", "XaeroWaypoints"]

    package static func exportItems(_ instance: McInstance) -> [ExportItem] {
        let fm = FileManager.default
        let dir = instance.gameDir
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { n in
            if excluded.contains(n) || n.hasSuffix(".log") || n.hasPrefix(".") { return nil }
            // 独立游戏目录中的版本文件
            if instance.isolated && (n == "\(instance.name).json" || n == "\(instance.name).jar" || n == "\(instance.name)-natives") { return nil }
            let url = dir.appendingPathComponent(n)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return ExportItem(path: n, size: size(of: url), isDirectory: isDir.boolValue, suggested: !personal.contains(n))
        }.sorted { ($0.isDirectory ? 0 : 1, $0.path.lowercased()) < ($1.isDirectory ? 0 : 1, $1.path.lowercased()) }
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    package struct ExportResult: Sendable {
        /// 以 Modrinth 下载地址引用的文件数
        package let linked: Int
        /// 直接打包的文件数
        package let embedded: Int
    }

    /// 导出为 .mrpack：能在 Modrinth 上找到的 Mod / 资源包 / 光影以下载地址引用，其余文件放入 overrides
    package static func export(_ instance: McInstance, name: String, version: String, summary: String,
                               include: Set<String>, to output: URL, job: Job) async throws -> ExportResult {
        let fm = FileManager.default
        let gameDir = instance.gameDir
        await job.enter(T("整理文件", "Collecting files"), index: 0, of: 3)
        // 收集文件
        var files: [(rel: String, url: URL)] = []
        for top in include.sorted() {
            let url = gameDir.appendingPathComponent(top)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue { files.append((top, url)); continue }
            guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            let base = url.resolvingSymlinksInPath().path
            for case let f as URL in e {
                let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard v?.isRegularFile == true, v?.isSymbolicLink != true, f.lastPathComponent != ".DS_Store" else { continue }
                let full = f.resolvingSymlinksInPath().path
                guard full.hasPrefix(base + "/") else { continue }
                files.append((top + "/" + full.dropFirst(base.count + 1), f))
            }
        }

        // 在 Modrinth 上查找：mods / resourcepacks / shaderpacks 中的文件
        await job.enter(T("在 Modrinth 上查找文件", "Looking up files on Modrinth"), index: 1, of: 3)
        let linkable = files.filter { f in
            let parts = f.rel.split(separator: "/")
            return parts.count == 2 && ["mods", "resourcepacks", "shaderpacks"].contains(String(parts[0]))
                && !f.rel.hasSuffix(".disabled")
        }
        var hashes: [String: String] = [:]
        for f in linkable { if let h = Hash.sha1(file: f.url) { hashes[f.rel] = h } }
        let found = (try? await Modrinth.versionsByHash(Array(hashes.values))) ?? [:]
        var indexFiles: [JSON] = []
        var linkedPaths = Set<String>()
        for f in linkable {
            guard let sha1 = hashes[f.rel], let v = found[sha1],
                  let file = v["files"].array.first(where: { $0["hashes"]["sha1"].string == sha1 }),
                  let url = file["url"].string, let sha512 = file["hashes"]["sha512"].string else { continue }
            indexFiles.append(.object([
                "path": .string(f.rel),
                "hashes": .object(["sha1": .string(sha1), "sha512": .string(sha512)]),
                "env": .object(["client": .string("required"), "server": .string(f.rel.hasPrefix("mods/") ? "required" : "unsupported")]),
                "downloads": .array([.string(url)]),
                "fileSize": .number(file["size"].double ?? 0),
            ]))
            linkedPaths.insert(f.rel)
        }

        // 打包
        await job.enter(T("打包", "Packing"), index: 2, of: 3)
        let staging = Paths.cache.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var embedded = 0
        for f in files where !linkedPaths.contains(f.rel) {
            guard let dest = safePath("overrides/" + f.rel, in: staging) else { continue }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // APFS 上为写时克隆，不额外占用空间
            try fm.copyItem(at: f.url, to: dest)
            embedded += 1
        }
        var deps: [String: JSON] = ["minecraft": .string(instance.vanillaVersion)]
        for l in instance.loaders {
            guard let v = instance.loaderVersion(l) else { continue }
            switch l {
            case "Fabric": deps["fabric-loader"] = .string(v)
            case "Quilt": deps["quilt-loader"] = .string(v)
            case "Forge": deps["forge"] = .string(v)
            case "NeoForge": deps["neoforge"] = .string(v)
            default: break
            }
        }
        var index: [String: JSON] = ["formatVersion": .number(1), "game": .string("minecraft"), "versionId": .string(version),
                                     "name": .string(name), "files": .array(indexFiles), "dependencies": .object(deps)]
        if !summary.isEmpty { index["summary"] = .string(summary) }
        try JSON.object(index).data().write(to: staging.appendingPathComponent("modrinth.index.json"))
        try? fm.removeItem(at: output)
        try Updater.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", staging.path, output.path])
        return ExportResult(linked: linkedPaths.count, embedded: embedded)
    }
}
