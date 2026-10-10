import Foundation

/// Forge / NeoForge 安装（实现思路参考 HMCL：解析安装器中的 install_profile.json，下载支持库并运行 processors）
package enum ForgeKind: String, CaseIterable, Identifiable, Sendable {
    case forge = "Forge", neoforge = "NeoForge"
    package var id: String { rawValue }

    var installerURL: (String) -> String {
        switch self {
        case .forge: return { "https://maven.minecraftforge.net/net/minecraftforge/forge/\($0)/forge-\($0)-installer.jar" }
        case .neoforge: return { "https://maven.neoforged.net/releases/net/neoforged/neoforge/\($0)/neoforge-\($0)-installer.jar" }
        }
    }
}

package enum ForgeInstaller {
    package struct Version: Identifiable, Hashable, Sendable {
        /// Maven 版本号，如 1.20.1-47.2.0 / 21.1.77
        package let version: String
        package var id: String { version }
        /// 显示用的简短版本号
        package var display: String {
            if let r = version.range(of: "-") , version.hasPrefix("1.") { return String(version[r.upperBound...]) }
            return version
        }
        package var isBeta: Bool { version.contains("beta") || version.contains("alpha") }
    }

    // MARK: 版本列表

    package static func versions(_ kind: ForgeKind, game: String) async throws -> [Version] {
        switch kind {
        case .forge:
            let j = try await Net.json(urls: ["https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json",
                                              "https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/maven-metadata.json"])
            return j[game].array.compactMap(\.string).reversed().map(Version.init(version:))
        case .neoforge:
            let j = try await Net.json(urls: ["https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge",
                                              "https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/neoforge"])
            let all = j["versions"].array.compactMap(\.string)
            return all.filter { neoForgeGameVersion($0) == game }.reversed().map(Version.init(version:))
        }
    }

    /// NeoForge 版本号对应的 Minecraft 版本：21.1.77 → 1.21.1，20.4.x → 1.20.4，26.1.0.3 → 26.1
    package static func neoForgeGameVersion(_ v: String) -> String? {
        let comps = v.split(separator: "-")[0].split(separator: ".").compactMap { Int($0) }
        guard comps.count >= 2 else { return nil }
        if comps[0] >= 26 {
            // 新的年份版本号：主.次.修订.构建
            let patch = comps.count >= 4 ? comps[2] : 0
            return patch == 0 ? "\(comps[0]).\(comps[1])" : "\(comps[0]).\(comps[1]).\(patch)"
        }
        return comps[1] == 0 ? "1.\(comps[0])" : "1.\(comps[0]).\(comps[1])"
    }

    // MARK: 安装

    package static func install(_ kind: ForgeKind, version: String, game: RemoteVersion, name: String, folder: URL, job: Job) async throws {
        let fm = FileManager.default
        let total = 5
        let libraries = folder.appendingPathComponent("libraries", isDirectory: true)

        // 1. 原版
        await job.enter(T("准备原版 \(game.id)", "Preparing vanilla \(game.id)"), index: 0, of: total)
        let vanillaJson = folder.appendingPathComponent("versions/\(game.id)/\(game.id).json")
        if !fm.fileExists(atPath: vanillaJson.path) {
            try fm.createDirectory(at: vanillaJson.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await Downloader.fetch(DownloadItem(url: game.url, destination: vanillaJson, sha1: game.sha1, kind: .versionList))
        }
        let vanilla = McInstance(folder: folder, name: game.id)
        try await Installer.completeFiles(vanilla, job: nil)

        // 2. 安装器
        await job.enter(T("下载 \(kind.rawValue) 安装器", "Downloading the \(kind.rawValue) installer"), index: 1, of: total)
        let installer = Paths.cache.appendingPathComponent("\(kind.rawValue.lowercased())-\(version)-installer.jar")
        try await Downloader.fetch(DownloadItem(url: kind.installerURL(version), destination: installer))
        guard let profileData = Zip.read(installer, "install_profile.json") else {
            throw LauncherError(T("安装器中缺少 install_profile.json", "install_profile.json is missing from the installer"))
        }
        // 旧地址替换为新的 HTTPS 地址
        let profileText = String(decoding: profileData, as: UTF8.self)
            .replacingOccurrences(of: "http://files.minecraftforge.net/maven/", with: "https://maven.minecraftforge.net/")
        let profile = try JSON(data: Data(profileText.utf8))

        let targetDir = folder.appendingPathComponent("versions/\(name)", isDirectory: true)
        if fm.fileExists(atPath: targetDir.appendingPathComponent("\(name).json").path) {
            throw LauncherError(T("已存在名为 \(name) 的版本", "An instance named \(name) already exists"))
        }
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        if profile["install"].exists {
            // 旧格式（1.12.2 及以前）
            try await installLegacy(profile: profile, installer: installer, game: game, name: name, targetDir: targetDir, libraries: libraries, job: job)
        } else {
            try await installModern(profile: profile, installer: installer, vanilla: vanilla, game: game, name: name,
                                    targetDir: targetDir, folder: folder, libraries: libraries, job: job)
        }

        await job.enter(T("检查文件", "Verifying files"), index: 4, of: total)
        let instance = McInstance(folder: folder, name: name)
        var setup = instance.setup
        setup.isolation = instance.isolated
        LauncherSettings.shared.saveInstanceSetup(setup, targetDir)
        try await Installer.completeFiles(instance, job: nil)
        if LauncherSettings.shared.gameLanguageAuto { Installer.writeGameLanguage(instance) }
    }

    private static func writeVersionJson(_ json: JSON, name: String, game: String, to dir: URL) throws {
        var j = json.object
        j["id"] = .string(name)
        if j["inheritsFrom"] == nil { j["inheritsFrom"] = .string(game) }
        j["jar"] = nil
        try JSON.object(j).data().write(to: dir.appendingPathComponent("\(name).json"))
    }

    private static func installLegacy(profile: JSON, installer: URL, game: RemoteVersion, name: String, targetDir: URL,
                                      libraries: URL, job: Job) async throws {
        await job.enter(T("安装支持库", "Installing libraries"), index: 2, of: 5)
        let install = profile["install"]
        if let coords = install["path"].string, let file = install["filePath"].string, let rel = Maven.path(coords) {
            try Zip.extract(installer, file, to: libraries.appendingPathComponent(rel))
        }
        var info = profile["versionInfo"].object
        // 只保留客户端需要的支持库
        info["libraries"] = .array(profile["versionInfo"]["libraries"].array.filter { $0["clientreq"].bool != false })
        try writeVersionJson(.object(info), name: name, game: game.id, to: targetDir)
    }

    private static func installModern(profile: JSON, installer: URL, vanilla: McInstance, game: RemoteVersion, name: String,
                                      targetDir: URL, folder: URL, libraries: URL, job: Job) async throws {
        let fm = FileManager.default
        // 版本 JSON
        var jsonPath = profile["json"].string ?? "/version.json"
        if jsonPath.hasPrefix("/") { jsonPath.removeFirst() }
        guard let versionData = Zip.read(installer, jsonPath) else {
            throw LauncherError(T("安装器中缺少 version.json", "version.json is missing from the installer"))
        }
        let versionJson = try JSON(data: versionData)

        // 支持库：安装器内置的直接解压，其余下载
        await job.enter(T("下载支持库", "Downloading libraries"), index: 2, of: 5)
        var items: [DownloadItem] = []
        for lib in profile["libraries"].array + versionJson["libraries"].array {
            guard let name = lib["name"].string else { continue }
            let art = lib["downloads"]["artifact"]
            guard let rel = art["path"].string ?? Maven.path(name) else { continue }
            let dest = libraries.appendingPathComponent(rel)
            if let url = art["url"].string, !url.isEmpty {
                items.append(DownloadItem(url: url, destination: dest, sha1: art["sha1"].string, size: art["size"].double.map { Int64($0) }))
            } else if !fm.fileExists(atPath: dest.path) {
                try? Zip.extract(installer, "maven/\(rel)", to: dest)
            }
        }
        try await Downloader.run(items, job: job)

        // data 字段
        let work = Paths.cache.appendingPathComponent("forge-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        var data: [String: String] = [
            "SIDE": "client",
            "MINECRAFT_JAR": vanilla.clientJar.path,
            "MINECRAFT_VERSION": game.id,
            "ROOT": folder.path,
            "INSTALLER": installer.path,
            "LIBRARY_DIR": libraries.path,
        ]
        for (key, value) in profile["data"].object {
            guard let v = value["client"].string else { continue }
            data[key] = try resolveData(v, installer: installer, libraries: libraries, work: work)
        }
        func substitute(_ s: String) -> String {
            if s.hasPrefix("[") && s.hasSuffix("]"), let rel = Maven.path(String(s.dropFirst().dropLast())) {
                return libraries.appendingPathComponent(rel).path
            }
            var r = s
            for (k, v) in data { r = r.replacingOccurrences(of: "{\(k)}", with: v) }
            return r
        }

        // processors
        let processors = profile["processors"].array.filter { p in
            let sides = p["sides"].array.compactMap(\.string)
            return sides.isEmpty || sides.contains("client")
        }
        if !processors.isEmpty {
            let java = try await JavaManager.select(for: vanilla, job: job)
            for (i, p) in processors.enumerated() {
                try Task.checkCancellation()
                await job.enter(T("运行安装处理器 \(i + 1)/\(processors.count)", "Running processor \(i + 1)/\(processors.count)"), index: 3, of: 5)
                await MainActor.run { job.fileFraction = Double(i) / Double(processors.count) }
                guard let jarCoords = p["jar"].string, let jarRel = Maven.path(jarCoords) else { continue }
                let jar = libraries.appendingPathComponent(jarRel)
                // 输出均已存在且校验正确时跳过
                let outputs = p["outputs"].object.map { (substitute($0.key), substitute($0.value.string ?? "")) }
                if !outputs.isEmpty && outputs.allSatisfy({ path, sha in
                    let sha = sha.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                    return fm.fileExists(atPath: path) && Hash.sha1(file: URL(fileURLWithPath: path)) == sha
                }) { continue }
                guard let mainClass = Zip.mainClass(jar) else {
                    throw LauncherError(T("无法读取处理器 \(jarCoords)", "Couldn't read processor \(jarCoords)"))
                }
                let cp = ([jar] + p["classpath"].array.compactMap { $0.string.flatMap { Maven.path($0) } }.map { libraries.appendingPathComponent($0) })
                    .map(\.path).joined(separator: ":")
                let args = p["args"].array.compactMap(\.string).map(substitute)
                try runProcessor(java: java.path, classpath: cp, mainClass: mainClass, args: args, cwd: work)
            }
        }
        try writeVersionJson(versionJson, name: name, game: game.id, to: targetDir)
    }

    private static func resolveData(_ v: String, installer: URL, libraries: URL, work: URL) throws -> String {
        if v.hasPrefix("[") && v.hasSuffix("]"), let rel = Maven.path(String(v.dropFirst().dropLast())) {
            return libraries.appendingPathComponent(rel).path
        }
        if v.hasPrefix("'") && v.hasSuffix("'") { return String(v.dropFirst().dropLast()) }
        if v.hasPrefix("/") {
            let dest = work.appendingPathComponent(String(v.dropFirst()))
            try Zip.extract(installer, String(v.dropFirst()), to: dest)
            return dest.path
        }
        return v
    }

    private static func runProcessor(java: String, classpath: String, mainClass: String, args: [String], cwd: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: java)
        p.arguments = ["-cp", classpath, mainClass] + args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        log("[Forge] 运行处理器 \(mainClass) \(args.joined(separator: " "))")
        try p.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let text = String(decoding: out, as: UTF8.self)
            log("[Forge] 处理器失败：\(text.suffix(4000))")
            throw LauncherError(T("安装处理器运行失败（\(mainClass)）：", "Processor failed (\(mainClass)): ") + String(text.suffix(600)))
        }
    }
}
