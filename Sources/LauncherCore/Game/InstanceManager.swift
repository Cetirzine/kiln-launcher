import Foundation

/// 版本管理：重命名、复制；存档的导入与导出
package enum InstanceManager {
    /// 检查新名称，返回错误信息
    package static func validateName(_ name: String, folder: URL) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return T("请输入名称", "Enter a name") }
        if n.contains(where: { "/\\:!*?\"<>|".contains($0) }) || n.hasPrefix(".") {
            return T("名称不能包含 / \\ : ! * ? \" < > | 或以 . 开头", "The name can't contain / \\ : ! * ? \" < > | or start with .")
        }
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("versions/\(n)").path) {
            return T("已存在名为 \(n) 的版本", "An instance named \(n) already exists")
        }
        return nil
    }

    /// 依赖这个版本的其他版本（inheritsFrom）
    package static func dependents(of instance: McInstance) -> [String] {
        let versions = instance.folder.appendingPathComponent("versions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return names.filter { n in
            guard n != instance.name,
                  let data = try? Data(contentsOf: versions.appendingPathComponent("\(n)/\(n).json")),
                  let j = try? JSON(data: data) else { return false }
            return j["inheritsFrom"].string == instance.name
        }
    }

    /// 重命名
    package static func rename(_ instance: McInstance, to newName: String) throws {
        if let e = validateName(newName, folder: instance.folder) { throw LauncherError(e) }
        let deps = dependents(of: instance)
        if !deps.isEmpty {
            throw LauncherError(T("\(deps.joined(separator: "、")) 依赖这个版本，不能重命名", "\(deps.joined(separator: ", ")) depend on this instance, so it can't be renamed"))
        }
        let target = instance.folder.appendingPathComponent("versions/\(newName)", isDirectory: true)
        try FileManager.default.moveItem(at: instance.dir, to: target)
        try renameContents(in: target, from: instance.name, to: newName)
        if LauncherSettings.shared.selectedInstance == instance.name { LauncherSettings.shared.selectedInstance = newName }
    }

    /// 复制为新版本（APFS 上为写时克隆，几乎不占用额外空间）
    package static func duplicate(_ instance: McInstance, as newName: String) throws {
        if let e = validateName(newName, folder: instance.folder) { throw LauncherError(e) }
        let target = instance.folder.appendingPathComponent("versions/\(newName)", isDirectory: true)
        try FileManager.default.copyItem(at: instance.dir, to: target)
        try renameContents(in: target, from: instance.name, to: newName)
        // 新版本从未启动过
        var setup = LauncherSettings.shared.instanceSetup(target)
        setup.lastPlayed = nil
        LauncherSettings.shared.saveInstanceSetup(setup, target)
    }

    /// 版本文件夹内与名称相关的文件：<名称>.json（及其中的 id）、<名称>.jar、natives
    private static func renameContents(in dir: URL, from old: String, to new: String) throws {
        let fm = FileManager.default
        let oldJson = dir.appendingPathComponent("\(old).json"), newJson = dir.appendingPathComponent("\(new).json")
        var j = try JSON(data: Data(contentsOf: oldJson)).object
        j["id"] = .string(new)
        try JSON.object(j).data().write(to: newJson)
        try fm.removeItem(at: oldJson)
        let oldJar = dir.appendingPathComponent("\(old).jar")
        if fm.fileExists(atPath: oldJar.path) { try fm.moveItem(at: oldJar, to: dir.appendingPathComponent("\(new).jar")) }
        // natives 会在启动时重新解压
        try? fm.removeItem(at: dir.appendingPathComponent("\(old)-natives"))
        // 类数据共享缓存与类路径相关，改名后失效
        for f in (try? fm.contentsOfDirectory(at: dir.appendingPathComponent(".kiln"), includingPropertiesForKeys: nil)) ?? []
            where f.pathExtension == "jsa" || f.pathExtension == "aot" {
            try? fm.removeItem(at: f)
        }
    }

    // MARK: 存档

    package struct World: Identifiable, Hashable, Sendable {
        package var id: URL { url }
        package let url: URL
        package var name: String { url.lastPathComponent }
        package let lastPlayed: Date
        package let icon: URL?
    }

    package static func worlds(_ instance: McInstance) -> [World] {
        let saves = instance.gameDir.appendingPathComponent("saves")
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return dirs.compactMap { d in
            let level = d.appendingPathComponent("level.dat")
            guard fm.fileExists(atPath: level.path) else { return nil }
            let date = (try? level.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let icon = d.appendingPathComponent("icon.png")
            return World(url: d, lastPlayed: date, icon: fm.fileExists(atPath: icon.path) ? icon : nil)
        }.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    /// 导出存档为 zip（包含存档文件夹本身，可直接导入其他启动器或解压到 saves）
    package static func exportWorld(_ world: World, to output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        try Updater.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noqtn", world.url.path, output.path])
    }

    /// 导入存档 zip：压缩包根目录可以是存档文件夹，也可以直接是 level.dat
    package static func importWorld(_ archive: URL, into instance: McInstance) throws -> String {
        let fm = FileManager.default
        let tmp = Paths.cache.appendingPathComponent("world-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try Zip.extractAll(archive, to: tmp)
        // 找到包含 level.dat 的目录
        var root: URL?
        if fm.fileExists(atPath: tmp.appendingPathComponent("level.dat").path) {
            root = tmp
        } else if let e = fm.enumerator(at: tmp, includingPropertiesForKeys: nil) {
            for case let f as URL in e where f.lastPathComponent == "level.dat" && !f.path.contains("__MACOSX") {
                root = f.deletingLastPathComponent()
                break
            }
        }
        guard let root else { throw LauncherError(T("压缩包中没有找到存档（level.dat）", "No world (level.dat) was found in the archive")) }
        let saves = instance.gameDir.appendingPathComponent("saves")
        try fm.createDirectory(at: saves, withIntermediateDirectories: true)
        var name = root == tmp ? archive.deletingPathExtension().lastPathComponent : root.lastPathComponent
        let baseName = name
        var i = 2
        while fm.fileExists(atPath: saves.appendingPathComponent(name).path) { name = "\(baseName) (\(i))"; i += 1 }
        try fm.moveItem(at: root, to: saves.appendingPathComponent(name))
        return name
    }
}
