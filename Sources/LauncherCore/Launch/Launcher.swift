import Foundation
import Observation
import CryptoKit

/// 一次运行中的游戏
@MainActor
@Observable
package final class GameProcess: Identifiable {
    package enum State { case starting, running, exited, crashed }
    package let id = UUID()
    package let instanceName: String
    package var lines: [String] = []
    package var state: State = .starting
    package var exitCode: Int32?
    @ObservationIgnored package var process: Process?
    @ObservationIgnored package var logFile: URL?
    @ObservationIgnored private let parser = Log4jParser()

    package init(instanceName: String) { self.instanceName = instanceName }

    package func append(_ text: String) {
        lines.append(contentsOf: parser.feed(text))
        if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
    }

    package func kill() { process?.terminate() }
}

package struct LaunchOptions {
    package var serverIp: String?
    package var demo = false
    /// 仅导出启动脚本
    package var exportScript: URL?
    package init(serverIp: String? = nil, demo: Bool = false, exportScript: URL? = nil) {
        self.serverIp = serverIp; self.demo = demo; self.exportScript = exportScript
    }
}

/// 游戏进程事件，由界面层决定如何响应（隐藏窗口、弹出崩溃提示等）
package struct LaunchCallbacks {
    package var onWindow: @MainActor (GameProcess) -> Void = { _ in }
    package var onExit: @MainActor (GameProcess) -> Void = { _ in }
    package init(onWindow: @escaping @MainActor (GameProcess) -> Void = { _ in }, onExit: @escaping @MainActor (GameProcess) -> Void = { _ in }) {
        self.onWindow = onWindow; self.onExit = onExit
    }
}

