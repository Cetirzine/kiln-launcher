import Foundation

/// 本地 Mod 的识别、更新与前置解析。
/// 先用 SHA-1 在 Modrinth 上一次性查询所有文件，剩下的再用 CurseForge 指纹一次性查询，不逐个请求。
package enum ModIndex {
    /// 识别出的本地文件
    package struct Entry: Sendable, Hashable {
        package let file: URL
        package let sha1: String
        package let project: Modrinth.Project?
        /// 当前文件对应的远程版本
        package let version: Modrinth.Version?
        package var source: Modrinth.Source? { version?.source }

        package init(file: URL, sha1: String, project: Modrinth.Project?, version: Modrinth.Version?) {
            self.file = file; self.sha1 = sha1; self.project = project; self.version = version
        }
    }

    /// 一个可用的更新
    package struct Update: Sendable, Hashable, Identifiable {
        package var id: URL { file }
        package let file: URL
        package let project: Modrinth.Project?
        package let current: Modrinth.Version?
        package let latest: Modrinth.Version
    }

    /// 识别文件（.jar 与 .jar.disabled 均可），返回 文件 → 识别结果
    package static func identify(_ files: [URL]) async -> [URL: Entry] {
        // 计算哈希（并行）
        let hashed: [(URL, String)] = await withTaskGroup(of: (URL, String)?.self) { group in
            for f in files { group.addTask { Hash.sha1(file: f).map { (f, $0) } } }
            var r: [(URL, String)] = []
            for await x in group { if let x { r.append(x) } }
            return r
        }
        var result: [URL: Entry] = [:]
        var modrinthVersions: [URL: Modrinth.Version] = [:]

        // Modrinth：一次查询全部
        if let map = try? await Modrinth.versionsByHash(hashed.map(\.1)) {
            for (file, sha1) in hashed {
                if let j = map[sha1], var v = Modrinth.version(j) { v.source = .modrinth; modrinthVersions[file] = v }
            }
        }
        let mrProjects = (try? await Modrinth.projects(ids: Array(Set(modrinthVersions.values.map(\.projectId))))) ?? []
        let mrById = Dictionary(mrProjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (file, sha1) in hashed {
            if let v = modrinthVersions[file] {
                result[file] = Entry(file: file, sha1: sha1, project: mrById[v.projectId], version: v)
            }
        }

        // 其余文件：CurseForge 指纹
        let rest = hashed.filter { result[$0.0] == nil }
        if !rest.isEmpty {
            var prints: [URL: UInt32] = [:]
            for (file, _) in rest {
                if let data = try? Data(contentsOf: file, options: .mappedIfSafe) { prints[file] = CurseForge.fingerprint(data) }
            }
            if let matched = try? await CurseForge.match(fingerprints: Array(prints.values)) {
                let modIds = Set(matched.values.compactMap { Int($0.projectId.dropFirst(3)) })
                let projects = (try? await CurseForge.projects(ids: Array(modIds))) ?? [:]
                for (file, sha1) in rest {
                    guard let fp = prints[file], let v = matched[fp] else { continue }
                    let p = Int(v.projectId.dropFirst(3)).flatMap { projects[$0]?.project }
                    result[file] = Entry(file: file, sha1: sha1, project: p, version: v)
                }
            }
        }
        // 都没找到的：仍然记录哈希
        for (file, sha1) in hashed where result[file] == nil {
            result[file] = Entry(file: file, sha1: sha1, project: nil, version: nil)
        }
        return result
    }

    /// 检查更新：Modrinth 一次请求；CurseForge 按项目并发查询
    package static func updates(_ entries: [Entry], gameVersion: String, loader: String?) async -> [Update] {
        var updates: [Update] = []
        let mr = entries.filter { $0.source == .modrinth }
        if let latest = try? await Modrinth.latestByHash(mr.map(\.sha1), gameVersion: gameVersion, loader: loader) {
            for e in mr {
                guard var v = latest[e.sha1], v.id != e.version?.id else { continue }
                // 只升级到更新的版本
                if let cur = e.version, v.published <= cur.published { continue }
                v.source = .modrinth
                updates.append(Update(file: e.file, project: e.project, current: e.version, latest: v))
            }
        }
        let cf = entries.filter { $0.source == .curseforge }
        let cfUpdates: [Update] = await withTaskGroup(of: Update?.self) { group in
            for e in cf {
                guard let project = e.project else { continue }
                group.addTask {
                    guard let files = try? await CurseForge.files(project, gameVersion: gameVersion, loader: loader),
                          let newest = files.first(where: { !$0.blocked }),
                          newest.id != e.version?.id, newest.published > (e.version?.published ?? .distantPast) else { return nil }
                    return Update(file: e.file, project: project, current: e.version, latest: newest)
                }
            }
            var r: [Update] = []
            for await u in group { if let u { r.append(u) } }
            return r
        }
        return (updates + cfUpdates).sorted { ($0.project?.title ?? "") .localizedCaseInsensitiveCompare($1.project?.title ?? "") == .orderedAscending }
    }

    /// 应用一个更新：下载新文件，旧文件移到废纸篓；已禁用的 Mod 更新后仍保持禁用
    package static func apply(_ u: Update, job: Job?) async throws {
        let disabled = u.file.lastPathComponent.hasSuffix(".disabled")
        let dir = u.file.deletingLastPathComponent()
        let dest = dir.appendingPathComponent(u.latest.fileName + (disabled ? ".disabled" : ""))
        var item = DownloadItem(url: u.latest.fileURL, destination: dest, sha1: u.latest.sha1, size: u.latest.size)
        if u.latest.source == .curseforge { item.urls = CurseForge.downloadURLs(u.latest) }
        try await Downloader.run([item], job: job)
        if dest.standardizedFileURL != u.file.standardizedFileURL {
            try? FileManager.default.trashItem(at: u.file, resultingItemURL: nil)
        }
    }

    // MARK: 前置

    /// 解析某个版本的必需前置（递归），跳过已安装的项目。返回需要额外安装的版本
    package static func requiredDependencies(of version: Modrinth.Version, gameVersion: String?, loader: String?,
                                             installedProjects: Set<String>) async throws -> [(project: Modrinth.Project?, version: Modrinth.Version)] {
        var seen = installedProjects
        seen.insert(version.projectId)
        var queue = version.dependencies.filter(\.required)
        var result: [(Modrinth.Project?, Modrinth.Version)] = []
        var depth = 0
        while !queue.isEmpty && depth < 6 {
            depth += 1
            let current = queue
            queue = []
            for dep in current where !seen.contains(dep.projectId) {
                seen.insert(dep.projectId)
                guard let v = try await resolve(dep, gameVersion: gameVersion, loader: loader) else { continue }
                result.append((nil, v))
                queue += v.dependencies.filter(\.required)
            }
        }
        // 补充项目名称
        let mrIds = result.map(\.1.projectId).filter { !$0.hasPrefix("cf-") }
        let cfIds = result.map(\.1.projectId).filter { $0.hasPrefix("cf-") }.compactMap { Int($0.dropFirst(3)) }
        let mr = Dictionary(((try? await Modrinth.projects(ids: mrIds)) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cf = (try? await CurseForge.projects(ids: cfIds)) ?? [:]
        return result.map { (_, v) in
            let p = v.projectId.hasPrefix("cf-") ? Int(v.projectId.dropFirst(3)).flatMap { cf[$0]?.project } : mr[v.projectId]
            return (p, v)
        }
    }

    private static func resolve(_ dep: Modrinth.Dependency, gameVersion: String?, loader: String?) async throws -> Modrinth.Version? {
        if dep.projectId.hasPrefix("cf-") {
            let stub = Modrinth.Project(id: dep.projectId, slug: "", title: "", description: "", iconURL: nil, downloads: 0, categories: [])
            return try await CurseForge.files(stub, gameVersion: gameVersion, loader: loader).first { !$0.blocked }
        }
        // 指定了版本时，只有在它适用于当前游戏版本时才使用
        if let id = dep.versionId, var v = try await Modrinth.version(id: id),
           gameVersion == nil || v.gameVersions.contains(gameVersion!) {
            v.source = .modrinth
            return v
        }
        var v = try await Modrinth.versions(dep.projectId, gameVersion: gameVersion, loader: loader).first
        v?.source = .modrinth
        return v
    }

    /// 已安装 Mod 对应的项目 ID（用于跳过已安装的前置）
    package static func installedProjects(_ entries: [URL: Entry]) -> Set<String> {
        Set(entries.values.compactMap { $0.version?.projectId })
    }
}
