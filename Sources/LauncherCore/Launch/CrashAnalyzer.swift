import Foundation

/// 崩溃分析：在游戏输出与崩溃报告中查找常见原因（思路参考 HMCL 的崩溃分析规则）
package enum CrashAnalyzer {
    package struct Finding {
        package let reason: String
        package let detail: String?
    }

    private struct Rule {
        let patterns: [String]
        let reason: () -> String
        /// 用于提取细节（如 Mod 名称）的正则，取第一个匹配到的捕获组
        var detail: String?
    }

    private static let rules: [Rule] = [
        Rule(patterns: ["Manually triggered debug crash"],
             reason: { T("这是手动触发的调试崩溃（按住了 F3 + C），不是游戏出错。", "This crash was triggered on purpose by holding F3 + C; nothing is wrong with the game.") }),
        // Forge / NeoForge 1.13+ 与 Fabric / Quilt 对 Minecraft 版本的依赖检查
        Rule(patterns: ["Mod ID: 'minecraft', Requested by", "of 'Minecraft' (minecraft), but only the wrong version is present",
                        "requires minecraft ", "which requires Minecraft "],
             reason: { T("有 Mod 不适用于这个 Minecraft 版本。请换用对应版本的 Mod，或删除它。", "A mod is made for a different Minecraft version. Get the matching version of the mod or remove it.") },
             detail: #"(?:Requested by: '([^']+)'|Mod '([^']+)'[^\n]*of 'Minecraft')"#),
        Rule(patterns: ["' (java), but only the wrong version is present", "Mod ID: 'java', Requested by"],
             reason: { T("有 Mod 需要更新的 Java。请在版本设置中将 Java 改为自动选择，或手动选择更新的 Java。", "A mod needs a newer Java. Set Java to automatic in the instance settings, or pick a newer Java.") },
             detail: #"(?:Requested by: '([^']+)'|Mod '([^']+)'[^\n]*\(java\))"#),
        // Forge 1.12.2 及以前只能运行在 Java 8 上
        Rule(patterns: ["cannot be cast to class java.net.URLClassLoader", "ClassLoaders$AppClassLoader cannot be cast to"],
             reason: { T("这个版本只能使用 Java 8。请在版本设置中将 Java 改为自动选择。", "This version only runs on Java 8. Set Java to automatic in the instance settings.") }),
        Rule(patterns: ["UnsupportedClassVersionError", "has been compiled by a more recent version of the Java Runtime"],
             reason: { T("Java 版本过低。请在版本设置中将 Java 改为自动选择。", "Java is too old. Set Java to automatic in the instance settings.") }),
        Rule(patterns: ["Could not reserve enough space", "Invalid maximum heap size", "There is insufficient memory for the Java Runtime"],
             reason: { T("无法分配所需内存。请减少分配的内存。", "Couldn't allocate the requested memory. Lower the memory allocation.") }),
        Rule(patterns: ["java.lang.OutOfMemoryError", "GC overhead limit exceeded"],
             reason: { T("内存不足。请增加分配的内存，或减少 Mod 与资源包。", "Out of memory. Allocate more memory or use fewer mods and resource packs.") }),
        Rule(patterns: ["Pixel format not accelerated", "GLFW error 65543", "GLFW error 65542", "Failed to create a GLFW window", "No OpenGL context"],
             reason: { T("无法创建 OpenGL 窗口。请更新 macOS，或关闭光影与渲染类 Mod 后重试。", "Couldn't create an OpenGL window. Update macOS, or disable shaders and rendering mods.") }),
        Rule(patterns: ["UnsatisfiedLinkError", "no lwjgl in java.library.path", "Failed to locate library: liblwjgl"],
             reason: { T("本地库与 Java 架构不匹配。请在设置中切换 Java，或关闭“原生运行旧版本”。", "Native libraries don't match the Java architecture. Switch Java or turn off \"Run older versions natively\".") }),
        Rule(patterns: ["DuplicateModsFoundException", "Found duplicate mods", "duplicate mod ID"],
             reason: { T("安装了重复的 Mod。", "Duplicate mods are installed.") },
             detail: #"(?:Mod ID|mod ID)[: ]+'?([\w\-]+)"#),
        Rule(patterns: ["Incompatible mods found", "Mod resolution failed", "requires any version of", "requires version"],
             reason: { T("Mod 缺少前置或版本不兼容。", "A mod is missing a dependency or is incompatible.") },
             detail: #"Mod '([^']+)'"#),
        Rule(patterns: ["MissingModsException", "Missing or unsupported mandatory dependencies"],
             reason: { T("缺少前置 Mod。", "A required dependency mod is missing.") },
             detail: #"Mod ID: '([^']+)'"#),
        Rule(patterns: ["Mixin apply failed", "MixinApplyError", "InvalidInjectionException"],
             reason: { T("某个 Mod 的 Mixin 注入失败，可能与当前版本或其他 Mod 不兼容。", "A mod's Mixin failed to apply; it may be incompatible with this version or another mod.") },
             detail: #"from mod ([\w\-]+)"#),
        Rule(patterns: ["java.lang.NoSuchMethodError", "java.lang.NoClassDefFoundError", "java.lang.ClassNotFoundException"],
             reason: { T("缺少类或方法，通常是 Mod 与游戏或加载器版本不匹配。", "A class or method is missing; usually a mod doesn't match the game or loader version.") },
             detail: #"(?:NoSuchMethodError|NoClassDefFoundError|ClassNotFoundException): ([\w./$]+)"#),
        Rule(patterns: ["Unable to read jar", "ZipException", "Invalid or corrupt jarfile", "zip END header not found"],
             reason: { T("有文件损坏。请在版本设置中“补全文件”，或重新下载 Mod。", "A file is corrupted. Use \"Repair files\" or re-download the mod.") }),
        Rule(patterns: ["No space left on device"],
             reason: { T("磁盘空间不足。请清理磁盘后重试。", "The disk is full. Free up some space and try again.") }),
        Rule(patterns: ["A fatal error has been detected by the Java Runtime Environment"],
             reason: { T("Java 虚拟机崩溃，通常与光影、渲染类 Mod 或本地库有关。可以导出诊断包查看 hs_err 报告。", "The Java VM crashed, usually because of shaders, rendering mods or native libraries. Export a diagnostics bundle to see the hs_err report.") },
             detail: #"Problematic frame:\s*#\s*(.+)"#),
        Rule(patterns: ["The directory is locked", "Failed to load level", "Exception reading", "level.dat"],
             reason: { T("存档读取失败，可能是存档损坏或被占用。", "Failed to read a world; it may be corrupted or in use.") }),
    ]

    package static func analyze(_ lines: [String], gameDir: URL? = nil) -> Finding? {
        var text = lines.suffix(1500).joined(separator: "\n")
        // 附加最新的崩溃报告
        if let dir = gameDir?.appendingPathComponent("crash-reports"),
           let latest = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter({ $0.pathExtension == "txt" })
            .max(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }),
           let date = try? latest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(date) < 600,
           let report = try? String(contentsOf: latest, encoding: .utf8) {
            text += "\n" + report
        }
        for rule in rules where rule.patterns.contains(where: { text.contains($0) }) {
            var detail: String?
            if let p = rule.detail, let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = (1..<m.numberOfRanges).lazy.compactMap({ Range(m.range(at: $0), in: text) }).first {
                detail = String(text[r]).trimmingCharacters(in: .whitespaces)
            }
            return Finding(reason: rule.reason(), detail: detail)
        }
        return nil
    }
}
