import Foundation

package struct JavaInfo: Identifiable, Hashable, Sendable {
    /// bin/java 的路径
    package let path: String
    package let version: String
    package let major: Int
    /// "arm64" 或 "x86_64"
    package let arch: String
    package let isMojang: Bool
    package var id: String { path }

    package var home: String { URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path }

    /// 是否带有基础 CDS 归档（动态 CDS / AOT 缓存依赖它；Mojang 的运行时默认没有）
    package var hasBaseCDS: Bool {
        ["lib/server/classes.jsa", "lib/server/classes_nocoops.jsa", "jre/lib/server/classes.jsa"].contains {
            FileManager.default.fileExists(atPath: home + "/" + $0)
        }
    }

    package var displayName: String {
        let kind = path.contains("/zulu-") ? "Zulu" : (isMojang ? "Mojang" : "Java")
        let a = arch == "arm64" ? "Apple Silicon" : "Intel"
        return "\(kind) \(version) (\(a))"
    }

    /// 与原版类似的兼容性判定
    package func compatible(with need: Int) -> Bool {
        if need <= 8 { return major == 8 }
        return major >= need
    }
}

package enum JavaManager {
    // MARK: 搜索

    package static func searchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines"),
            home.appendingPathComponent("Library/Java/JavaVirtualMachines"),
            URL(fileURLWithPath: "/opt/homebrew/opt"),
            URL(fileURLWithPath: "/usr/local/opt"),
            URL(fileURLWithPath: "/opt/homebrew/Cellar"),
            URL(fileURLWithPath: "/usr/local/Cellar"),
            home.appendingPathComponent(".sdkman/candidates/java"),
            home.appendingPathComponent(".jdks"),
            home.appendingPathComponent(".gradle/jdks"),
            Paths.runtime,
            Paths.defaultMinecraft.appendingPathComponent("runtime"),
            URL(fileURLWithPath: LauncherSettings.shared.minecraftFolder).appendingPathComponent("runtime"),
        ]
    }

    /// 在目录树中查找 bin/java（限制深度，避免过慢）
    package static func findJavaBinaries(in root: URL, depth: Int = 6) -> [String] {
        let fm = FileManager.default
        var result: [String] = []
        func walk(_ url: URL, _ d: Int) {
            let java = url.appendingPathComponent("bin/java")
            if fm.isExecutableFile(atPath: java.path) {
                result.append(java.resolvingSymlinksInPath().path)
                return
            }
            guard d > 0, let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let n = item.lastPathComponent
                // 跳过明显无关的大目录
                if root.path.contains("Cellar") || root.path.hasSuffix("/opt") {
                    if !(n.contains("openjdk") || n.contains("java") || n.contains("jdk") || n.contains("temurin") || n.contains("zulu")
                         || n == "libexec" || n.hasSuffix(".jdk") || n == "Contents" || n == "Home" || n.first?.isNumber == true) { continue }
                }
                if ["legal", "lib", "include", "man", "jmods", "conf"].contains(n) { continue }
                walk(item, d - 1)
            }
        }
        walk(root, depth)
        return result
    }

    package static func search() async -> [JavaInfo] {
        await Task.detached(priority: .userInitiated) {
            var paths: [String] = []
            for root in searchRoots() { paths += findJavaBinaries(in: root) }
            paths += LauncherSettings.shared.customJavas
            if let env = ProcessInfo.processInfo.environment["JAVA_HOME"] { paths.append(env + "/bin/java") }
            var seen = Set<String>()
            var result: [JavaInfo] = []
            for p in paths {
                let real = URL(fileURLWithPath: p).resolvingSymlinksInPath().path
                guard seen.insert(real).inserted, let info = inspect(real) else { continue }
                result.append(info)
            }
            return result.sorted { a, b in a.major != b.major ? a.major > b.major : a.version > b.version }
        }.value
    }

    /// 读取 Java 的版本与架构：优先读 release 文件，否则执行 java -XshowSettings
    package static func inspect(_ path: String) -> JavaInfo? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let isMojang = path.hasPrefix(Paths.runtime.path) || path.contains("/minecraft/runtime/")
        let home = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
        if let text = try? String(contentsOf: home.appendingPathComponent("release"), encoding: .utf8) {
            var props: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { props[kv[0]] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            if let v = props["JAVA_VERSION"], let a = props["OS_ARCH"] {
                return JavaInfo(path: path, version: v, major: majorOf(v), arch: normalizeArch(a), isMojang: isMojang)
            }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-XshowSettings:properties", "-version"]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        func prop(_ k: String) -> String? {
            for line in out.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(k + " = ") { return String(t.dropFirst(k.count + 3)) }
            }
            return nil
        }
        guard let v = prop("java.version"), let a = prop("os.arch") else { return nil }
        return JavaInfo(path: path, version: v, major: majorOf(v), arch: normalizeArch(a), isMojang: isMojang)
    }

    package static func majorOf(_ v: String) -> Int {
        let parts = v.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = parts.first else { return 0 }
        return first == 1 && parts.count > 1 ? parts[1] : first
    }

    package static func normalizeArch(_ a: String) -> String {
        ["aarch64", "arm64"].contains(a.lowercased()) ? "arm64" : "x86_64"
    }

    // MARK: 选择

    /// 选择合适的 Java；若没有则自动下载 Mojang 提供的 Java 运行时。
    /// 在 Apple 芯片上优先选择 arm64 原生 Java，只有无法原生运行的版本才使用 Rosetta 2。
    package static func select(for instance: McInstance, job: Job?) async throws -> JavaInfo {
        let need = instance.javaMajor
        // 版本独立设置或全局设置中手动指定的 Java
        let manual = instance.setup.javaPath ?? LauncherSettings.shared.javaPath
        if !manual.isEmpty, let info = inspect(manual) {
            if info.arch == "arm64" && !instance.canRunNativelyOnArm {
                log("[Java] 手动指定了 arm64 Java，但该版本只能通过 Rosetta 2 运行，可能无法启动")
            }
            return info
        }
        let all = await search()
        func rank(_ list: [JavaInfo]) -> [JavaInfo] {
            list.sorted { a, b in
                let ea = a.compatible(with: need), eb = b.compatible(with: need)
                if ea != eb { return ea }
                let da = a.major - need, db = b.major - need
                if da != db { return da < db }
                return a.isMojang && !b.isMojang
            }
        }
        var arch = instance.preferredArch
        if arch == "arm64" {
            if let best = rank(all.filter { $0.arch == "arm64" && instance.acceptsJava($0) }).first {
                log("[Java] 原生 arm64：\(best.path)（\(best.version)）")
                return prepared(best)
            }
            // 没有合适的 arm64 Java：能下载就下载 arm64 运行时
            do {
                if let component = arm64Component(for: instance) {
                    await MainActor.run { job?.stage = T("正在下载 Java（\(component)）", "Downloading Java (\(component))") }
                    return prepared(try await downloadRuntime(component: component, arch: "arm64", job: job))
                }
                // Mojang 不提供 arm64 的 Java 8：改用 Azul Zulu 8（arm64）
                await MainActor.run { job?.stage = T("正在下载 Java 8（Apple 芯片）", "Downloading Java 8 (Apple Silicon)") }
                return prepared(try await downloadZulu(major: 8, job: job))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log("[Java] 下载 arm64 Java 失败（\(error.friendly)），改用 Rosetta 2")
                arch = "x86_64"
            }
        }
        if arch == "x86_64" && Arch.isAppleSilicon && !Arch.rosettaInstalled {
            throw LauncherError(T("该版本需要 Rosetta 2。请在终端中执行：softwareupdate --install-rosetta --agree-to-license", "This version needs Rosetta 2. Run in Terminal: softwareupdate --install-rosetta --agree-to-license"))
        }
        if let best = rank(all.filter { $0.arch == arch && $0.compatible(with: need) }).first {
            log("[Java] 选择 \(best.path)（\(best.version)，\(best.arch)）")
            return prepared(best)
        }
        log("[Java] 没有可用的 Java（需要 \(need)，\(arch)），开始下载 \(instance.javaComponent)")
        await MainActor.run { job?.stage = T("正在下载 Java（\(instance.javaComponent)）", "Downloading Java (\(instance.javaComponent))") }
        return prepared(try await downloadRuntime(component: instance.javaComponent, arch: arch, job: job))
    }

    /// 为启动器管理的运行时生成基础 CDS 归档（Mojang 与 Zulu 的运行时默认没有），使类数据共享与 AOT 缓存生效
    static func prepared(_ java: JavaInfo) -> JavaInfo {
        guard !java.hasBaseCDS, java.major >= 11, java.path.hasPrefix(Paths.runtime.path) else { return java }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: java.path)
        p.arguments = ["-Xshare:dump"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let start = Date()
        if (try? p.run()) != nil {
            p.waitUntilExit()
            log("[Java] 已生成基础 CDS 归档（\(String(format: "%.1f", Date().timeIntervalSince(start))) 秒）：\(java.hasBaseCDS)")
        }
        return java
    }

    // MARK: Azul Zulu（Apple 芯片上的 Java 8）

    static func downloadZulu(major: Int, job: Job?) async throws -> JavaInfo {
        let api = "https://api.azul.com/metadata/v1/zulu/packages/?java_version=\(major)&os=macos&arch=aarch64&archive_type=tar.gz&java_package_type=jre&javafx_bundled=false&latest=true&release_status=ga&availability_types=CA&page_size=1"
        let list = try await Net.json(urls: [api])
        guard let url = list[0]["download_url"].string, let name = list[0]["name"].string else {
            throw LauncherError(T("无法获取 Java \(major) 的下载地址", "Couldn't find a download for Java \(major)"))
        }
        let root = Paths.runtime.appendingPathComponent("zulu-\(major)/mac-os-arm64", isDirectory: true)
        if let bin = findJavaBinaries(in: root).first, let info = inspect(bin) { return info }
        let archive = Paths.cache.appendingPathComponent(name)
        await MainActor.run { job?.stage = T("下载 Java \(major)（Azul Zulu）", "Downloading Java \(major) (Azul Zulu)") }
        try await Downloader.run([DownloadItem(url: url, destination: archive)], job: job)
        defer { try? FileManager.default.removeItem(at: archive) }
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", root.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0, let bin = findJavaBinaries(in: root, depth: 8).first, let info = inspect(bin) else {
            throw LauncherError(T("Java \(major) 解压失败", "Failed to extract Java \(major)"))
        }
        return info
    }

    /// Apple 芯片上可下载的 Mojang arm64 运行时组件
    package static func arm64Component(for instance: McInstance) -> String? {
        let c = instance.javaComponent
        // Mojang 不提供 arm64 的 jre-legacy（Java 8）
        if c == "jre-legacy" {
            return instance.needsStrictJava8 || instance.isLwjgl2 ? nil : "java-runtime-gamma"
        }
        // java-runtime-alpha（Java 16）在 arm64 上同样缺失，Java 17 可以兼容
        if c == "java-runtime-alpha" { return "java-runtime-gamma" }
        return c
    }

    // MARK: 下载 Mojang Java 运行时

    package static let runtimeIndex = "https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"

    package static func platformKey(_ arch: String) -> String { arch == "arm64" ? "mac-os-arm64" : "mac-os" }

    package static func downloadRuntime(component: String, arch: String, job: Job?) async throws -> JavaInfo {
        let index = try await Net.json(runtimeIndex, kind: .file)
        var platform = platformKey(arch)
        var entry = index[platform][component][0]
        if !entry.exists && arch == "arm64" && component != "jre-legacy" {
            // Apple 芯片上没有该组件时，退回 x86_64 版本（通过 Rosetta 2 运行）
            platform = platformKey("x86_64")
            entry = index[platform][component][0]
        }
        guard let manifestURL = entry["manifest"]["url"].string else {
            throw LauncherError(T("Mojang 未提供适用于此 Mac 的 Java 运行时 \(component)", "Mojang does not provide Java runtime \(component) for this Mac"))
        }
        let manifest = try await Net.json(manifestURL, kind: .file)
        let root = Paths.runtime.appendingPathComponent("\(component)/\(platform)", isDirectory: true)
        let fm = FileManager.default
        var items: [DownloadItem] = []
        var executables: [URL] = []
        var links: [(URL, String)] = []
        for (rel, f) in manifest["files"].object {
            let dest = root.appendingPathComponent(rel)
            switch f["type"].string {
            case "directory":
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            case "link":
                if let target = f["target"].string { links.append((dest, target)) }
            default:
                let raw = f["downloads"]["raw"]
                guard let url = raw["url"].string else { continue }
                items.append(DownloadItem(url: url, destination: dest, sha1: raw["sha1"].string,
                                          size: raw["size"].double.map { Int64($0) }))
                if f["executable"].bool == true { executables.append(dest) }
            }
        }
        await MainActor.run { job?.stage = T("下载 Java \(component)", "Download Java \(component)") }
        try await Downloader.run(items, job: job)
        for (dest, target) in links {
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try? fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
        }
        for e in executables { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: e.path) }
        // 去除隔离属性，防止 Gatekeeper 拦截
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", root.path]
        try? xattr.run()
        xattr.waitUntilExit()
        guard let bin = findJavaBinaries(in: root).first, let info = inspect(bin) else {
            throw LauncherError(T("Mojang 未提供适用于此 Mac 的 Java 运行时 \(component)", "Mojang does not provide Java runtime \(component) for this Mac"))
        }
        return info
    }
}
