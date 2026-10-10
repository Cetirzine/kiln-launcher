import Foundation

/// 远程版本列表中的一项
package struct RemoteVersion: Identifiable, Hashable, Sendable {
    package let id: String
    package let type: String
    package let url: String
    package let sha1: String?
    package let releaseTime: Date

    package var kind: McVersionKind {
        if McVersionKind.isAprilFool(id) { return .aprilFool }
        switch type {
        case "release": return .release
        case "snapshot", "pending": return .snapshot
        default: return .old
        }
    }
}

package enum McVersionKind: String, CaseIterable, Sendable {
    case release, snapshot, old, aprilFool

    package var title: String {
        switch self {
        case .release: return T("正式版", "Release")
        case .snapshot: return T("快照", "Snapshot")
        case .old: return T("远古版", "Old Alpha/Beta")
        case .aprilFool: return T("愚人节版", "April Fools")
        }
    }

    package var icon: String {
        switch self {
        case .release: return "Grass"
        case .snapshot: return "CommandBlock"
        case .old: return "CobbleStone"
        case .aprilFool: return "GoldBlock"
        }
    }

    /// 已知的愚人节版本
    package static let aprilFoolIds: Set<String> = [
        "15w14a", "1.RV-Pre1", "3D Shareware v1.34", "20w14infinite", "20w14∞", "22w13oneblockatatime",
        "23w13a_or_b", "24w14potato", "25w14craftmine", "2.0",
    ]

    package static func isAprilFool(_ id: String) -> Bool {
        aprilFoolIds.contains(id) || id.lowercased().contains("infinite") && id.hasPrefix("20w14")
    }
}

package enum VersionManifest {
    package static let url = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

    package struct Result: Sendable {
        package var latestRelease: String?
        package var latestSnapshot: String?
        package var versions: [RemoteVersion]
    }

    private static var cached: Result?

    package static func fetch(force: Bool = false) async throws -> Result {
        if !force, let cached { return cached }
        let j = try await Net.json(url, kind: .versionList)
        let iso = ISO8601DateFormatter()
        let versions: [RemoteVersion] = j["versions"].array.compactMap { v in
            guard let id = v["id"].string, let u = v["url"].string else { return nil }
            return RemoteVersion(id: id, type: v["type"].string ?? "release", url: u, sha1: v["sha1"].string,
                                 releaseTime: iso.date(from: v["releaseTime"].string ?? "") ?? Date(timeIntervalSince1970: 0))
        }
        let r = Result(latestRelease: j["latest"]["release"].string, latestSnapshot: j["latest"]["snapshot"].string, versions: versions)
        cached = r
        return r
    }

    package static func find(_ id: String) async throws -> RemoteVersion {
        let list = try await fetch()
        if let v = list.versions.first(where: { $0.id == id }) { return v }
        let fresh = try await fetch(force: true)
        if let v = fresh.versions.first(where: { $0.id == id }) { return v }
        throw LauncherError(T("在版本列表中找不到 \(id)", "Version \(id) was not found in the version list"))
    }
}

/// Fabric / Quilt 加载器
package enum ModLoaderKind: String, CaseIterable, Identifiable, Sendable {
    case fabric = "Fabric", quilt = "Quilt"
    package var id: String { rawValue }

    package var metaBase: String {
        switch self {
        case .fabric: return "https://meta.fabricmc.net/v2"
        case .quilt: return "https://meta.quiltmc.org/v3"
        }
    }

    package struct LoaderVersion: Identifiable, Hashable, Sendable {
        package let version: String
        package let stable: Bool
        package var id: String { version }
    }

    /// 某个 MC 版本可用的加载器版本
    package func versions(for game: String) async throws -> [LoaderVersion] {
        let j = try await Net.json("\(metaBase)/versions/loader/\(game)", kind: .versionList)
        return j.array.compactMap { item in
            let loader = item["loader"]
            guard let v = loader["version"].string else { return nil }
            // Quilt 没有 stable 字段，用 beta 判定
            let stable = loader["stable"].bool ?? !(v.contains("beta") || v.contains("pre"))
            return LoaderVersion(version: v, stable: stable)
        }
    }

    package func profileURL(game: String, loader: String) -> String {
        "\(metaBase)/versions/loader/\(game)/\(loader)/profile/json"
    }
}
