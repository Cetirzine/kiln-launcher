import Foundation

package enum Installer {
    // MARK: 安装新版本

    /// 安装原版，可选附带 Fabric / Quilt
    package static func install(version: RemoteVersion, name: String, loader: (ModLoaderKind, String)?, folder: URL, job: Job) async throws {
        let fm = FileManager.default
        let total = loader == nil ? 4 : 5
        await job.enter(T("下载版本 JSON", "Download version JSON"), index: 0, of: total)

        // 原版 JSON
        let vanillaDir = folder.appendingPathComponent("versions/\(version.id)", isDirectory: true)
        let vanillaJsonURL = vanillaDir.appendingPathComponent("\(version.id).json")
        if loader != nil || name != version.id {
            // 安装加载器或自定义名称时，原版 JSON 依然保存在原版名称下，供 inheritsFrom 使用
            if !fm.fileExists(atPath: vanillaJsonURL.path) {
                try await downloadVanillaJson(version, to: vanillaJsonURL)
            }
        }

        let targetDir = folder.appendingPathComponent("versions/\(name)", isDirectory: true)
        if fm.fileExists(atPath: targetDir.appendingPathComponent("\(name).json").path) {
            throw LauncherError(T("已存在名为 \(name) 的版本", "An instance named \(name) already exists"))
        }
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetJson = targetDir.appendingPathComponent("\(name).json")

        if let (kind, loaderVersion) = loader {
            await job.enter(T("获取 \(kind.rawValue)", "Fetch \(kind.rawValue)"), index: 1, of: total)
            let data = try await Net.data(Net.candidates(kind.profileURL(game: version.id, loader: loaderVersion), kind: .versionList))
            var profile = try JSON(data: data).object
            profile["id"] = .string(name)
            profile["inheritsFrom"] = .string(version.id)
            try JSON.object(profile).data().write(to: targetJson)
        } else if name == version.id {
            try await downloadVanillaJson(version, to: targetJson)
        } else {
            var j = try JSON(data: Data(contentsOf: vanillaJsonURL)).object
            j["id"] = .string(name)
            j["clientVersion"] = .string(version.id)
            try JSON.object(j).data().write(to: targetJson)
        }

        // 新版本的隔离设置
        let instance = McInstance(folder: folder, name: name)
        var setup = instance.setup
        setup.isolation = instance.isolated
        LauncherSettings.shared.saveInstanceSetup(setup, targetDir)

        try await completeFiles(instance, job: job, stageOffset: total - 3, stageCount: total)

        // 自动调整游戏语言
        if LauncherSettings.shared.gameLanguageAuto {
            writeGameLanguage(instance)
        }
    }

    private static func downloadVanillaJson(_ version: RemoteVersion, to url: URL) async throws {
        let item = DownloadItem(url: version.url, destination: url, sha1: version.sha1, kind: .versionList)
        try await Downloader.fetch(item)
    }

    /// 将游戏语言设置为启动器语言
    package static func writeGameLanguage(_ instance: McInstance) {
        let options = instance.gameDir.appendingPathComponent("options.txt")
        guard !FileManager.default.fileExists(atPath: options.path) else { return }
        let code = LauncherSettings.shared.language.gameLanguage
        // 1.10 及以前使用 xx_XX 格式
        let old = instance.releaseTime < ISO8601DateFormatter().date(from: "2016-11-01T00:00:00Z")!
        let value = old ? String(code.prefix(3)) + code.suffix(2).uppercased() : code
        try? FileManager.default.createDirectory(at: instance.gameDir, withIntermediateDirectories: true)
        try? "lang:\(value)\n".write(to: options, atomically: true, encoding: .utf8)
    }

    // MARK: 补全文件

    /// 补全某个版本运行所需的所有文件（原版 JSON、客户端、支持库、资源文件）
    package static func completeFiles(_ instance: McInstance, job: Job?, stageOffset: Int = 0, stageCount: Int = 3,
                              arch: String? = nil, quick: Bool = false) async throws {
        let fm = FileManager.default
        // 缺失的前置版本
        if let parent = instance.missingParent {
            let remote = try await VersionManifest.find(parent)
            let url = instance.folder.appendingPathComponent("versions/\(parent)/\(parent).json")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await downloadVanillaJson(remote, to: url)
            instance.reload()
        }
        let json = instance.json
        let ctx = RuleContext(arch: arch ?? instance.preferredArch)

        // 客户端与支持库
        await MainActor.run { job?.enter(T("下载游戏文件", "Downloading game files"), index: stageOffset, of: stageCount) }
        var items: [DownloadItem] = []
        let client = json["downloads"]["client"]
        if let url = client["url"].string {
            items.append(DownloadItem(url: url, destination: instance.clientJar, sha1: client["sha1"].string,
                                      size: client["size"].double.map { Int64($0) }))
        }
        for lib in instance.libraries(ctx) {
            if let d = lib.download { items.append(d) }
            else if !fm.fileExists(atPath: lib.path.path) {
                log("[Install] 支持库 \(lib.name) 缺失，且没有下载地址")
            }
        }
        if let logging = json["logging"]["client"]["file"]["url"].string, let id = json["logging"]["client"]["file"]["id"].string {
            items.append(DownloadItem(url: logging,
                                      destination: instance.folder.appendingPathComponent("assets/log_configs/\(id)"),
                                      sha1: json["logging"]["client"]["file"]["sha1"].string))
        }
        try await Downloader.run(items, job: job, checkHash: !quick)

        // 与官方启动器一致：继承版本使用自己目录下的 <名称>.jar（Forge 1.17+ 的 ignoreList 依赖这个文件名）。
        // APFS 上 copyItem 会创建写时克隆，不额外占用空间。
        let ownJar = instance.dir.appendingPathComponent("\(instance.name).jar")
        if !instance.parents.isEmpty, !fm.fileExists(atPath: ownJar.path), fm.fileExists(atPath: instance.clientJar.path) {
            try? fm.copyItem(at: instance.clientJar, to: ownJar)
        }

        // 资源文件
        await MainActor.run { job?.enter(T("下载资源文件", "Download assets"), index: stageOffset + 1, of: stageCount) }
        if !(quick && LauncherSettings.shared.skipAssetCheck) {
            try await completeAssets(instance, job: job, checkHash: false)
        }
        await MainActor.run { job?.enter(T("完成", "Done"), index: stageOffset + 2, of: stageCount) }
    }

    package static func completeAssets(_ instance: McInstance, job: Job?, checkHash: Bool) async throws {
        let json = instance.json
        let assets = instance.folder.appendingPathComponent("assets", isDirectory: true)
        let index = json["assetIndex"]
        guard let indexURL = index["url"].string, let id = index["id"].string else { return }
        let indexFile = assets.appendingPathComponent("indexes/\(id).json")
        let indexItem = DownloadItem(url: indexURL, destination: indexFile, sha1: index["sha1"].string)
        if !indexItem.isValid() { try await Downloader.fetch(indexItem) }
        let indexJson = try JSON(data: Data(contentsOf: indexFile))
        var items: [DownloadItem] = []
        var copies: [(URL, URL)] = []
        let isVirtual = indexJson["virtual"].bool == true
        let mapToResources = indexJson["map_to_resources"].bool == true
        for (path, obj) in indexJson["objects"].object {
            guard let hash = obj["hash"].string, hash.count > 2 else { continue }
            let prefix = String(hash.prefix(2))
            let dest = assets.appendingPathComponent("objects/\(prefix)/\(hash)")
            items.append(DownloadItem(url: "https://resources.download.minecraft.net/\(prefix)/\(hash)", destination: dest,
                                      sha1: hash, size: obj["size"].double.map { Int64($0) }))
            if isVirtual { copies.append((dest, assets.appendingPathComponent("virtual/\(id)/\(path)"))) }
            if mapToResources { copies.append((dest, instance.gameDir.appendingPathComponent("resources/\(path)"))) }
        }
        try await Downloader.run(items, job: job, checkHash: checkHash)
        let fm = FileManager.default
        for (src, dst) in copies where !fm.fileExists(atPath: dst.path) {
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
