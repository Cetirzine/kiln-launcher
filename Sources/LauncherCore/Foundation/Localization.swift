import Foundation

/// 界面语言。繁体中文由简体中文通过系统的简繁转换自动生成。
package enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans", zhHant = "zh-Hant", en = "en"
    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        }
    }

    /// Minecraft 的游戏语言代码
    package var gameLanguage: String {
        switch self {
        case .zhHans: return "zh_cn"
        case .zhHant: return Locale.current.region?.identifier == "HK" ? "zh_hk" : "zh_tw"
        case .en: return "en_us"
        }
    }

    package static var system: AppLanguage {
        let p = Locale.preferredLanguages.first ?? "en"
        if p.hasPrefix("zh-Hant") || p.hasPrefix("zh-TW") || p.hasPrefix("zh-HK") { return .zhHant }
        if p.hasPrefix("zh") { return .zhHans }
        return .en
    }
}

package final class Localizer: @unchecked Sendable {
    package static let shared = Localizer()
    private let lock = NSLock()
    private var hantCache: [String: String] = [:]
    package var language: AppLanguage = .system

    static let variants: [(String, String)] = [
        ("啓", "啟"), ("爲", "為"), ("裏", "裡"), ("綫", "線"), ("衆", "眾"), ("僞", "偽"), ("峯", "峰"), ("脣", "唇"), ("羣", "群"),
        ("檔案夾", "資料夾"), ("文件夾", "資料夾"), ("默認", "預設"), ("設置", "設定"), ("信息", "資訊"), ("賬號", "帳號"), ("內存", "記憶體"),
        ("網絡", "網路"), ("緩存", "快取"), ("加載", "載入"), ("程序", "程式"), ("視頻", "視訊"), ("屏幕", "螢幕"), ("文件", "檔案"),
    ]

    func traditional(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let c = hantCache[s] { return c }
        var r = s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
        // ICU 的输出使用部分旧字形，替换为台湾常用写法
        for (a, b) in Localizer.variants { r = r.replacingOccurrences(of: a, with: b) }
        hantCache[s] = r
        return r
    }
}

/// 双语文案：`T("中文", "English")`
package func T(_ zh: String, _ en: String) -> String {
    switch Localizer.shared.language {
    case .zhHans: return zh
    case .zhHant: return Localizer.shared.traditional(zh)
    case .en: return en
    }
}

/// 应用信息
package enum AppInfo {
    /// 应用名称。注意：按《PCL 存储库合理使用指南》，不得使用会与 PCL 混淆的名称。
    package static let shortName = "Kiln"
    package static let author = "NelsonPence"
    package static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.8" }
}
