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
        expect(Updater.isNewer("0.2.10", than: "0.2.9") && !Updater.isNewer("0.2.1", than: "0.2.1") && Updater.isNewer("1.0", than: "0.9.9"),
               "更新：版本号比较")
        expect(AppState.plainNotes("## 更新内容\n\n- **下载更快**：见 [这里](https://x)\n\n---\n\nEnglish") == "更新内容\n\n- 下载更快：见 这里",
               "更新：发布说明转纯文本")
        // 文件监视：版本目录的变化会触发刷新，资源文件的变化被忽略
        expect(FolderWatcher.isRelevant("/mc/versions/1.21/1.21.json") && FolderWatcher.isRelevant("/mc/versions/1.21/mods/a.jar")
               && !FolderWatcher.isRelevant("/mc/assets/objects/ab/abcd") && !FolderWatcher.isRelevant("/mc/versions/1.21/1.21-natives/x.dylib"),
               "文件监视的路径过滤")
        // 版本管理：重命名与复制
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("kiln-im-\(UUID().uuidString)")
            let dirA = root.appendingPathComponent("versions/A")
            try fm.createDirectory(at: dirA.appendingPathComponent("A-natives"), withIntermediateDirectories: true)
            try Data(#"{"id":"A","inheritsFrom":"1.21.1","mainClass":"x"}"#.utf8).write(to: dirA.appendingPathComponent("A.json"))
            try Data("jar".utf8).write(to: dirA.appendingPathComponent("A.jar"))
            let child = root.appendingPathComponent("versions/Child")
            try fm.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(#"{"id":"Child","inheritsFrom":"A"}"#.utf8).write(to: child.appendingPathComponent("Child.json"))
            let a = McInstance(folder: root, name: "A")
            expect((try? InstanceManager.rename(a, to: "B")) == nil, "被其他版本依赖时拒绝重命名")
            try fm.removeItem(at: root.appendingPathComponent("versions/Child"))
            try InstanceManager.duplicate(a, as: "A2")
            let dup = try JSON(data: Data(contentsOf: root.appendingPathComponent("versions/A2/A2.json")))
            expect(dup["id"].string == "A2" && fm.fileExists(atPath: root.appendingPathComponent("versions/A2/A2.jar").path)
                   && !fm.fileExists(atPath: root.appendingPathComponent("versions/A2/A-natives").path), "复制版本：JSON id、jar 改名，natives 清除")
            try InstanceManager.rename(a, to: "B")
            let renamed = try JSON(data: Data(contentsOf: root.appendingPathComponent("versions/B/B.json")))
            expect(renamed["id"].string == "B" && !fm.fileExists(atPath: dirA.path), "重命名版本")
            expect(InstanceManager.validateName("B", folder: root) != nil && InstanceManager.validateName("a/b", folder: root) != nil
                   && InstanceManager.validateName("C", folder: root) == nil, "版本名称校验")
            expect(Modpack.safePath("../x", in: root) == nil && Modpack.safePath("/etc/x", in: root) == nil
                   && Modpack.safePath("mods/a.jar", in: root)?.path == root.appendingPathComponent("mods/a.jar").path, "整合包路径安全检查")
            try? fm.removeItem(at: root)
        } catch { expect(false, "版本管理：\(error.friendly)") }
        // 账号：旧版本保存的数据（没有 needsLogin / account 字段）仍能读取
        let oldAccount = try? JSONDecoder().decode(Account.self, from: Data(#"{"kind":"offline","name":"Steve","uuid":"abc"}"#.utf8))
        expect(oldAccount?.name == "Steve" && oldAccount?.needsLogin == nil, "旧账号数据兼容")
        let oldSetup = try? JSONDecoder().decode(LauncherSettings.InstanceSetup.self, from: Data(#"{"icon":"stone"}"#.utf8))
        expect(oldSetup?.icon == "stone" && oldSetup?.account == nil, "旧版本设置兼容（无固定账号）")
        expect(Account.offlineUUID("Steve") != Account.offlineUUID("Alex"), "离线账号改名后 UUID 随之改变")
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
        // 登录令牌存在只有自己能读的文件里，不经过钥匙串
        let tokenKey = "selftest-\(UUID().uuidString)"
        TokenStore.set("token-1", for: tokenKey)
        let perms = (try? FileManager.default.attributesOfItem(atPath: TokenStore.file.path)[.posixPermissions] as? Int) ?? 0
        let roundTrip = TokenStore.get(tokenKey) == "token-1"
        TokenStore.delete(tokenKey)
        expect(roundTrip && TokenStore.get(tokenKey) == nil && perms == 0o600, "登录令牌：读写删除，文件权限 600")
        // 主页场景：快照、预发布用正式版的场景，1.21 按小版本区分，远古版本用默认场景
        let scenes: [(String, String)] = [("1.0", "1.0"), ("1.7.10", "1.7"), ("1.8.9", "1.8"), ("1.12.2", "1.12"), ("1.14 Pre-Release 1", "1.14"),
                                          ("1.20.1", "1.20"), ("1.21.1", "1.21"), ("1.21.4", "1.21.4"), ("1.21.8", "1.21.6"), ("1.21.10", "1.21.9"),
                                          ("1.21.11-rc1", "1.21.11"), ("26.1.2", "26.1"), ("26.4-snapshot-3", "26.4"), ("b1.7.3", "plains"), ("24w14a", "plains")]
        let wrong = scenes.filter { DotScenes.scene(for: $0.0).id != $0.1 }
        expect(wrong.isEmpty, "主页场景按版本选择" + (wrong.isEmpty ? "" : "：\(wrong.map { "\($0.0) → \(DotScenes.scene(for: $0.0).id)" })"))
        // 0.2.9：崩溃规则
        expect(CrashAnalyzer.analyze(["java.lang.Throwable: Manually triggered debug crash"])?.reason.contains("F3") == true, "崩溃分析：手动触发的调试崩溃")
        let mcRange = CrashAnalyzer.analyze(["Missing or unsupported mandatory dependencies:",
                                             "\tMod ID: 'minecraft', Requested by: 'create', Expected range: '[1.20.1,1.20.2)', Actual version: '1.20.4'"])
        expect(mcRange?.detail == "create" && mcRange?.reason.contains("Minecraft") == true, "崩溃分析：Forge Mod 与 Minecraft 版本不匹配")
        let fabricMc = CrashAnalyzer.analyze(["Incompatible mods found!", " - Mod 'Sodium' (sodium) 0.5.3 requires version 1.20.1 of 'Minecraft' (minecraft), but only the wrong version is present: 1.20.4!"])
        expect(fabricMc?.detail == "Sodium" && fabricMc?.reason.contains("Minecraft") == true, "崩溃分析：Fabric Mod 与 Minecraft 版本不匹配")
        let fabricJava = CrashAnalyzer.analyze([" - Mod 'Foo' (foo) 1.0 requires version 21 or later of 'OpenJDK 64-Bit Server VM' (java), but only the wrong version is present: 17!"])
        expect(fabricJava?.detail == "Foo" && fabricJava?.reason.contains("Java") == true, "崩溃分析：Mod 需要更新的 Java")
        expect(CrashAnalyzer.analyze(["java.lang.ClassCastException: class jdk.internal.loader.ClassLoaders$AppClassLoader cannot be cast to class java.net.URLClassLoader"])?.reason.contains("Java 8") == true,
               "崩溃分析：旧版 Forge 只能用 Java 8")
        let jvm = CrashAnalyzer.analyze(["# A fatal error has been detected by the Java Runtime Environment:", "# Problematic frame:", "# C  [liblwjgl.dylib+0x1234]  foo"])
        expect(jvm?.detail == "C  [liblwjgl.dylib+0x1234]  foo", "崩溃分析：JVM 崩溃，提取出错位置")
        // 诊断包：隐藏令牌与用户目录
        let scrubbed = Diagnostics.scrub("--accessToken abc.def --username X \(NSHomeDirectory())/mc eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4eHh4eHgifQ.c2lnbmF0dXJl secret-token-123",
                                         secret: "secret-token-123")
        expect(!scrubbed.contains("abc.def") && !scrubbed.contains("eyJhbGci") && !scrubbed.contains("secret-token-123")
               && scrubbed.contains("~/mc") && scrubbed.contains("--username X"), "诊断包：隐藏令牌与用户目录")
        // 游戏时长
        let en = Localizer.shared.language
        Localizer.shared.language = .zhHans
        expect(McInstance.formatPlayTime(nil) == nil && McInstance.formatPlayTime(30) == "不到 1 分钟" && McInstance.formatPlayTime(25 * 60) == "25 分钟"
               && McInstance.formatPlayTime(3 * 3600 + 20 * 60) == "3 小时 20 分钟" && McInstance.formatPlayTime(3 * 3600 + 20 * 60, compact: true) == "3.3 小时",
               "游戏时长的文字")
        Localizer.shared.language = en
        // 启动链接
        let link = LaunchLinks.url(for: "1.21.1 Fabric 测试", world: "新的世界")
        let parsed = LaunchLinks.parse(link)
        expect(link.absoluteString.hasPrefix("kiln://launch/") && parsed?.name == "1.21.1 Fabric 测试" && parsed?.options.world == "新的世界",
               "启动链接：生成与解析（空格、中文）")
        expect(LaunchLinks.parse(URL(string: "kiln://launch?server=mc.example.com:25565")!).map { $0.name == nil && $0.options.serverIp == "mc.example.com:25565" } == true
               && LaunchLinks.parse(URL(string: "https://example.com")!) == nil, "启动链接：服务器参数、拒绝其他链接")
        // 从其他启动器导入
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("kiln-import-\(UUID().uuidString)")
            let prism = root.appendingPathComponent("prism/My Pack")
            try fm.createDirectory(at: prism.appendingPathComponent(".minecraft/mods"), withIntermediateDirectories: true)
            try fm.createDirectory(at: prism.appendingPathComponent(".minecraft/saves/World"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: prism.appendingPathComponent(".minecraft/mods/sodium.jar"))
            try "[General]\nname=\"My Pack\"\nOverrideMemory=true\nMaxMemAlloc=6144\nOverrideJavaArgs=true\nJvmArgs=-Dfoo=1\nlastLaunchTime=1700000000000\n"
                .write(to: prism.appendingPathComponent("instance.cfg"), atomically: true, encoding: .utf8)
            try #"{"components":[{"uid":"org.lwjgl3","version":"3.3.3"},{"uid":"net.minecraft","version":"1.21.1"},{"uid":"net.fabricmc.fabric-loader","version":"0.16.5"}],"formatVersion":1}"#
                .write(to: prism.appendingPathComponent("mmc-pack.json"), atomically: true, encoding: .utf8)
            let p = LauncherImport.inspect(folder: prism)
            expect(p?.name == "My Pack" && p?.gameVersion == "1.21.1" && p?.loader == LauncherImport.Loader(kind: "Fabric", version: "0.16.5")
                   && p?.memoryGB == 6 && p?.jvmArgs == "-Dfoo=1" && p?.modCount == 1 && p?.worldCount == 1
                   && p?.contentDir.lastPathComponent == ".minecraft" && p?.lastPlayed == Date(timeIntervalSince1970: 1_700_000_000),
                   "导入：Prism 实例（instance.cfg + mmc-pack.json）")
            let cf = root.appendingPathComponent("curseforge/All the Mods")
            try fm.createDirectory(at: cf.appendingPathComponent("mods"), withIntermediateDirectories: true)
            try #"{"name":"All the Mods","gameVersion":"1.20.1","baseModLoader":{"name":"forge-47.2.0","forgeVersion":"47.2.0","minecraftVersion":"1.20.1"},"allocatedMemory":8192,"lastPlayed":"2024-05-01T10:00:00.123Z"}"#
                .write(to: cf.appendingPathComponent("minecraftinstance.json"), atomically: true, encoding: .utf8)
            let c = LauncherImport.inspect(folder: cf)
            expect(c?.source == .curseforge && c?.gameVersion == "1.20.1" && c?.loader == LauncherImport.Loader(kind: "Forge", version: "47.2.0")
                   && c?.memoryGB == 8 && c?.lastPlayed != nil && c?.contentDir == cf, "导入：CurseForge 实例（minecraftinstance.json）")
            let fabricCf = try JSON(data: Data(#"{"name":"F","gameVersion":"1.20.1","baseModLoader":{"name":"fabric-0.15.7-1.20.1"}}"#.utf8))
            try fabricCf.data().write(to: cf.appendingPathComponent("minecraftinstance.json"))
            expect(LauncherImport.inspect(folder: cf)?.loader == LauncherImport.Loader(kind: "Fabric", version: "0.15.7"), "导入：CurseForge 的 Fabric 加载器名称")
            // 官方启动器：只导入使用独立游戏目录的配置
            let official = root.appendingPathComponent("minecraft")
            let ver = official.appendingPathComponent("versions/fabric-loader-0.16.5-1.21.1")
            try fm.createDirectory(at: ver, withIntermediateDirectories: true)
            try #"{"id":"fabric-loader-0.16.5-1.21.1","inheritsFrom":"1.21.1","libraries":[{"name":"net.fabricmc:fabric-loader:0.16.5"}]}"#
                .write(to: ver.appendingPathComponent("fabric-loader-0.16.5-1.21.1.json"), atomically: true, encoding: .utf8)
            let customDir = root.appendingPathComponent("profile-dir")
            try fm.createDirectory(at: customDir, withIntermediateDirectories: true)
            let profiles = #"{"profiles":{"a":{"name":"Fabric 生存","lastVersionId":"fabric-loader-0.16.5-1.21.1","gameDir":"\#(customDir.path)","javaArgs":"-Xmx4G -XX:+UseG1GC -Dbar=2"},"b":{"name":"","lastVersionId":"latest-release","type":"latest-release"},"c":{"name":"默认","lastVersionId":"fabric-loader-0.16.5-1.21.1"}}}"#
            try profiles.write(to: official.appendingPathComponent("launcher_profiles.json"), atomically: true, encoding: .utf8)
            let o = LauncherImport.officialProfiles(official)
            expect(o.count == 1 && o.first?.name == "Fabric 生存" && o.first?.gameVersion == "1.21.1" && o.first?.loader?.kind == "Fabric"
                   && o.first?.memoryGB == 4 && o.first?.jvmArgs == "-Dbar=2", "导入：官方启动器配置（独立游戏目录、内存与参数）")
            // 复制内容：跳过游戏文件与日志，保留 Mod、存档
            let dst = root.appendingPathComponent("dst/X")
            try fm.createDirectory(at: dst.appendingPathComponent(".kiln"), withIntermediateDirectories: true)
            try fm.createDirectory(at: prism.appendingPathComponent(".minecraft/logs"), withIntermediateDirectories: true)
            try fm.createDirectory(at: prism.appendingPathComponent(".minecraft/versions"), withIntermediateDirectories: true)
            try LauncherImport.copyContent(from: prism.appendingPathComponent(".minecraft"), to: dst)
            expect(fm.fileExists(atPath: dst.appendingPathComponent("mods/sodium.jar").path) && fm.fileExists(atPath: dst.appendingPathComponent("saves/World").path)
                   && !fm.fileExists(atPath: dst.appendingPathComponent("logs").path) && !fm.fileExists(atPath: dst.appendingPathComponent("versions").path)
                   && fm.fileExists(atPath: dst.appendingPathComponent(".kiln").path), "导入：复制 Mod 与存档，跳过日志与游戏文件")
            expect(LauncherImport.availableName("a/b:c", folder: root) == "a-b-c", "导入：名称中的非法字符")
            try? fm.removeItem(at: root)
        } catch { expect(false, "导入：\(error.friendly)") }
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
                let isPack = loader?.hasPrefix("pack=") == true
                // KILN_TEST_INSTANCE=<版本名>：直接启动已有的版本
                let name = ProcessInfo.processInfo.environment["KILN_TEST_INSTANCE"]
                    ?? (isPack ? "\(version)-modpack-test" : "\(version)-\(loader?.lowercased() ?? "vanilla")-test")
                let instanceDir = folder.appendingPathComponent("versions/\(name)")
                if !FileManager.default.fileExists(atPath: instanceDir.appendingPathComponent("\(name).json").path) {
                    try? FileManager.default.removeItem(at: instanceDir)
                    print("安装 \(version) \(loader ?? "")…")
                    let remote = try await VersionManifest.find(version)
                    let job = Job(title: "install")
                    if isPack {
                        // 整合包：本地文件或下载地址
                        let src = String(loader!.dropFirst(5))
                        var file = URL(fileURLWithPath: src)
                        if src.hasPrefix("http") {
                            file = Paths.cache.appendingPathComponent(URL(string: src)!.lastPathComponent)
                            try await Downloader.fetch(DownloadItem(url: src, destination: file))
                        }
                        let info = try Modpack.inspect(file)
                        print("整合包：\(info.name) \(info.version)（\(info.format.rawValue)），MC \(info.gameVersion)，\(info.loader.map { "\($0.kind) \($0.version)" } ?? "原版")，\(info.fileCount) 个文件")
                        let t0 = Date()
                        let manual = try await Modpack.install(file, name: name, folder: folder, job: job)
                        print(String(format: "整合包安装完成，用时 %.1f 秒；需手动下载 %d 个文件", Date().timeIntervalSince(t0), manual.count))
                        for m in manual { print("  手动下载：\(m.title) \(m.fileName) \(m.pageURL)") }
                    } else {
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
                var login = LoginResult(name: account.name, uuid: account.uuid, accessToken: account.uuid, userType: "legacy")
                // KILN_TEST_SKIN=<正版玩家名>：测试离线皮肤（本地皮肤服务 + authlib-injector）
                let skinTest = ProcessInfo.processInfo.environment["KILN_TEST_SKIN"]
                if let premium = skinTest {
                    var acc = account
                    acc.skin = Account.OfflineSkin(premium: premium)
                    login = try await AccountStore.shared.login(acc)
                    print("离线皮肤：\(login.jvmArgs.first ?? "未启用")")
                }
                // KILN_TEST_WORLD=<存档名>：测试直接进入存档（Quick Play）
                let testWorld = ProcessInfo.processInfo.environment["KILN_TEST_WORLD"]
                let args = try Launcher.buildArguments(instance, java: java, login: login, libs: libs, ctx: ctx, options: LaunchOptions(world: testWorld))
                if let w = testWorld { print("Quick Play：\(args.contains("--quickPlaySingleplayer") ? "--quickPlaySingleplayer \(w)" : "不支持")") }
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
                    if testWorld != nil {
                        // 进入存档：等待玩家加入内置服务器
                        if joined.contains("logged in with entity id") { ok = true; break }
                        continue
                    }
                    if joined.contains("Sound engine started") || joined.contains("OpenAL initialized") || joined.contains("Initializing LWJGL OpenAL") || joined.contains("Created: ") {
                        ok = true
                        // 皮肤测试：多等几秒，让游戏查询档案与材质
                        if skinTest != nil { try await Task.sleep(nanoseconds: 6_000_000_000) }
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

/// `--modrinth-check`：按加载器搜索 Mod，检查筛选结果
enum ModrinthCheck {
    nonisolated static func run() {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = true
        Task {
            defer { sem.signal() }
            for loader in ["Fabric", "Forge", "NeoForge", "Quilt", ""] {
                do {
                    let r = try await Modrinth.search("", type: .mod, gameVersion: "1.20.1", loader: loader.isEmpty ? nil : loader)
                    let allowed = loader.isEmpty ? nil : Set(Modrinth.compatibleLoaders(loader))
                    let mismatched = allowed.map { a in r.filter { Set($0.categories).isDisjoint(with: a) } } ?? []
                    if r.isEmpty || !mismatched.isEmpty { ok = false }
                    print("\(loader.isEmpty ? "全部" : loader)：\(r.count) 个结果，前 3：\(r.prefix(3).map(\.title).joined(separator: "、"))\(mismatched.isEmpty ? "" : "，不符合筛选：\(mismatched.count)")")
                } catch { ok = false; print("\(loader)：失败 \(error.friendly)") }
            }
            // 版本列表按加载器筛选（Sodium）
            for loader in ["Fabric", "NeoForge"] {
                let v = (try? await Modrinth.versions("AANobbMI", gameVersion: "1.21.1", loader: loader)) ?? []
                let wrong = v.filter { !$0.loaders.contains(loader.lowercased()) }
                if v.isEmpty || !wrong.isEmpty { ok = false }
                print("Sodium 1.21.1 \(loader) 版本：\(v.count) 个\(wrong.isEmpty ? "" : "，不符合：\(wrong.count)")")
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print(ok ? "✔ 加载器筛选正常" : "✘ 加载器筛选有问题")
    }
}

/// `--mod-search-check`：检查中文名、中文与拼音搜索，以及 CurseForge 补充来源
enum ModSearchCheck {
    nonisolated static func run() {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = true
        func expect(_ c: Bool, _ name: String) { print(c ? "  ✔ \(name)" : "  ✘ \(name)"); if !c { ok = false } }
        Task {
            defer { sem.signal() }
            let names = ModNames.shared
            print("中文名表：\(names.count) 条")
            expect(names.chinese("create") == "机械动力", "中文名：create → 机械动力")
            expect(names.search("机械动力").first == "create", "中文搜索：机械动力")
            expect(names.search("機械動力").first == "create", "繁体搜索：機械動力")
            expect(names.search("jxdl").first == "create", "首字母搜索：jxdl")
            expect(names.search("jixiedongli").first == "create", "拼音搜索：jixiedongli")
            expect(names.search("钠").first == "sodium", "中文搜索：钠")
            expect(names.search("汉化").contains("i18nupdatemod"), "别名搜索：汉化")
            expect(names.search("ae2").first == "ae2", "英文别名：ae2")
            let projects = (try? await Modrinth.projects(names.search("背包"), gameVersion: "1.20.1", loader: "Forge")) ?? []
            expect(!projects.isEmpty, "中文搜索结果：背包（1.20.1 Forge）→ \(projects.map(\.title).joined(separator: "、"))")
            let cf = (try? await CurseForge.search("create", type: .mod, gameVersion: "1.20.1", loader: "Forge")) ?? []
            expect(cf.first?.slug == "create", "CurseForge 搜索：create → \(cf.prefix(3).map(\.title).joined(separator: "、"))")
            if let create = cf.first(where: { $0.slug == "create" }) {
                let files = (try? await CurseForge.files(create, gameVersion: "1.20.1", loader: "Forge")) ?? []
                expect(!files.isEmpty && files.allSatisfy { $0.loaders.contains("forge") && $0.gameVersions.contains("1.20.1") },
                       "CurseForge 文件筛选：\(files.count) 个，最新 \(files.first?.fileName ?? "-")")
                if let f = files.first(where: { !$0.blocked }) {
                    expect(CurseForge.downloadURLs(f).count == 2, "CurseForge 下载地址含镜像备用")
                }
            }
            let shaders = (try? await CurseForge.search("complementary", type: .shader, gameVersion: nil, loader: nil)) ?? []
            expect(!shaders.isEmpty, "CurseForge 光影：\(shaders.prefix(2).map(\.title).joined(separator: "、"))")
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print(ok ? "✔ 全部通过" : "✘ 有检查未通过")
    }
}

/// `--mod-core-check`：CurseForge 指纹、本地 Mod 识别、更新与前置解析（使用真实数据）
enum ModCoreCheck {
    nonisolated static func run() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = true
        Task {
            defer { sem.signal() }
            func expect(_ c: Bool, _ name: String) { print("  \(c ? "✔" : "✘") \(name)"); if !c { ok = false } }
            do {
                let dir = Paths.cache.appendingPathComponent("modcore-\(UUID().uuidString)/mods", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

                // CurseForge：Create 0.5.1.f（1.20.1 Forge）
                let cf = try await CurseForge.files(ids: [4835191])
                guard let create = cf[4835191] else { expect(false, "CurseForge 批量查询文件"); return }
                expect(create.fileName.hasPrefix("create-1.20.1") && create.projectId == "cf-328085", "CurseForge 批量查询文件")
                let createURL = dir.appendingPathComponent(create.fileName)
                var item = DownloadItem(url: create.fileURL, destination: createURL, sha1: create.sha1, size: create.size)
                item.urls = CurseForge.downloadURLs(create)
                try await Downloader.run([item], job: nil)
                let fp = CurseForge.fingerprint(try Data(contentsOf: createURL))
                let matched = try await CurseForge.match(fingerprints: [fp])
                expect(matched[fp]?.id == "4835191", "CurseForge 指纹（MurmurHash2）与官方一致：\(fp)")

                // Modrinth：Sodium 的一个旧版本（1.20.1 Fabric）
                let sodiumVersions = try await Modrinth.versions("AANobbMI", gameVersion: "1.20.1", loader: "fabric")
                guard let old = sodiumVersions.last else { expect(false, "Modrinth 版本列表"); return }
                try await Downloader.fetch(DownloadItem(url: old.fileURL, destination: dir.appendingPathComponent(old.fileName), sha1: old.sha1, size: old.size))
                // 一个识别不了的文件
                try Data("not a mod".utf8).write(to: dir.appendingPathComponent("unknown.jar"))

                let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                let t0 = Date()
                let entries = await ModIndex.identify(files)
                print(String(format: "  识别 %d 个文件用时 %.1f 秒", files.count, Date().timeIntervalSince(t0)))
                let byName = Dictionary(entries.values.map { ($0.file.lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
                expect(byName[old.fileName]?.project?.title == "Sodium" && byName[old.fileName]?.source == .modrinth, "识别 Modrinth Mod：\(byName[old.fileName]?.project?.title ?? "无")")
                // 同一个文件也在 Modrinth 上发布时优先使用 Modrinth
                expect(byName[create.fileName]?.project?.title.contains("Create") == true, "识别 Create（\(byName[create.fileName]?.source?.rawValue ?? "无")）：\(byName[create.fileName]?.project?.title ?? "无")")
                expect(byName["unknown.jar"]?.project == nil, "无法识别的文件保持未知")

                // 更新
                let sodiumEntry = entries.values.filter { $0.source == .modrinth }
                let up = await ModIndex.updates(sodiumEntry, gameVersion: "1.20.1", loader: "Fabric")
                expect(up.first?.latest.id == sodiumVersions.first?.id, "Modrinth 更新：\(old.number) → \(up.first?.latest.number ?? "无")")
                // CurseForge 更新：直接以 CurseForge 来源检查
                let cfProject = try await CurseForge.projects(ids: [328085])[328085]?.project
                let cfEntry = ModIndex.Entry(file: createURL, sha1: "", project: cfProject, version: create)
                let cfUp = await ModIndex.updates([cfEntry], gameVersion: "1.20.1", loader: "Forge")
                expect(cfUp.first.map { $0.latest.published > create.published } == true, "CurseForge 更新：\(create.fileName) → \(cfUp.first?.latest.fileName ?? "无")")
                if let u = up.first {
                    try await ModIndex.apply(u, job: nil)
                    let after = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                    expect(after.contains(u.latest.fileName) && !after.contains(old.fileName), "应用更新：替换为 \(u.latest.fileName)")
                }

                // 前置：Sodium Extra 需要 Sodium
                let extra = try await Modrinth.versions("PtjYWJkn", gameVersion: "1.20.1", loader: "fabric")
                if let e = extra.first {
                    let deps = try await ModIndex.requiredDependencies(of: e, gameVersion: "1.20.1", loader: "fabric", installedProjects: [])
                    expect(deps.contains { $0.version.projectId == "AANobbMI" }, "前置解析：Sodium Extra → \(deps.map { $0.project?.title ?? $0.version.projectId }.joined(separator: ", "))")
                    let none = try await ModIndex.requiredDependencies(of: e, gameVersion: "1.20.1", loader: "fabric", installedProjects: ["AANobbMI"])
                    expect(!none.contains { $0.version.projectId == "AANobbMI" }, "已安装的前置会跳过")
                }
            } catch {
                print("  ✘ \(error.friendly)")
                ok = false
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print(ok ? "全部通过" : "存在失败项")
        return ok
    }
}

/// `--modpack-install-test <文件或地址> <目录>`：只安装整合包并检查结果，不启动游戏
enum ModpackInstallCheck {
    nonisolated static func run(source: String, folder: URL) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        Task { @MainActor in
            defer { sem.signal() }
            do {
                var file = URL(fileURLWithPath: source)
                if source.hasPrefix("http") {
                    file = Paths.cache.appendingPathComponent(URL(string: source)!.lastPathComponent)
                    try await Downloader.fetch(DownloadItem(url: source, destination: file))
                }
                let info = try Modpack.inspect(file)
                print("整合包：\(info.name) \(info.version)（\(info.format.rawValue)），MC \(info.gameVersion)，\(info.loader.map { "\($0.kind) \($0.version)" } ?? "原版")，\(info.fileCount) 个文件")
                let name = "modpack-install-test"
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("versions/\(name)"))
                let t0 = Date()
                let manual = try await Modpack.install(file, name: name, folder: folder, job: Job(title: "pack"))
                let instance = McInstance(folder: folder, name: name)
                let mods = (try? FileManager.default.contentsOfDirectory(atPath: instance.gameDir.appendingPathComponent("mods").path)) ?? []
                print(String(format: "安装用时 %.1f 秒：%@，%d 个 Mod，需手动下载 %d 个", Date().timeIntervalSince(t0), instance.description, mods.count, manual.count))
                for m in manual { print("  手动下载：\(m.title)（\(m.fileName)）\(m.pageURL)") }
                for sub in ["resourcepacks", "shaderpacks", "config"] {
                    let n = (try? FileManager.default.contentsOfDirectory(atPath: instance.gameDir.appendingPathComponent(sub).path).count) ?? 0
                    print("  \(sub)：\(n)")
                }
                let loaderOK = info.loader.map { instance.loaders.contains($0.kind) } ?? true
                ok = instance.error == nil && loaderOK && mods.count + manual.count >= 1
                print(ok ? "✔ 安装成功" : "✘ 安装结果不符合预期")
                // 导出为 .mrpack 并重新读取
                let out = Paths.cache.appendingPathComponent("export-test.mrpack")
                let items = Modpack.exportItems(instance)
                print("  可导出：\(items.map { "\($0.path)\($0.suggested ? "" : "（默认不选）")" }.joined(separator: ", "))")
                let include = Set(items.filter(\.suggested).map(\.path))
                let r = try await Modpack.export(instance, name: "Export Test", version: "1.0", summary: "", include: include, to: out, job: Job(title: "export"))
                let back = try Modpack.inspect(out)
                let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                print("  导出：\(r.linked) 个文件引用 Modrinth，\(r.embedded) 个文件打包，\(Job.formatSize(Double(size)))")
                print("  重新读取：\(back.name)，MC \(back.gameVersion)，\(back.loader.map { "\($0.kind) \($0.version)" } ?? "原版")，\(back.fileCount) 个下载文件")
                let exportOK = back.gameVersion == info.gameVersion && back.loader?.kind == info.loader?.kind && back.loader?.version == info.loader?.version && r.linked > 0
                print(exportOK ? "✔ 导出成功" : "✘ 导出结果不符合预期")
                ok = ok && exportOK
            } catch {
                print("✘ \(error.friendly)")
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return ok
    }
}

/// `--skin-check`：本地皮肤服务的签名（用 openssl 独立验证）与材质下载
enum SkinCheck {
    nonisolated static func run() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = true
        Task {
            defer { sem.signal() }
            func expect(_ c: Bool, _ name: String) { print("  \(c ? "✔" : "✘") \(name)"); if !c { ok = false } }
            do {
                let (skin, slim) = try await Skins.premium("jeb_")
                expect((try? Skins.validate(Data(contentsOf: skin))) != nil, "获取同名正版皮肤（jeb_，\(slim ? "纤细" : "经典")模型）")
                let root = try SkinServer.shared.start()
                let uuid = Account.offlineUUID("KilnSkin")
                SkinServer.shared.register(uuid: uuid, name: "KilnSkin", skin: skin, slim: slim)
                let meta = try await Net.json(urls: [root])
                let profile = try await Net.json(urls: [root + "/sessionserver/session/minecraft/profile/\(uuid)?unsigned=false"])
                let prop = profile["properties"][0]
                guard let value = prop["value"].string, let sig = prop["signature"].string, let pem = meta["signaturePublickey"].string else {
                    expect(false, "档案包含签名的材质属性"); return
                }
                let dir = Paths.cache.appendingPathComponent("skincheck-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }
                try Data(value.utf8).write(to: dir.appendingPathComponent("value"))
                try Data(base64Encoded: sig)!.write(to: dir.appendingPathComponent("sig"))
                try Data(pem.utf8).write(to: dir.appendingPathComponent("pub.pem"))
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
                p.arguments = ["dgst", "-sha1", "-verify", dir.appendingPathComponent("pub.pem").path,
                               "-signature", dir.appendingPathComponent("sig").path, dir.appendingPathComponent("value").path]
                let out = Pipe(); p.standardOutput = out; p.standardError = out
                try p.run(); p.waitUntilExit()
                let result = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                expect(p.terminationStatus == 0, "签名通过 openssl 验证（\(result)）")
                let textures = try JSON(data: Data(base64Encoded: value)!)
                let url = textures["textures"]["SKIN"]["url"].string ?? ""
                let png = try await Net.data([url])
                expect(png == (try Data(contentsOf: skin)), "材质地址可下载且内容一致：\(url)")
                let names = try await Net.request(root + "/api/profiles/minecraft", body: JSON.array([.string("kilnskin")]).data(pretty: false), contentType: "application/json")
                expect(names.1[0]["id"].string == uuid, "按名称查询 UUID")
                let joined = try await Net.json(urls: [root + "/sessionserver/session/minecraft/hasJoined?username=KilnSkin&serverId=x"])
                expect(joined["id"].string == uuid, "局域网联机验证（hasJoined）")
                // 外置登录：只输入域名也能通过 ALI 找到 API 地址
                let ls = try await Yggdrasil.resolve("littleskin.cn")
                expect(ls.root == "https://littleskin.cn/api/yggdrasil" && Yggdrasil.serverName(ls.meta, root: ls.root) == "LittleSkin",
                       "外置登录地址解析：littleskin.cn → \(ls.root)（\(Yggdrasil.serverName(ls.meta, root: ls.root))）")
                let jar = try await AuthlibInjector.ensure()
                expect(FileManager.default.fileExists(atPath: jar.path), "authlib-injector 已就绪")
            } catch {
                print("  ✘ \(error.friendly)")
                ok = false
            }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print(ok ? "全部通过" : "存在失败项")
        return ok
    }
}

/// `--profile-check`：用已登录的第一个微软账号读取正版档案（只读：拥有的游戏、联机权限、改名信息、名称可用性），不改任何东西
enum ProfileCheck {
    nonisolated static func run() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = true
        Task { @MainActor in
            defer { sem.signal() }
            func expect(_ c: Bool, _ name: String) { print("  \(c ? "✔" : "✘") \(name)"); if !c { ok = false } }
            guard let acc = AccountStore.shared.accounts.first(where: { $0.kind == .microsoft }) else { print("没有微软账号，跳过"); return }
            do {
                let t = try await AccountStore.shared.login(acc).accessToken
                let o = try await MinecraftServices.ownership(token: t)
                expect(true, "拥有的游戏：Java \(o.javaPurchased ? "已购买" : "Game Pass")，基岩版 \(o.bedrock)，Dungeons \(o.dungeons)，Legends \(o.legends)")
                let a = try await MinecraftServices.attributes(token: t)
                expect(true, "联机 \(a.multiplayer)，Realms \(a.realms)，聊天 \(a.chat)，封禁 \(a.multiplayerBan.map { "\($0.expires.map(\.description) ?? "永久") \($0.reason ?? "")" } ?? "无")")
                let n = try await MinecraftServices.nameChange(token: t)
                expect(n.changedAt != nil, "上次改名 \(n.changedAt.map(\.description) ?? "-")，现在\(n.allowed ? "可以" : "不能")改名")
                let taken = try await MinecraftServices.nameStatus("Notch", token: t)
                expect(taken != .available, "Notch 不可用（\(taken)）")
                let free = try await MinecraftServices.nameStatus("Kiln_" + String(UUID().uuidString.prefix(8)).replacingOccurrences(of: "-", with: ""), token: t)
                expect(free == .available, "随机新名称可用（\(free)）")
            } catch { expect(false, error.friendly) }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return ok
    }
}

/// `--import-test <实例文件夹> <游戏目录>`：从其他启动器的实例导入为新版本（会下载游戏与加载器）
enum ImportCheck {
    nonisolated static func run(source: URL, folder: URL) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        Task { @MainActor in
            defer { sem.signal() }
            guard let c = LauncherImport.inspect(folder: source) else { print("✘ 无法识别实例：\(source.path)"); return }
            print("识别：\(c.source.rawValue) · \(c.name) · \(c.summary) · \(c.modCount) 个 Mod · \(c.worldCount) 个存档 · 内存 \(c.memoryGB.map { "\($0) GB" } ?? "默认")")
            do {
                let name = LauncherImport.availableName(c.name, folder: folder)
                let t0 = Date()
                try await LauncherImport.run(c, name: name, folder: folder, job: Job(title: "import"))
                let instance = McInstance(folder: folder, name: name)
                let worlds = InstanceManager.worlds(instance).map(\.name)
                print(String(format: "导入为 %@（%@），用时 %.1f 秒；存档：%@；独立目录：%@；内存：%@", name, instance.description, Date().timeIntervalSince(t0),
                             worlds.joined(separator: ", "), instance.isolated ? "是" : "否", instance.setup.memoryGB.map { "\($0) GB" } ?? "默认"))
                ok = instance.error == nil && instance.loaders.contains(c.loader?.kind ?? "") == (c.loader != nil) && worlds.count == c.worldCount
                    && instance.setup.importedFrom == c.contentDir.path
                print(ok ? "✔ 导入成功" : "✘ 导入结果不符")
            } catch { print("✘ \(error.friendly)") }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return ok
    }
}

/// `--diagnostics-check <游戏目录> <版本名> <输出.zip>`：导出诊断包
enum DiagnosticsCheck {
    nonisolated static func run(folder: URL, name: String, output: URL) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        Task { @MainActor in
            defer { sem.signal() }
            do {
                try await Diagnostics.export(instance: McInstance(folder: folder, name: name), game: nil, to: output)
                let files = Zip.list(output)
                print(files.joined(separator: "\n"))
                ok = files.contains { $0.hasSuffix("info.txt") } && files.contains { $0.hasSuffix("launcher.log") }
                print(ok ? "✔ 已导出" : "✘ 缺少文件")
            } catch { print("✘ \(error.friendly)") }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return ok
    }
}
