import Foundation

/// 可随 Forge 一起安装的附加组件：作为 Forge Mod 放入实例的 mods 文件夹
package enum OptiFine {
    package struct Version: Identifiable, Hashable, Sendable {
        package let game: String
        package let type: String      // 如 HD_U
        package let patch: String     // 如 I6、pre3
        package let filename: String
        /// 兼容的最低 Forge 版本说明，如 "Forge 47.2.18"
        package let forge: String?
        package var id: String { filename }
        package var isPreview: Bool { patch.lowercased().hasPrefix("pre") }
        package var display: String {
            let t = type.replacingOccurrences(of: "_", with: " ")
            return "\(t) \(patch)"
        }
    }

    /// 某个游戏版本可用的 OptiFine（正式版在前，较新的在前）
    package static func versions(game: String) async throws -> [Version] {
        let j = try await Net.json(urls: ["https://bmclapi2.bangbang93.com/optifine/\(game)"])
        let list: [Version] = j.array.compactMap { v in
            guard let type = v["type"].string, let patch = v["patch"].string, let file = v["filename"].string else { return nil }
            return Version(game: v["mcversion"].string ?? game, type: type, patch: patch, filename: file, forge: v["forge"].string)
        }
        return list.sorted { a, b in
            if a.isPreview != b.isPreview { return !a.isPreview }
            return a.patch.compare(b.patch, options: .numeric) == .orderedDescending
        }
    }

    /// 下载到 mods 文件夹：优先官网（optifine.net），失败时使用 BMCLAPI
    package static func install(_ v: Version, into mods: URL, job: Job?) async throws {
        var urls: [String] = []
        if let page = try? await Net.data(["https://optifine.net/adloadx?f=\(v.filename)"], timeout: 12),
           let html = String(data: page, encoding: .utf8),
           let range = html.range(of: #"downloadx\?f=[^'"\s]+"#, options: .regularExpression) {
            urls.append("https://optifine.net/" + html[range].replacingOccurrences(of: "&amp;", with: "&"))
        }
        urls.append("https://bmclapi2.bangbang93.com/optifine/\(v.game)/\(v.type)/\(v.patch)")
        var item = DownloadItem(url: urls[0], destination: mods.appendingPathComponent(v.filename))
        item.urls = urls
        try await Downloader.run([item], job: job)
    }
}

package enum LiteLoader {
    package struct Version: Identifiable, Hashable, Sendable {
        package let game: String
        package let version: String   // 如 1.12.2-SNAPSHOT
        package let file: String
        package let md5: String?
        package var id: String { version }
    }

    /// 某个游戏版本可用的 LiteLoader；不支持的版本返回空数组
    package static func versions(game: String) async throws -> [Version] {
        let data = try await Net.data(["https://bmclapi2.bangbang93.com/liteloader/list?mcversion=\(game)"])
        guard !data.isEmpty, let j = try? JSON(data: data) else { return [] }
        let items = j.array.isEmpty ? (j.object.isEmpty ? [] : [j]) : j.array
        return items.compactMap { v in
            guard let version = v["version"].string else { return nil }
            return Version(game: v["mcversion"].string ?? game, version: version,
                           file: v["build"]["file"].string ?? "liteloader-\(version).jar", md5: v["hash"].string)
        }
    }

    /// 下载到 mods 文件夹（官方站点已停止服务，使用 BMCLAPI）
    package static func install(_ v: Version, into mods: URL, job: Job?) async throws {
        let item = DownloadItem(url: "https://bmclapi2.bangbang93.com/liteloader/download?version=\(v.version)",
                                destination: mods.appendingPathComponent(v.file))
        try await Downloader.run([item], job: job)
    }
}
