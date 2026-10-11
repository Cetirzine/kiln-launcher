import Foundation

/// Modrinth 社区资源（Mod / 资源包 / 光影）
package enum Modrinth {
    package static let api = "https://api.modrinth.com/v2"

    package enum ProjectType: String, CaseIterable, Identifiable {
        case mod, resourcepack, shader, modpack
        package var id: String { rawValue }
        package var title: String {
            switch self {
            case .mod: return "Mod"
            case .resourcepack: return T("资源包", "Resource packs")
            case .shader: return T("光影", "Shaders")
            case .modpack: return T("整合包", "Modpacks")
            }
        }
        package var folder: String {
            switch self {
            case .mod: return "mods"
            case .resourcepack: return "resourcepacks"
            case .shader: return "shaderpacks"
            case .modpack: return ""
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
        /// 所属项目（Modrinth 项目 ID，CurseForge 为 "cf-<modId>"）
        package var projectId = ""
        package var dependencies: [Dependency] = []
        package var source: Source = .modrinth
    }

    /// 依赖：必需的前置，或可选的联动
    package struct Dependency: Hashable, Sendable {
        package let projectId: String
        package let versionId: String?
        package let required: Bool
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
        if type == .mod || type == .modpack, let loader, !loader.isEmpty {
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
        return j.array.compactMap(version)
    }

    /// 单个版本
    package static func version(id: String) async throws -> Version? {
        version(try await Net.json(urls: ["\(api)/version/\(id)"]))
    }

    /// 解析 Modrinth 的版本对象
    package static func version(_ v: JSON) -> Version? {
        let files = v["files"].array
        guard let id = v["id"].string, let file = files.first(where: { $0["primary"].bool == true }) ?? files.first,
              let fileURL = file["url"].string else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var r = Version(id: id, name: v["name"].string ?? "", number: v["version_number"].string ?? "",
                        gameVersions: v["game_versions"].array.compactMap(\.string),
                        loaders: v["loaders"].array.compactMap(\.string),
                        fileURL: fileURL, fileName: file["filename"].string ?? URL(string: fileURL)?.lastPathComponent ?? id,
                        sha1: file["hashes"]["sha1"].string, size: file["size"].double.map { Int64($0) },
                        published: iso.date(from: v["date_published"].string ?? "") ?? Date(timeIntervalSince1970: 0))
        r.projectId = v["project_id"].string ?? ""
        r.dependencies = v["dependencies"].array.compactMap { d in
            guard let type = d["dependency_type"].string, type == "required" || type == "optional" else { return nil }
            guard let pid = d["project_id"].string else { return nil }
            return Dependency(projectId: pid, versionId: d["version_id"].string, required: type == "required")
        }
        return r
    }

    /// 按 SHA-1 查找文件对应的版本（一次请求查询多个文件）
    package static func versionsByHash(_ sha1s: [String]) async throws -> [String: JSON] {
        guard !sha1s.isEmpty else { return [:] }
        let body = JSON.object(["hashes": .array(sha1s.map(JSON.string)), "algorithm": .string("sha1")]).data(pretty: false)
        let (code, j) = try await Net.request("\(api)/version_files", body: body, contentType: "application/json")
        guard code == 200 else { throw LauncherError("Modrinth HTTP \(code)") }
        return j.object
    }

    /// 按 SHA-1 查询每个文件在指定游戏版本与加载器下的最新版本
    package static func latestByHash(_ sha1s: [String], gameVersion: String, loader: String?) async throws -> [String: Version] {
        guard !sha1s.isEmpty else { return [:] }
        var body: [String: JSON] = ["hashes": .array(sha1s.map(JSON.string)), "algorithm": .string("sha1"),
                                    "game_versions": .array([.string(gameVersion)])]
        if let loader { body["loaders"] = .array(compatibleLoaders(loader).map(JSON.string)) }
        let (code, j) = try await Net.request("\(api)/version_files/update", body: JSON.object(body).data(pretty: false),
                                              contentType: "application/json")
        guard code == 200 else { throw LauncherError("Modrinth HTTP \(code)") }
        return j.object.compactMapValues(version)
    }

    /// 按 ID 批量获取项目信息
    package static func projects(ids: [String]) async throws -> [Project] {
        guard !ids.isEmpty else { return [] }
        var result: [Project] = []
        // URL 长度有限，分批查询
        for chunk in stride(from: 0, to: ids.count, by: 80).map({ Array(ids[$0..<min($0 + 80, ids.count)]) }) {
            let list = "[" + chunk.map { "\"\($0)\"" }.joined(separator: ",") + "]"
            let j = try await Net.json(urls: ["\(api)/projects?ids=\(encode(list))"])
            result += j.array.compactMap { p in
                guard let id = p["id"].string, let slug = p["slug"].string else { return nil }
                return Project(id: id, slug: slug, title: p["title"].string ?? slug, description: p["description"].string ?? "",
                               iconURL: p["icon_url"].string.flatMap(URL.init(string:)), downloads: p["downloads"].int ?? 0,
                               categories: p["categories"].array.compactMap(\.string))
            }
        }
        return result
    }
}
