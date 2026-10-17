import Foundation

/// 诊断包：把游戏日志、崩溃报告、启动器日志、Mod 列表和系统信息打包成 zip，方便发给别人帮忙看。
/// 登录令牌会被替换为 ********，用户目录替换为 ~。
package enum Diagnostics {
    /// 单个文件最多保留的大小（取末尾）
    static let maxFileSize = 4 * 1024 * 1024

    /// 导出诊断包。game 为空时只收集游戏目录中的日志
    @MainActor
    package static func export(instance: McInstance, game: GameProcess?, to output: URL) async throws {
        let info = summary(instance: instance, game: game)
        let secret = game?.secret
        let since = game?.startedAt ?? Date().addingTimeInterval(-86400)
        let outputLog = game?.logFile
        let lines = game?.lines ?? []
        let gameDir = instance.gameDir
        try await Task.detached {
            let fm = FileManager.default
            let root = Paths.cache.appendingPathComponent("diagnostics-\(UUID().uuidString)", isDirectory: true)
            let dir = root.appendingPathComponent(output.deletingPathExtension().lastPathComponent, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }

            func write(_ text: String, _ name: String) throws {
                try scrub(text, secret: secret).write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            func copy(_ src: URL, _ name: String) throws {
                guard let data = try? Data(contentsOf: src) else { return }
                try write(String(decoding: data.suffix(maxFileSize), as: UTF8.self), name)
            }

            try write(info, "info.txt")
            try copy(Log.file, "launcher.log")
            // 游戏输出：优先使用本次启动保存的完整输出
            if let f = outputLog, fm.fileExists(atPath: f.path) { try copy(f, "game-output.log") }
            else if !lines.isEmpty { try write(lines.joined(separator: "\n"), "game-output.log") }
            try copy(gameDir.appendingPathComponent("logs/latest.log"), "latest.log")
            if let report = newest(in: gameDir.appendingPathComponent("crash-reports"), since: since, where: { $0.pathExtension == "txt" }) {
                try copy(report, "crash-report-" + report.lastPathComponent)
            }
            // JVM 自身崩溃时的报告
            if let hs = newest(in: gameDir, since: since, where: { $0.lastPathComponent.hasPrefix("hs_err_pid") }) {
                try copy(hs, hs.lastPathComponent)
            }
            try? fm.removeItem(at: output)
            _ = try Updater.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noqtn", dir.path, output.path])
        }.value
    }

    /// 诊断信息正文
    @MainActor
    package static func summary(instance: McInstance, game: GameProcess?) -> String {
        var s: [String] = []
        s.append("\(AppInfo.shortName) \(AppInfo.version) — " + T("诊断信息", "Diagnostics"))
        s.append(T("生成时间：", "Generated: ") + ISO8601DateFormatter().string(from: Date()))
        s.append("")
        s.append("macOS \(RuleContext.osVersion) · \(chipName) · \(Arch.native) · " + T("内存", "Memory") + " \(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024) GB")
        s.append(T("版本：", "Instance: ") + instance.name + T("（\(instance.description)）", " (\(instance.description))"))
        s.append(T("游戏目录：", "Game directory: ") + instance.gameDir.path + (instance.isolated ? T("（独立）", " (separate)") : ""))
        s.append(T("分配内存：", "Memory allocated: ") + "\(Launcher.memoryMB(instance)) MB")
        if let j = game?.java { s.append("Java: \(j.path) (\(j.version), \(j.arch))") }
        if let game {
            let seconds = Int((game.endedAt ?? Date()).timeIntervalSince(game.startedAt))
            s.append(T("运行时长：", "Ran for: ") + "\(seconds) s" + (game.exitCode.map { T("，返回值 ", ", exit code ") + "\($0)" } ?? ""))
            if let f = CrashAnalyzer.analyze(game.lines, gameDir: instance.gameDir) {
                s.append(T("可能原因：", "Likely cause: ") + f.reason + (f.detail.map { T("（\($0)）", " (\($0))") } ?? ""))
            }
            if let c = game.commandLine { s += ["", T("启动参数：", "Launch arguments:"), c] }
        }
        for (title, sub) in [(T("Mod", "Mods"), "mods"), (T("资源包", "Resource packs"), "resourcepacks"), (T("光影", "Shaders"), "shaderpacks")] {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: instance.gameDir.appendingPathComponent(sub).path)) ?? [])
                .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            guard !files.isEmpty else { continue }
            s += ["", T("\(title)（\(files.count)）：", "\(title) (\(files.count)):")] + files.map { "  " + $0 }
        }
        return s.joined(separator: "\n") + "\n"
    }

    /// 隐藏令牌与用户目录
    package static func scrub(_ text: String, secret: String?) -> String {
        var t = text
        if let secret, secret.count >= 8 { t = t.replacingOccurrences(of: secret, with: "********") }
        let patterns = [
            #"(--accessToken\s+)\S+"#,
            #"(Session ID is token:)[^)\s]+"#,
            #"()eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+"#,
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: "$1********", options: .regularExpression)
        }
        return t.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func newest(in dir: URL, since: Date, where match: (URL) -> Bool) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []).filter(match)
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast }
        guard let latest = files.max(by: { date($0) < date($1) }), date(latest) >= since.addingTimeInterval(-60) else { return nil }
        return latest
    }

    /// 芯片型号，如 “Apple M3 Pro”
    package static var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
