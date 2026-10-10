import Foundation

/// Metallum / MetalUniversal：以 Apple Metal 替代 OpenGL / Vulkan 的实验性渲染后端
/// https://github.com/EternityQwQ/MetalUniversal（Modrinth 项目 metallum-mc）
/// 目前只有 Fabric / Quilt 版本；NeoForge 与 Forge 尚无 Metal 渲染 Mod。
package enum MetalRenderer {
    package static let projectId = "w79ASAJD"
    package static let modId = "metallum"
    package static let homepage = "https://github.com/EternityQwQ/MetalUniversal"

    /// 仅支持 Apple 芯片
    package static var deviceSupported: Bool { Arch.isAppleSilicon }

    /// 支持 Metal 渲染 Mod 的加载器
    package static let supportedLoaders = ["Fabric", "Quilt"]

    package static func supports(loader: String) -> Bool { supportedLoaders.contains(loader) }

    /// 适用于指定游戏版本与加载器的版本（最新在前）
    package static func versions(game: String, loader: String = "Fabric") async throws -> [Modrinth.Version] {
        guard supports(loader: loader) else { return [] }
        return try await Modrinth.versions(projectId, gameVersion: game, loader: loader.lowercased())
    }

    /// 实例使用的、支持 Metal 的加载器
    package static func loader(of instance: McInstance) -> String? {
        instance.loaders.first { supports(loader: $0) }
    }

    /// 已安装的 MetalUniversal（启用或禁用）
    package static func installedJar(_ instance: McInstance) -> URL? {
        let mods = instance.gameDir.appendingPathComponent("mods")
        let files = (try? FileManager.default.contentsOfDirectory(at: mods, includingPropertiesForKeys: nil)) ?? []
        return files.first { f in
            let n = f.lastPathComponent.lowercased()
            guard n.hasSuffix(".jar") || n.hasSuffix(".jar.disabled") else { return false }
            guard n.contains("metal") else { return false }
            guard let data = Zip.read(f, "fabric.mod.json"), let j = try? JSON(data: data) else { return false }
            return j["id"].string == modId
        }
    }

    package static func isEnabled(_ instance: McInstance) -> Bool {
        installedJar(instance).map { $0.pathExtension == "jar" } ?? false
    }

    /// 安装并启用：下载 Mod，并把图形后端设为默认（MetalUniversal 会把“默认”改为优先使用 Metal）
    package static func enable(_ instance: McInstance, job: Job?) async throws {
        guard let loader = loader(of: instance) else {
            throw LauncherError(T("Metal 渲染需要 Fabric 或 Quilt，NeoForge / Forge 暂无可用的 Metal 渲染 Mod。",
                                  "Metal rendering requires Fabric or Quilt; there's no Metal renderer for NeoForge / Forge yet."))
        }
        if let jar = installedJar(instance), jar.pathExtension == "disabled" {
            try FileManager.default.moveItem(at: jar, to: jar.deletingPathExtension())
        } else if installedJar(instance) == nil {
            guard let v = try await versions(game: instance.vanillaVersion, loader: loader).first else {
                throw LauncherError(T("MetalUniversal 暂不支持 Minecraft \(instance.vanillaVersion)。", "MetalUniversal doesn't support Minecraft \(instance.vanillaVersion) yet."))
            }
            let dest = instance.gameDir.appendingPathComponent("mods/\(v.fileName)")
            try await Downloader.run([DownloadItem(url: v.fileURL, destination: dest, sha1: v.sha1, size: v.size)], job: job)
        }
        try setOption(instance, key: "preferredGraphicsBackend", value: "\"default\"")
    }

    package static func disable(_ instance: McInstance) throws {
        if let jar = installedJar(instance), jar.pathExtension == "jar" {
            try FileManager.default.moveItem(at: jar, to: jar.appendingPathExtension("disabled"))
        }
    }

    /// 启动前调用：游戏退出时会把图形后端写回为实际回退到的 "opengl"，导致下次不再尝试 Metal，因此每次启动前恢复为默认
    package static func prepareLaunch(_ instance: McInstance) {
        guard isEnabled(instance) else { return }
        try? setOption(instance, key: "preferredGraphicsBackend", value: "\"default\"")
    }

    /// 修改 options.txt 中的一项
    static func setOption(_ instance: McInstance, key: String, value: String) throws {
        let url = instance.gameDir.appendingPathComponent("options.txt")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        if let i = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) {
            lines[i] = "\(key):\(value)"
        } else {
            lines.append("\(key):\(value)")
        }
        try FileManager.default.createDirectory(at: instance.gameDir, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
