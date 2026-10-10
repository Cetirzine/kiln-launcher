import Foundation

/// Modrinth 社区资源（Mod / 资源包 / 光影）
package enum Modrinth {
    package static let api = "https://api.modrinth.com/v2"

    package enum ProjectType: String, CaseIterable, Identifiable {
        case mod, resourcepack, shader
        package var id: String { rawValue }
        package var title: String {
            switch self {
            case .mod: return "Mod"
            case .resourcepack: return T("资源包", "Resource packs")
            case .shader: return T("光影", "Shaders")
            }
        }
        package var folder: String {
            switch self {
            case .mod: return "mods"
            case .resourcepack: return "resourcepacks"
            case .shader: return "shaderpacks"
            }
        }
    }

    /// 资源来源
    package enum Source: String, Sendable { case modrinth = "Modrinth", curseforge = "CurseForge" }

    package struct Project: Identifiable, Hashable {
        package let id: String
        package let slug: String
        package let title: String
        package let description: String
        package let iconURL: URL?
        package let downloads: Int
        package let categories: [String]
        package var source: Source = .modrinth
        /// 项目网页
        package var pageURL: String?
    }

    package struct Version: Identifiable, Hashable {
        package let id: String
        package let name: String
        package let number: String
        package let gameVersions: [String]
        package let loaders: [String]
        package let fileURL: String
        package let fileName: String
        package let sha1: String?
        package let size: Int64?
        package let published: Date
        /// 作者禁止第三方下载（CurseForge），需要到网站手动下载
        package var blocked = false
    }

    private static func encode(_ v: String) -> String {
        v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+[]\""))) ?? v
    }

    /// 某个加载器能使用的 Mod 类别：Quilt 可以加载大部分 Fabric Mod
    package static func compatibleLoaders(_ loader: String) -> [String] {
        let l = loader.lowercased()
        return l == "quilt" ? ["quilt", "fabric"] : [l]
    }

    package static func search(_ query: String, type: ProjectType, gameVersion: String?, loader: String?, offset: Int = 0) async throws -> [Project] {
        var facets = ["[\"project_type:\(type.rawValue)\"]"]
        if let gameVersion, !gameVersion.isEmpty { facets.append("[\"versions:\(gameVersion)\"]") }
        // 同一层中的多个条件为“或”：Quilt 同时包含 Fabric Mod
        if type == .mod, let loader, !loader.isEmpty {
            facets.append("[" + compatibleLoaders(loader).map { "\"categories:\($0)\"" }.joined(separator: ",") + "]")
        }
        let url = "\(api)/search?query=\(encode(query))&limit=30&offset=\(offset)&index=relevance&facets=\(encode("[" + facets.joined(separator: ",") + "]"))"
        let j = try await Net.json(urls: [url])
        return j["hits"].array.compactMap { h in
            guard let id = h["project_id"].string else { return nil }
            return Project(id: id, slug: h["slug"].string ?? id, title: h["title"].string ?? id,
                           description: h["description"].string ?? "", iconURL: h["icon_url"].string.flatMap(URL.init(string:)),
                           downloads: h["downloads"].int ?? 0, categories: h["categories"].array.compactMap(\.string))
        }
    }

    /// 按 slug 批量获取项目（用于中文名搜索），按给定顺序返回，并按游戏版本与加载器筛选
    package static func projects(_ slugs: [String], gameVersion: String?, loader: String?) async throws -> [Project] {
        guard !slugs.isEmpty else { return [] }
        let ids = "[" + slugs.prefix(60).map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let j = try await Net.json(urls: ["\(api)/projects?ids=\(encode(ids))"])
        let allowed = loader.map { Set(compatibleLoaders($0)) }
        var bySlug: [String: Project] = [:]
        for p in j.array {
            guard let id = p["id"].string, let slug = p["slug"].string else { continue }
            let loaders = p["loaders"].array.compactMap(\.string)
            if let gameVersion, !gameVersion.isEmpty, !p["game_versions"].array.compactMap(\.string).contains(gameVersion) { continue }
            if let allowed, Set(loaders).isDisjoint(with: allowed) { continue }
            bySlug[slug] = Project(id: id, slug: slug, title: p["title"].string ?? slug, description: p["description"].string ?? "",
                                   iconURL: p["icon_url"].string.flatMap(URL.init(string:)), downloads: p["downloads"].int ?? 0,
                                   categories: p["categories"].array.compactMap(\.string) + loaders)
        }
        return slugs.compactMap { bySlug[$0] }
    }

    package static func versions(_ projectId: String, gameVersion: String?, loader: String?) async throws -> [Version] {
        var url = "\(api)/project/\(projectId)/version"
        var q: [String] = []
        if let gameVersion, !gameVersion.isEmpty { q.append("game_versions=" + encode("[\"\(gameVersion)\"]")) }
        if let loader, !loader.isEmpty {
            q.append("loaders=" + encode("[" + compatibleLoaders(loader).map { "\"\($0)\"" }.joined(separator: ",") + "]"))
        }
        if !q.isEmpty { url += "?" + q.joined(separator: "&") }
        let j = try await Net.json(urls: [url])
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return j.array.compactMap { v in
            let files = v["files"].array
            guard let id = v["id"].string, let file = files.first(where: { $0["primary"].bool == true }) ?? files.first,
                  let fileURL = file["url"].string else { return nil }
            return Version(id: id, name: v["name"].string ?? "", number: v["version_number"].string ?? "",
                           gameVersions: v["game_versions"].array.compactMap(\.string),
                           loaders: v["loaders"].array.compactMap(\.string),
                           fileURL: fileURL, fileName: file["filename"].string ?? URL(string: fileURL)!.lastPathComponent,
                           sha1: file["hashes"]["sha1"].string, size: file["size"].double.map { Int64($0) },
                           published: iso.date(from: v["date_published"].string ?? "") ?? Date(timeIntervalSince1970: 0))
        }
    }
}