package enum Launcher {
    // MARK: 主流程

    /// 启动游戏。返回 nil 表示仅导出了脚本。
    @MainActor
    package static func launch(_ instance: McInstance, account: Account, options: LaunchOptions, job: Job,
                               callbacks: LaunchCallbacks) async throws -> GameProcess? {
        let stages = 5
        job.enter(T("检查版本", "Checking instance"), index: 0, of: stages)
        try precheck(instance, account: account)

        job.enter(T("登录", "Signing in"), index: 1, of: stages)
        let login = try await AccountStore.shared.login(account)

        job.enter(T("准备 Java", "Preparing Java"), index: 2, of: stages)
        let java = try await JavaManager.select(for: instance, job: job)
        log("[Launch] Java：\(java.path)（\(java.version)，\(java.arch)）")

        job.enter(T("检查文件", "Verifying files"), index: 3, of: stages)
        try await Installer.completeFiles(instance, job: job, stageOffset: 3, stageCount: stages + 2, arch: java.arch, quick: true)
        job.enter(T("正在启动", "Launching"), index: 4, of: stages)
        try Task.checkCancellation()

        MetalRenderer.prepareLaunch(instance)
        let ctx = RuleContext(arch: java.arch, demo: options.demo, customResolution: LauncherSettings.shared.windowMode != .fullscreen)
        let libs = instance.libraries(ctx)
        try extractNatives(instance, libs: libs, arch: java.arch)
        let args = try buildArguments(instance, java: java, login: login, libs: libs, ctx: ctx, options: options)
        log("[Launch] 启动参数：\(redact(args.joined(separator: " "), login))")

        if let script = options.exportScript {
            try exportScript(java: java, args: args, cwd: instance.gameDir, to: script)
            return nil
        }
        LauncherSettings.shared.selectedInstance = instance.name
        var setup = instance.setup
        setup.lastPlayed = Date()
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)
        return try run(instance, java: java, args: args, login: login, callbacks: callbacks)
    }

    static func precheck(_ instance: McInstance, account: Account) throws {
        // classpath 以冒号分隔，路径中不能包含冒号；“!” 会破坏 jar URL
        if instance.dir.path.contains("!") || instance.dir.path.contains(":") {
            throw LauncherError(T("游戏路径中不能包含 ! 或 :（\(instance.dir.path)）", "The game path can't contain ! or : (\(instance.dir.path))"))
        }
        if let error = instance.error { throw LauncherError(T("该版本存在问题：\(error)", "This instance is broken: \(error)")) }
        if account.kind == .offline, let e = AccountStore.validateOffline(account.name) { throw LauncherError(e) }
    }

    // MARK: natives

    package static func extractNatives(_ instance: McInstance, libs: [McLibrary], arch: String) throws {
        let fm = FileManager.default
        let dir = instance.nativesDir
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for lib in libs where lib.isNatives || lib.nativeArch == arch {
            guard fm.fileExists(atPath: lib.path.path) else { continue }
            // -j：去掉 jar 内的目录结构（新版 LWJGL 的 natives 位于 macos/arm64/... 下）
            _ = try? Zip.run(["-o", "-q", "-j", lib.path.path, "*.dylib", "*.jnilib", "*.so", "-d", dir.path])
        }
    }

    // MARK: 参数

    package static func memoryMB(_ instance: McInstance) -> Int {
        if let m = instance.setup.memoryGB, m > 0 { return Int(m * 1024) }
        if !LauncherSettings.shared.memoryAuto { return Int(LauncherSettings.shared.memoryGB * 1024) }
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
        // 统一内存由 CPU 与 GPU 共享，需要给图形与系统留出足够空间
        var gb: Double
        if instance.isModded {
            let mods = (try? FileManager.default.contentsOfDirectory(atPath: instance.gameDir.appendingPathComponent("mods").path).count) ?? 0
            gb = min(3 + Double(mods) * 0.025, 10, totalGB * 0.5)
        } else {
            gb = min(4, max(2, totalGB * 0.25))
        }
        return Int(max(1, gb) * 1024)
    }

    package static func split(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        for c in s {
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
                hasToken = true
            } else if c.isWhitespace {
                if hasToken || !current.isEmpty { result.append(current); current = ""; hasToken = false }
            } else {
                current.append(c)
            }
        }
        if hasToken || !current.isEmpty { result.append(current) }
        return result
    }

    private static func collect(_ list: [JSON], _ ctx: RuleContext) -> [String] {
        var out: [String] = []
        for item in list {
            if let s = item.string { out.append(s); continue }
            if item["rules"].exists && !ctx.check(item["rules"]) { continue }
            let v = item["value"]
            if let s = v.string { out.append(s) } else { out += v.array.compactMap(\.string) }
        }
        return out
    }

    /// 针对 Apple 芯片与 Java 版本调优的 JVM 参数（借鉴 Lunar / Badlion 的做法）
    package static func performanceArguments(java: JavaInfo, memoryMB: Int, instance: McInstance, custom: [String], classpath: String = "",
                                             existing: [String] = []) -> [String] {
        var args: [String] = []
        let s = LauncherSettings.shared
        if !custom.contains(where: { $0.hasPrefix("-Xmx") }) {
            args.append("-Xmx\(memoryMB)m")
            // 初始堆设为一半，减少启动阶段的反复扩容
            if !custom.contains(where: { $0.hasPrefix("-Xms") }) { args.append("-Xms\(max(512, memoryMB / 2))m") }
        }
        if !custom.contains(where: { $0.contains("GC") && $0.hasPrefix("-XX:+Use") }) {
            let useZGC = s.gcMode == .zgc && java.major >= 21
            if useZGC {
                args.append("-XX:+UseZGC")
                // Java 21~22 需要显式开启分代 ZGC；23 起默认分代，24 起该参数被移除
                if java.major <= 22 { args.append("-XX:+ZGenerational") }
            } else {
                // Mojang 官方启动器的 G1 参数，并根据堆大小调整区域大小
                args += ["-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions", "-XX:G1NewSizePercent=20", "-XX:G1ReservePercent=20",
                         "-XX:MaxGCPauseMillis=50", "-XX:G1HeapRegionSize=\(memoryMB >= 6144 ? 16 : 8)M", "-XX:+ParallelRefProcEnabled"]
            }
        }
        args.append("-XX:-OmitStackTraceInFastThrow")
        // Java 24+ 默认会对 sun.misc.Unsafe 的内存访问发出警告，LWJGL 与部分 Mod 仍在使用
        if java.major >= 24 && !(custom + existing).contains(where: { $0.hasPrefix("--sun-misc-unsafe-memory-access") }) {
            args.append("--sun-misc-unsafe-memory-access=allow")
        }
        // Java 24+：紧凑对象头，显著降低堆内存占用（25 起为正式功能）
        if s.compactHeaders && java.major >= 25 { args.append("-XX:+UseCompactObjectHeaders") }
        else if s.compactHeaders && java.major == 24 { args += ["-XX:+UnlockExperimentalVMOptions", "-XX:+UseCompactObjectHeaders"] }
        // Java agent（如 authlib-injector）与动态 CDS / AOT 缓存的生成不兼容
        let hasAgent = (existing + custom).contains { $0.hasPrefix("-javaagent:") }
        if s.classDataSharing && java.hasBaseCDS && !hasAgent {
            let dir = instance.dir.appendingPathComponent(".kiln", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if java.major >= 25 && !args.contains("-XX:+UseZGC") {
                // Java 25+：AOT 缓存（JEP 483/514/515）。首次运行记录类加载与方法分析，退出时写入缓存，之后的启动直接复用。
                // 缓存与 classpath、Java 版本和 JVM 参数绑定，变化后换用新文件。
                let key = SHA256.hash(data: Data((java.path + java.version + classpath + args.joined(separator: " ")).utf8))
                    .prefix(6).map { String(format: "%02x", $0) }.joined()
                let aot = dir.appendingPathComponent("aot-\(key).aot")
                if FileManager.default.fileExists(atPath: aot.path) {
                    args.append("-XX:AOTCache=\(aot.path)")
                } else {
                    // 清理过期的缓存
                    for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                    where f.lastPathComponent.hasPrefix("aot-") { try? FileManager.default.removeItem(at: f) }
                    args.append("-XX:AOTCacheOutput=\(aot.path)")
                }
            } else if java.major >= 19 {
                // Java 19~24：动态 CDS 归档，自动生成并在 classpath 变化时重建
                let jsa = dir.appendingPathComponent("cds-\(java.major)-\(java.arch).jsa")
                args += ["-XX:+AutoCreateSharedArchive", "-XX:SharedArchiveFile=\(jsa.path)"]
            }
        }
        return args
    }

    package static func buildArguments(_ instance: McInstance, java: JavaInfo, login: LoginResult, libs: [McLibrary],
                                       ctx: RuleContext, options: LaunchOptions) throws -> [String] {
        let json = instance.json
        let s = LauncherSettings.shared
        let setup = instance.setup
        let folder = instance.folder
        let assets = folder.appendingPathComponent("assets")
        var jvm: [String] = []

        // macOS 程序坞名称与图标
        jvm.append("-Xdock:name=Minecraft \(instance.vanillaVersion)")
        if let icon = dockIcon(instance) { jvm.append("-Xdock:icon=\(icon.path)") }

        if json["arguments"]["jvm"].exists {
            jvm += collect(json["arguments"]["jvm"].array, ctx)
        } else {
            jvm += ["-Djava.library.path=${natives_directory}", "-cp", "${classpath}"]
        }
        let custom = split(setup.jvmArgs.flatMap { $0.isEmpty ? nil : $0 } ?? s.jvmArgs)
        let classpathKey = libs.map(\.path.path).joined(separator: ":")
        jvm += performanceArguments(java: java, memoryMB: memoryMB(instance), instance: instance, custom: custom, classpath: classpathKey, existing: jvm + login.jvmArgs)
        jvm += ["-Dfml.ignoreInvalidMinecraftCertificates=true", "-Dfml.ignorePatchDiscrepancies=true",
                "-Dlog4j2.formatMsgNoLookups=true", "-Dorg.lwjgl.librarypath=${natives_directory}"]
        if let logArg = json["logging"]["client"]["argument"].string, let id = json["logging"]["client"]["file"]["id"].string {
            let path = assets.appendingPathComponent("log_configs/\(id)")
            if FileManager.default.fileExists(atPath: path.path) {
                jvm.append(logArg.replacingOccurrences(of: "${path}", with: path.path))
            }
        }
        // 外置登录 / 离线皮肤：authlib-injector
        jvm += login.jvmArgs
        jvm += custom
        guard let mainClass = json["mainClass"].string else {
            throw LauncherError(T("版本 JSON 中缺少 mainClass", "mainClass is missing from the version JSON"))
        }

        var game: [String] = []
        if let old = json["minecraftArguments"].string, !old.isEmpty {
            game += old.split(separator: " ").map(String.init)
            if s.windowMode != .fullscreen && !game.contains("--width") {
                game += ["--width", "${resolution_width}", "--height", "${resolution_height}"]
            }
        }
        if json["arguments"]["game"].exists {
            game += collect(json["arguments"]["game"].array, ctx)
        }
        // 自定义信息：为空时移除 --versionType
        let info = setup.customInfo.flatMap { $0.isEmpty ? nil : $0 } ?? s.customInfo
        if info.isEmpty, let i = game.firstIndex(of: "--versionType") {
            game.remove(at: i)
            if i < game.count { game.remove(at: i) }
        }
        if s.windowMode == .fullscreen { game.append("--fullscreen") }
        if options.demo && !game.contains("--demo") { game.append("--demo") }
        let server = options.serverIp ?? setup.serverEnter ?? ""
        if !server.isEmpty {
            if instance.releaseTime > ISO8601DateFormatter().date(from: "2023-04-04T00:00:00Z")! {
                game += ["--quickPlayMultiplayer", server]
            } else {
                let parts = server.split(separator: ":")
                game += ["--server", String(parts[0]), "--port", parts.count > 1 ? String(parts[1]) : "25565"]
            }
        }
        game += split(setup.gameArgs.flatMap { $0.isEmpty ? nil : $0 } ?? s.gameArgs)

        var cp = libs.filter { !$0.isNatives && FileManager.default.fileExists(atPath: $0.path.path) }.map(\.path.path)
        // 1.13 ~ 1.18 的 arm64 原生模式：使用修补过窗口图标调用的 lwjgl-glfw
        if ctx.arch == "arm64" && instance.lwjglNeedsArm64Patch && s.arm64Native,
           let i = cp.firstIndex(where: { $0.hasSuffix("/lwjgl-glfw-\(Lwjgl.arm64Version).jar") }),
           let fixed = GLFWPatch.patchedJar(for: URL(fileURLWithPath: cp[i])) {
            cp[i] = fixed.path
        }
        let jar = instance.clientJar.path
        if FileManager.default.fileExists(atPath: jar) { cp.append(jar) }
        var size = (854, 480)
        if s.windowMode == .custom { size = (max(100, s.windowWidth), max(100, s.windowHeight)) }

        let replace: [String: String] = [
            "${classpath_separator}": ":",
            "${natives_directory}": instance.nativesDir.path,
            "${library_directory}": folder.appendingPathComponent("libraries").path,
            "${libraries_directory}": folder.appendingPathComponent("libraries").path,
            "${launcher_name}": AppInfo.shortName,
            "${launcher_version}": AppInfo.version,
            "${version_name}": instance.name,
            "${game_directory}": instance.gameDir.path,
            "${assets_root}": assets.path,
            "${game_assets}": assets.appendingPathComponent("virtual/\(instance.assetIndexId)").path,
            "${assets_index_name}": instance.assetIndexId,
            "${user_properties}": "{}",
            "${auth_player_name}": login.name,
            "${auth_uuid}": login.uuid,
            "${auth_access_token}": login.accessToken,
            "${access_token}": login.accessToken,
            "${auth_session}": login.accessToken,
            "${auth_xuid}": login.xuid,
            "${clientid}": "",
            "${user_type}": login.userType,
            "${version_type}": info.isEmpty ? AppInfo.shortName : info,
            "${resolution_width}": String(size.0),
            "${resolution_height}": String(size.1),
            "${primary_jar}": jar,
            "${classpath}": cp.joined(separator: ":"),
        ]
        func apply(_ a: String) -> String {
            guard a.contains("${") else { return a }
            var r = a
            for (k, v) in replace where r.contains(k) { r = r.replacingOccurrences(of: k, with: v) }
            return r
        }
        return jvm.map(apply) + [mainClass] + game.map(apply)
    }

    /// 从资源文件中找到 Minecraft 的 .icns 图标
    static func dockIcon(_ instance: McInstance) -> URL? {
        let indexFile = instance.folder.appendingPathComponent("assets/indexes/\(instance.assetIndexId).json")
        guard let data = try? Data(contentsOf: indexFile), let j = try? JSON(data: data) else { return nil }
        for key in ["icons/minecraft.icns", "minecraft/icons/minecraft.icns"] {
            if let hash = j["objects"][key]["hash"].string {
                let u = instance.folder.appendingPathComponent("assets/objects/\(hash.prefix(2))/\(hash)")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    static func redact(_ s: String, _ login: LoginResult) -> String {
        login.userType == "legacy" ? s : s.replacingOccurrences(of: login.accessToken, with: "********")
    }

    static func exportScript(java: JavaInfo, args: [String], cwd: URL, to url: URL) throws {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let text = "#!/bin/bash\n# Generated by \(AppInfo.shortName)\ncd \(q(cwd.path))\n\(q(java.path)) \(args.map(q).joined(separator: " "))\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: 运行

    @MainActor
    static func run(_ instance: McInstance, java: JavaInfo, args: [String], login: LoginResult, callbacks: LaunchCallbacks) throws -> GameProcess {
        let game = GameProcess(instanceName: instance.name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: java.path)
        p.arguments = args
        // 高 QoS：在 Apple 芯片上优先调度到性能核
        p.qualityOfService = .userInteractive
        try FileManager.default.createDirectory(at: instance.gameDir, withIntermediateDirectories: true)
        p.currentDirectoryURL = instance.gameDir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let logURL = Paths.logs.appendingPathComponent("LatestLaunch.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        game.logFile = logURL
        let redactToken = login.userType == "legacy" ? nil : login.accessToken

        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            var text = String(decoding: data, as: UTF8.self)
            if let t = redactToken { text = text.replacingOccurrences(of: t, with: "********") }
            logHandle?.write(Data(text.utf8))
            Task { @MainActor in
                game.append(text)
                if game.state == .starting && windowAppeared(text) {
                    game.state = .running
                    callbacks.onWindow(game)
                }
            }
        }
        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            try? logHandle?.close()
            let code = proc.terminationStatus
            let killed = proc.terminationReason == .uncaughtSignal && (code == 15 || code == 9)
            Task { @MainActor in
                game.exitCode = code
                game.state = code == 0 || killed ? .exited : .crashed
                log("[Launch] 游戏已退出，返回值 \(code)")
                callbacks.onExit(game)
            }
        }
        try p.run()
        game.process = p
        // 部分版本没有可识别的日志，20 秒后视为已启动
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if game.state == .starting { game.state = .running; callbacks.onWindow(game) }
        }
        return game
    }

    package static func windowAppeared(_ text: String) -> Bool {
        ["Setting user:", "LWJGL Version", "Backend library:", "OpenAL initialized", "Sound engine started", "Narrator library"]
            .contains { text.contains($0) }
    }
}

/// 将 log4j 的 XML 日志（版本 JSON 中 logging 配置的格式）转换为普通文本行
package final class Log4jParser {
    private var buffer = ""
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    package init() {}

    package func feed(_ text: String) -> [String] {
        buffer += text
        var out: [String] = []
        while true {
            if let start = buffer.range(of: "<log4j:Event") {
                // 事件之前的普通文本
                let before = buffer[..<start.lowerBound]
                out += plainLines(String(before))
                guard let end = buffer.range(of: "</log4j:Event>", range: start.upperBound..<buffer.endIndex) else {
                    buffer = String(buffer[start.lowerBound...])
                    return out
                }
                out.append(format(String(buffer[start.lowerBound..<end.upperBound])))
                buffer = String(buffer[end.upperBound...])
            } else {
                // 没有 XML 事件：保留最后不完整的一行
                guard let lastNewline = buffer.lastIndex(of: "\n") else {
                    if buffer.count > 8192 { out += plainLines(buffer); buffer = "" }
                    return out
                }
                out += plainLines(String(buffer[...lastNewline]))
                buffer = String(buffer[buffer.index(after: lastNewline)...])
                return out
            }
        }
    }

    private func plainLines(_ s: String) -> [String] {
        s.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func attr(_ xml: String, _ name: String) -> String? {
        guard let r = xml.range(of: "\(name)=\"") else { return nil }
        let rest = xml[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private func format(_ xml: String) -> String {
        let level = attr(xml, "level") ?? "INFO"
        let thread = attr(xml, "thread") ?? "main"
        var time = ""
        if let ts = attr(xml, "timestamp"), let ms = Double(ts) { time = formatter.string(from: Date(timeIntervalSince1970: ms / 1000)) }
        var message = ""
        if let a = xml.range(of: "<![CDATA["), let b = xml.range(of: "]]>", range: a.upperBound..<xml.endIndex) {
            message = String(xml[a.upperBound..<b.lowerBound])
        }
        if let a = xml.range(of: "<log4j:Throwable><![CDATA["), let b = xml.range(of: "]]>", range: a.upperBound..<xml.endIndex) {
            message += "\n" + xml[a.upperBound..<b.lowerBound]
        }
        return "[\(time)] [\(thread)/\(level)]: \(message)"
    }
}
