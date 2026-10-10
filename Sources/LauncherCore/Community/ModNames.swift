import Foundation

/// Mod 中文名表：显示中文名，并支持中文、拼音与拼音首字母搜索。
/// 数据为 Kiln 自己维护的 assets/mod-names-zh.json（键为 Modrinth slug），内置一份，并定期从仓库在线更新。
package final class ModNames: @unchecked Sendable {
    package static let shared = ModNames()

    package struct Entry: Sendable {
        package let slug: String
        package let zh: String
        let aliases: [String]
        /// 用于搜索的形式：中文名与别名（小写、简体）、完整拼音、拼音首字母
        let terms: [String]
        let pinyin: String
        let initials: String
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var updated = ""

    private static let remoteURLs = [
        "https://cdn.jsdelivr.net/gh/Cetirzine/kiln-launcher@main/assets/mod-names-zh.json",
        "https://raw.githubusercontent.com/Cetirzine/kiln-launcher/main/assets/mod-names-zh.json",
    ]
    private static var cacheFile: URL { Paths.cache.appendingPathComponent("mod-names-zh.json") }

    private init() {
        load(Data(ModNamesEmbedded.json.utf8))
        // 之前在线更新过的较新数据
        if let cached = try? Data(contentsOf: Self.cacheFile) { load(cached) }
    }

    /// 解析数据；只接受比当前更新的版本
    @discardableResult
    private func load(_ data: Data) -> Bool {
        guard let j = try? JSON(data: data), j["schema"].int == 1, let date = j["updated"].string else { return false }
        lock.lock(); defer { lock.unlock() }
        guard date >= updated else { return false }
        var result: [String: Entry] = [:]
        for (slug, v) in j["mods"].object {
            guard let zh = v["zh"].string, !zh.isEmpty else { continue }
            let aliases = v["aliases"].array.compactMap(\.string)
            let (py, ini) = Self.pinyin(zh)
            let terms = ([zh] + aliases).map(Self.normalize)
            result[slug] = Entry(slug: slug, zh: zh, aliases: aliases, terms: terms, pinyin: py, initials: ini)
        }
        guard !result.isEmpty else { return false }
        entries = result
        updated = date
        return true
    }

    /// 每天最多在线更新一次
    package func refresh() async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.cacheFile.path)
        if let date = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(date) < 24 * 3600 { return }
        guard let data = try? await Net.data(Self.remoteURLs, timeout: 10) else { return }
        if load(data) {
            try? data.write(to: Self.cacheFile, options: .atomic)
            log("[ModNames] 已更新中文名表：\(entries.count) 条")
        } else {
            // 远端不比本地新，也记录检查时间
            try? data.write(to: Self.cacheFile, options: .atomic)
        }
    }

    /// Mod 的中文名
    package func chinese(_ slug: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return entries[slug]?.zh
    }

    package var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// 按中文、别名、拼音或拼音首字母搜索，返回按匹配程度排序的 slug
    package func search(_ query: String) -> [String] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let cjk = Self.containsCJK(q)
        let latin = q.allSatisfy { ($0.isLetter || $0.isNumber) && $0.isASCII }
        lock.lock(); let all = Array(entries.values); lock.unlock()
        var scored: [(String, Int)] = []
        for e in all {
            var score = 0
            if cjk {
                for t in e.terms {
                    if t == q { score = max(score, 100) }
                    else if t.hasPrefix(q) { score = max(score, 80) }
                    else if t.contains(q) { score = max(score, 60) }
                }
            } else if latin && q.count >= 2 {
                if e.terms.contains(q) { score = 100 }                                     // 英文别名，如 ae2、dh
                else if e.initials == q { score = 90 }                                     // 拼音首字母：jxdl
                else if q.count >= 3 && e.initials.hasPrefix(q) { score = 70 }
                else if q.count >= 4 && e.pinyin.hasPrefix(q) { score = 75 }               // 完整拼音：jixie
                else if q.count >= 4 && e.pinyin.contains(q) { score = 50 }
            }
            if score > 0 { scored.append((e.slug, score)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.0)
    }

    // MARK: 工具

    package static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// 小写、去空白，繁体转简体
    static func normalize(_ s: String) -> String {
        var r = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if containsCJK(r) { r = r.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? r }
        return r.replacingOccurrences(of: " ", with: "")
    }

    /// 汉字转拼音（使用系统自带的转换），返回完整拼音与首字母，如（jixiedongli, jxdl）
    static func pinyin(_ s: String) -> (String, String) {
        let m = NSMutableString(string: s)
        CFStringTransform(m, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
        let words = (m as String).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return (words.joined(), String(words.compactMap(\.first)))
    }
}
