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
        case .modpack: return 4471
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

    private static func post(_ path: String, _ body: JSON) async throws -> JSON {
        let key = LauncherSettings.shared.curseforgeKey.trimmingCharacters(in: .whitespaces)
        let base = key.isEmpty ? mirror : official
        let (code, j) = try await Net.request(base + path, body: body.data(pretty: false), contentType: "application/json",
                                              headers: key.isEmpty ? [:] : ["x-api-key": key])
        guard code == 200 else { throw LauncherError("CurseForge HTTP \(code)") }
        return j
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
        if type == .mod || type == .modpack, let loader, let t = loaderType(loader) { q.append(("modLoaderType", "\(t)")) }
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
        return j["data"].array.compactMap(file).sorted { $0.published > $1.published }
    }

    /// 解析 CurseForge 的文件对象
    static func file(_ f: JSON) -> Modrinth.Version? {
        guard let id = f["id"].int, let name = f["fileName"].string else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        let loaderNames: Set<String> = ["forge", "neoforge", "fabric", "quilt"]
        let tags = f["gameVersions"].array.compactMap(\.string)
        let url = f["downloadUrl"].string ?? ""
        let date = f["fileDate"].string ?? ""
        var v = Modrinth.Version(id: "\(id)", name: f["displayName"].string ?? name, number: name,
                                 gameVersions: tags.filter { $0.first?.isNumber == true },
                                 loaders: tags.map { $0.lowercased() }.filter { loaderNames.contains($0) },
                                 fileURL: url, fileName: name,
                                 sha1: f["hashes"].array.first { $0["algo"].int == 1 }?["value"].string,
                                 size: f["fileLength"].double.map { Int64($0) },
                                 published: iso.date(from: date) ?? iso2.date(from: date) ?? Date(timeIntervalSince1970: 0))
        v.blocked = url.isEmpty
        v.source = .curseforge
        v.projectId = f["modId"].int.map { "cf-\($0)" } ?? ""
        // relationType：3 必需，2 可选
        v.dependencies = f["dependencies"].array.compactMap { d in
            guard let mod = d["modId"].int, let type = d["relationType"].int, type == 3 || type == 2 else { return nil }
            return Modrinth.Dependency(projectId: "cf-\(mod)", versionId: nil, required: type == 3)
        }
        return v
    }

    /// 按文件 ID 批量查询（一次请求）
    package static func files(ids: [Int]) async throws -> [Int: Modrinth.Version] {
        guard !ids.isEmpty else { return [:] }
        var result: [Int: Modrinth.Version] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let j = try await post("/v1/mods/files", .object(["fileIds": .array(chunk.map { .number(Double($0)) })]))
            for f in j["data"].array { if let id = f["id"].int, let v = file(f) { result[id] = v } }
        }
        return result
    }

    /// 按项目 ID 批量查询（一次请求）
    package static func projects(ids: [Int]) async throws -> [Int: (project: Modrinth.Project, classId: Int)] {
        guard !ids.isEmpty else { return [:] }
        let j = try await post("/v1/mods", .object(["modIds": .array(ids.map { .number(Double($0)) })]))
        var result: [Int: (Modrinth.Project, Int)] = [:]
        for m in j["data"].array {
            if let id = m["id"].int, let p = project(m) { result[id] = (p, m["classId"].int ?? 6) }
        }
        return result
    }

    /// 按指纹查找文件（用于识别本地 Mod）：返回 指纹 → 文件
    package static func match(fingerprints: [UInt32]) async throws -> [UInt32: Modrinth.Version] {
        guard !fingerprints.isEmpty else { return [:] }
        let j = try await post("/v1/fingerprints/432", .object(["fingerprints": .array(fingerprints.map { .number(Double($0)) })]))
        var result: [UInt32: Modrinth.Version] = [:]
        for m in j["data"]["exactMatches"].array {
            let f = m["file"]
            if let fp = f["fileFingerprint"].double, let v = file(f) { result[UInt32(fp)] = v }
        }
        return result
    }

    /// CurseForge 的文件指纹：去掉空白字节后的 MurmurHash2（种子 1）
    package static func fingerprint(_ data: Data) -> UInt32 {
        let bytes = [UInt8](data.lazy.filter { $0 != 9 && $0 != 10 && $0 != 13 && $0 != 32 })
        let m: UInt32 = 0x5bd1_e995
        let len = bytes.count
        var h: UInt32 = 1 ^ UInt32(truncatingIfNeeded: len)
        var i = 0
        while i + 4 <= len {
            var k = UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            k = k &* m
            k ^= k >> 24
            k = k &* m
            h = h &* m
            h ^= k
            i += 4
        }
        let rest = len - i
        if rest >= 3 { h ^= UInt32(bytes[i + 2]) << 16 }
        if rest >= 2 { h ^= UInt32(bytes[i + 1]) << 8 }
        if rest >= 1 {
            h ^= UInt32(bytes[i])
            h = h &* m
        }
        h ^= h >> 13
        h = h &* m
        h ^= h >> 15
        return h
    }

    /// 项目网页
    package static func pageURL(classId: Int, slug: String) -> String {
        let path: String
        switch classId {
        case 12: path = "texture-packs"
        case 6552: path = "shaders"
        case 4471: path = "modpacks"
        default: path = "mc-mods"
        }
        return "https://www.curseforge.com/minecraft/\(path)/\(slug)"
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
