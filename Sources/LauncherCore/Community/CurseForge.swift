import Foundation

/// CurseForge：作为 Modrinth 的补充来源。
/// 默认通过 MCIM 社区镜像访问（无需密钥）；在设置中填写官方 API 密钥后改用官方接口。
package enum CurseForge {
    static let official = "https://api.curseforge.com"
    static let mirror = "https://mod.mcimirror.top/curseforge"

    /// 资源类型对应的 CurseForge 分类 ID
    static func classId(_ type: Modrinth.ProjectType) -> Int {
        switch type {
        case .mod: return 6
        case .resourcepack: return 12
        case .shader: return 6552
        }
    }

    /// 加载器对应的 modLoaderType
    static func loaderType(_ loader: String) -> Int? {
        switch loader.lowercased() {
        case "forge": return 1
        case "fabric": return 4
        case "quilt": return 5
        case "neoforge": return 6
        default: return nil
        }
    }

    private static func get(_ path: String) async throws -> JSON {
        let key = LauncherSettings.shared.curseforgeKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            return try JSON(data: try await Net.data([official + path], headers: ["x-api-key": key]))
        }
        return try JSON(data: try await Net.data([mirror + path]))
    }

    private static func query(_ items: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return items.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }.joined(separator: "&")
    }

    package static func search(_ text: String, type: Modrinth.ProjectType, gameVersion: String?, loader: String?, offset: Int = 0) async throws -> [Modrinth.Project] {
        var q: [(String, String)] = [("gameId", "432"), ("classId", "\(classId(type))"), ("searchFilter", text),
                                     ("sortField", "2"), ("sortOrder", "desc"), ("index", "\(offset)"), ("pageSize", "30")]
        if let gameVersion, !gameVersion.isEmpty { q.append(("gameVersion", gameVersion)) }
        if type == .mod, let loader, let t = loaderType(loader) { q.append(("modLoaderType", "\(t)")) }
        let j = try await get("/v1/mods/search?" + query(q))
        let list = j["data"].array.compactMap(project)
        // CurseForge 的模糊匹配较宽：在热度顺序基础上，把名称更匹配的排到前面
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return list }
        func score(_ p: Modrinth.Project) -> Int {
            let name = p.title.lowercased()
            if name == key || p.slug == key.replacingOccurrences(of: " ", with: "-") { return 3 }
            if name.hasPrefix(key) { return 2 }
            return name.contains(key) ? 1 : 0
        }
        return list.enumerated().sorted { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    static func project(_ m: JSON) -> Modrinth.Project? {
        guard let id = m["id"].int, let slug = m["slug"].string else { return nil }
        var p = Modrinth.Project(id: "cf-\(id)", slug: slug, title: m["name"].string ?? slug, description: m["summary"].string ?? "",
                                 iconURL: m["logo"]["thumbnailUrl"].string.flatMap(URL.init(string:)),
                                 downloads: m["downloadCount"].int ?? 0,
                                 categories: m["categories"].array.compactMap { $0["name"].string })
        p.source = .curseforge
        p.pageURL = m["links"]["websiteUrl"].string
        return p
    }

    /// 某个项目的文件（版本），按游戏版本与加载器筛选
    package static func files(_ project: Modrinth.Project, gameVersion: String?, loader: String?) async throws -> [Modrinth.Version] {
        let modId = project.id.replacingOccurrences(of: "cf-", with: "")
        var q: [(String, String)] = [("pageSize", "50")]
        if let gameVersion, !gameVersion.isEmpty { q.append(("gameVersion", gameVersion)) }
        if let loader, let t = loaderType(loader) { q.append(("modLoaderType", "\(t)")) }
        let j = try await get("/v1/mods/\(modId)/files?" + query(q))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let loaderNames: Set<String> = ["forge", "neoforge", "fabric", "quilt"]
        let versions: [Modrinth.Version] = j["data"].array.compactMap { f in
            guard let id = f["id"].int, let name = f["fileName"].string else { return nil }
            let tags = f["gameVersions"].array.compactMap(\.string)
            let url = f["downloadUrl"].string ?? ""
            var v = Modrinth.Version(id: "\(id)", name: f["displayName"].string ?? name, number: name,
                                     gameVersions: tags.filter { $0.first?.isNumber == true },
                                     loaders: tags.map { $0.lowercased() }.filter { loaderNames.contains($0) },
                                     fileURL: url, fileName: name,
                                     sha1: f["hashes"].array.first { $0["algo"].int == 1 }?["value"].string,
                                     size: f["fileLength"].double.map { Int64($0) },
                                     published: iso.date(from: f["fileDate"].string ?? "") ?? Date(timeIntervalSince1970: 0))
            v.blocked = url.isEmpty
            return v
        }
        return versions.sorted { $0.published > $1.published }
    }

    /// 下载地址候选：官方 CDN，以及 MCIM 的文件镜像
    package static func downloadURLs(_ v: Modrinth.Version) -> [String] {
        guard !v.fileURL.isEmpty else { return [] }
        var urls = [v.fileURL]
        if let r = v.fileURL.range(of: "https://edge.forgecdn.net/") {
            urls.append("https://mod.mcimirror.top/" + v.fileURL[r.upperBound...])
        }
        return urls
    }
}
