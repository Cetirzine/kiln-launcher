import Foundation
import LauncherCore

/// 不依赖 XCTest 的自检（命令行工具链不带 XCTest / Swift Testing 的宏插件）
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func expect(_ ok: Bool, _ name: String) {
        print(ok ? "  ✔ \(name)" : "  ✘ \(name)")
        if !ok { failures += 1 }
    }

    static func runUnit() -> Bool {
        print("\(AppInfo.shortName) 自检")
        expect(Account.offlineUUID("Notch") == "b50ad385829d3141a2167e7d7539ba7f", "离线 UUID 与原版服务端一致")
        let old = Localizer.shared.language
        Localizer.shared.language = .zhHant
        expect(T("启动游戏", "Play") == "啟動遊戲" && T("设置内存", "") == "設定記憶體", "繁体中文自动转换")
        Localizer.shared.language = .en
        expect(T("启动游戏", "Play") == "Play", "英文")
        Localizer.shared.language = old
        expect(Maven.path("org.lwjgl:lwjgl:3.3.1:natives-macos-arm64") == "org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-macos-arm64.jar", "Maven 路径（classifier）")
        expect(Maven.path("a.b:c:1@zip") == "a/b/c/1/c-1.zip", "Maven 路径（扩展名）")
        let rules = try! JSON(data: Data(#"[{"action":"allow"},{"action":"disallow","os":{"name":"osx"}}]"#.utf8))
        expect(!RuleContext().check(rules), "规则：禁止 osx")
        let arm = try! JSON(data: Data(#"[{"action":"allow","os":{"name":"osx","arch":"arm64"}}]"#.utf8))
        expect(RuleContext(arch: "arm64").check(arm) && !RuleContext(arch: "x86_64").check(arm), "规则：架构")
        let demo = try! JSON(data: Data(#"[{"action":"allow","features":{"is_demo_user":true}}]"#.utf8))
        expect(!RuleContext().check(demo) && RuleContext(demo: true).check(demo), "规则：试玩特性")
        expect(Launcher.split(#"-Xmx2G "-Dfoo=a b" ''"#) == ["-Xmx2G", "-Dfoo=a b", ""], "参数分割")
        let libs = Lwjgl.arm64Replacement("org.lwjgl:lwjgl-glfw:3.2.2", libDir: URL(fileURLWithPath: "/tmp"))!
        expect(libs.map(\.name) == ["org.lwjgl:lwjgl-glfw:3.3.1", "org.lwjgl:lwjgl-glfw:3.3.1:natives-macos-arm64"], "LWJGL arm64 替换")
        expect(Lwjgl.arm64Replacement("org.lwjgl.lwjgl:lwjgl:2.9.4", libDir: URL(fileURLWithPath: "/tmp")) == nil, "LWJGL 2 不替换")
        expect(ForgeInstaller.neoForgeGameVersion("21.1.77") == "1.21.1", "NeoForge → 1.21.1")
        expect(ForgeInstaller.neoForgeGameVersion("20.4.237") == "1.20.4", "NeoForge → 1.20.4")
        expect(ForgeInstaller.neoForgeGameVersion("21.0.167") == "1.21", "NeoForge → 1.21")
        expect(ForgeInstaller.neoForgeGameVersion("26.3.0.65-beta") == "26.3", "NeoForge → 26.3")
        let parser = Log4jParser()
        let xml = #"<log4j:Event logger="x" timestamp="0" level="WARN" thread="Render thread"><log4j:Message><![CDATA[Hello]]></log4j:Message></log4j:Event>"#
        let lines = parser.feed(String(xml.prefix(40))) + parser.feed(String(xml.dropFirst(40)) + "\nplain line\n")
        expect(lines.count == 2 && lines[0].hasSuffix("[Render thread/WARN]: Hello") && lines[1] == "plain line", "log4j XML 日志解析（分段输入）")
        // 若当前游戏目录中已有 LWJGL 3.3.1，则验证窗口图标补丁
        let glfw = LauncherSettings.shared.minecraftURL.appendingPathComponent("libraries/org/lwjgl/lwjgl-glfw/3.3.1/lwjgl-glfw-3.3.1.jar")
        if FileManager.default.fileExists(atPath: glfw.path), let d = Zip.read(glfw, "org/lwjgl/glfw/GLFW.class") {
            expect(GLFWPatch.patchClass(d) != nil, "GLFW 窗口图标补丁")
        }
        let crash = CrashAnalyzer.analyze(["Exception in thread \"main\" java.lang.UnsupportedClassVersionError: foo"])
        expect(crash != nil, "崩溃分析：Java 版本")
        // 文件监视：版本目录的变化会触发刷新，资源文件的变化被忽略
        expect(FolderWatcher.isRelevant("/mc/versions/1.21/1.21.json") && FolderWatcher.isRelevant("/mc/versions/1.21/mods/a.jar")
               && !FolderWatcher.isRelevant("/mc/assets/objects/ab/abcd") && !FolderWatcher.isRelevant("/mc/versions/1.21/1.21-natives/x.dylib"),
               "文件监视的路径过滤")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-watch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp.appendingPathComponent("versions"), withIntermediateDirectories: true)
        var fired = 0
        let watcher = FolderWatcher { fired += 1 }
        watcher.watch(tmp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        try? FileManager.default.createDirectory(at: tmp.appendingPathComponent("versions/test"), withIntermediateDirectories: true)
        let deadline = Date().addingTimeInterval(5)
        while fired == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        watcher.stop()
        try? FileManager.default.removeItem(at: tmp)
        expect(fired > 0, "文件监视：新建版本文件夹后自动刷新")
        print(failures == 0 ? "全部通过" : "\(failures) 项失败")
        return failures == 0
    }

    /// 安装指定版本（可附带加载器）到目录中，并真正启动游戏，等待游戏窗口出现后结束进程
    nonisolated static func runLaunch(version: String, folder: URL, loader: String?) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        Task { @MainActor in
            defer { sem.signal() }
            do {
                // 测试结束后恢复原来的游戏目录
                let previousFolder = LauncherSettings.shared.minecraftFolder
                let previousSelection = LauncherSettings.shared.selectedInstance
                defer {
                    LauncherSettings.shared.minecraftFolder = previousFolder
                    LauncherSettings.shared.selectedInstance = previousSelection
                }
                LauncherSettings.shared.minecraftFolder = folder.path
                let name = "\(version)-\(loader?.lowercased() ?? "vanilla")-test"
                let instanceDir = folder.appendingPathComponent("versions/\(name)")
                if !FileManager.default.fileExists(atPath: instanceDir.appendingPathComponent("\(name).json").path) {
                    try? FileManager.default.removeItem(at: instanceDir)
                    print("安装 \(version) \(loader ?? "")…")
                    let remote = try await VersionManifest.find(version)
                    let job = Job(title: "install")
                    switch loader {
                    case "Forge", "NeoForge", "ForgePlus":
                        let kind = ForgeKind(rawValue: loader == "ForgePlus" ? "Forge" : loader!)!
                        let list = try await ForgeInstaller.versions(kind, game: version)
                        guard let v = list.first(where: { !$0.isBeta }) ?? list.first else { throw LauncherError("没有 \(kind.rawValue) 版本") }
                        print("\(kind.rawValue) \(v.version)")
                        try await ForgeInstaller.install(kind, version: v.version, game: remote, name: name, folder: folder, job: job)
                    case "Fabric", "Quilt", "FabricMetal":
                        let kind = ModLoaderKind(rawValue: loader == "FabricMetal" ? "Fabric" : loader!)!
                        let list = try await kind.versions(for: version)
                        let lv = list.first { $0.stable } ?? list.first!
                        try await Installer.install(version: remote, name: name, loader: (kind, lv.version), folder: folder, job: job)
                    default:
                        try await Installer.install(version: remote, name: name, loader: nil, folder: folder, job: job)
                    }
                }
                let instance = McInstance(folder: folder, name: name)
                if loader == "ForgePlus" {
                    let mods = instance.gameDir.appendingPathComponent("mods")
                    if let of = try await OptiFine.versions(game: version).first(where: { !$0.isPreview }) {
                        try await OptiFine.install(of, into: mods, job: nil)
                        print("已安装 OptiFine \(of.display)（\(of.forge ?? "")）")
                    }
                    if let ll = try await LiteLoader.versions(game: version).first {
                        try await LiteLoader.install(ll, into: mods, job: nil)
                        print("已安装 LiteLoader \(ll.version)")
                    }
                    print("mods：\((try? FileManager.default.contentsOfDirectory(atPath: mods.path))?.sorted().joined(separator: ", ") ?? "")")
                }
                if loader == "FabricMetal" && !MetalRenderer.isEnabled(instance) {
                    try await MetalRenderer.enable(instance, job: nil)
                    print("已启用 Metal 渲染：\(MetalRenderer.installedJar(instance)?.lastPathComponent ?? "?")")
                }
                print("版本：\(instance.description)，LWJGL \(instance.lwjglVersion ?? "?")，预期架构 \(instance.preferredArch)")
                let job = Job(title: "launch")
                let account = Account(kind: .offline, name: "KilnTest", uuid: Account.offlineUUID("KilnTest"))
                let java = try await JavaManager.select(for: instance, job: job)
                print("Java：\(java.displayName) \(java.path)")
                try await Installer.completeFiles(instance, job: job, arch: java.arch, quick: true)
                MetalRenderer.prepareLaunch(instance)
                let ctx = RuleContext(arch: java.arch)
                let libs = instance.libraries(ctx)
                try Launcher.extractNatives(instance, libs: libs, arch: java.arch)
                let login = LoginResult(name: account.name, uuid: account.uuid, accessToken: account.uuid, userType: "legacy")
                let args = try Launcher.buildArguments(instance, java: java, login: login, libs: libs, ctx: ctx, options: LaunchOptions())
                print("JVM 性能参数：\(args.filter { $0.hasPrefix("-XX:") || $0.hasPrefix("-Xm") || $0.hasPrefix("--sun") }.joined(separator: " "))")
                let p = Process()
                p.executableURL = URL(fileURLWithPath: java.path)
                p.arguments = args
                p.currentDirectoryURL = instance.gameDir
                p.qualityOfService = .userInteractive
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                let start = Date()
                try p.run()
                print("游戏进程已启动（pid \(p.processIdentifier)），等待窗口…")
                let parser = Log4jParser()
                var output: [String] = []
                let handle = pipe.fileHandleForReading
                while Date().timeIntervalSince(start) < 180 && p.isRunning {
                    let data = handle.availableData
                    if data.isEmpty { try await Task.sleep(nanoseconds: 200_000_000); continue }
                    let text = String(decoding: data, as: UTF8.self)
                    output += parser.feed(text)
                    let joined = output.suffix(80).joined(separator: "\n")
                    if joined.contains("Sound engine started") || joined.contains("OpenAL initialized") || joined.contains("Initializing LWJGL OpenAL") || joined.contains("Created: ") {
                        ok = true
                        break
                    }
                }
                print(String(format: "用时 %.1f 秒", Date().timeIntervalSince(start)))
                if p.isRunning {
                    p.terminate()
                    // 等待正常退出（AOT 缓存在退出时写入）
                    let deadline = Date().addingTimeInterval(60)
                    while p.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 200_000_000) }
                }
                // 读取剩余输出（包括退出阶段 JVM 打印的信息）
                output += parser.feed(String(decoding: handle.readDataToEndOfFile(), as: UTF8.self) + "\n")
                try? output.joined(separator: "\n").write(to: Paths.logs.appendingPathComponent("LaunchTest.log"), atomically: true, encoding: .utf8)
                print(output.suffix(12).joined(separator: "\n"))
                print(ok ? "✔ 启动成功" : "✘ 启动失败（退出码 \(p.isRunning ? -1 : p.terminationStatus)）")
            } catch {
                print("✘ 错误：\(error.friendly)")
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return ok
    }
}

/// `--download-bench <游戏目录>`：用启动器自己的下载引擎测试不同下载源与并发数的速度
enum DownloadBench {
    nonisolated static func run(folder: URL) {
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor in
            defer { sem.signal() }
            let indexes = folder.appendingPathComponent("assets/indexes")
            guard let file = try? FileManager.default.contentsOfDirectory(at: indexes, includingPropertiesForKeys: nil).first,
                  let j = try? JSON(data: Data(contentsOf: file)) else { print("没有找到资源索引"); return }
            let hashes = j["objects"].object.values.compactMap { $0["hash"].string }.sorted().prefix(1200)
            let settings = LauncherSettings.shared
            let original = (settings.fileSource, settings.downloadThreads)
            defer { settings.fileSource = original.0; settings.downloadThreads = original.1 }
            print("代理：\(Net.systemProxyEnabled ? "已开启" : "未开启")")
            let combos: [(LauncherSettings.DownloadSource, String, Int)] = [
                (.officialFirst, "官方", 16), (.officialFirst, "官方", 64), (.mirrorFirst, "镜像", 16), (.mirrorFirst, "镜像", 64),
            ]
            for (i, (source, name, threads)) in combos.enumerated() {
                settings.fileSource = source
                let batch = hashes.dropFirst(i * 300).prefix(300)
                let dir = Paths.cache.appendingPathComponent("bench-\(i)")
                try? FileManager.default.removeItem(at: dir)
                let items = batch.map { h in
                    DownloadItem(url: "https://resources.download.minecraft.net/\(h.prefix(2))/\(h)",
                                 destination: dir.appendingPathComponent(h), sha1: h)
                }
                let start = Date()
                var result = "完成"
                do { try await Downloader.run(items, job: nil, threads: threads, checkHash: false) }
                catch { result = "失败：\(error.friendly)" }
                let t = Date().timeIntervalSince(start)
                let size = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
                    .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0
                print(String(format: "%@ %2d 路：300 个文件 %.1f 秒（%.1f 个/秒，%.2f MB/s）%@",
                             name, threads, t, 300 / t, Double(size) / 1048576 / t, result))
                try? FileManager.default.removeItem(at: dir)
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
}
