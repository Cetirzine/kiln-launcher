import SwiftUI
import AppKit
import LauncherCore

/// `--snapshot <目录>`：离屏渲染主要页面，用于检查界面
@MainActor
enum Snapshot {
    static func run(to dir: URL, folder: URL? = nil) async {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState.shared
        state.instances = InstanceScanner.scan(folder ?? LauncherSettings.shared.minecraftURL)
        await BlockTextures.shared.load(from: state.instances)
        let pages: [(String, AppState.Page, AppState.SetupSection?, AppState.DownloadSection?)] = [
            ("home", .home, nil, nil), ("instances", .instances, nil, nil), ("download", .download, nil, .game),
            ("download-mod", .download, nil, .mod),
            ("download-modpack", .download, nil, .modpack),
            ("settings-performance", .setup, .performance, nil), ("settings-other", .setup, .other, nil), ("about", .about, nil, nil),
        ]
        if let first = state.instances.first {
            await BlockTextures.shared.ensure(BlockTextures.picker)
            let renderer = ImageRenderer(content: IconPicker(instance: first) {})
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("icon-picker.png"))
            }
        }
        // 新功能的界面
        func render<V: View>(_ name: String, _ view: V, width: CGFloat? = nil, height: CGFloat? = nil) {
            let r = ImageRenderer(content: view.environment(state).environment(\.snapshotMode, true)
                .frame(width: width, height: height).background(Theme.bg))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        if let pack = state.instances.first(where: { $0.name.contains("modpack") }) ?? state.instances.first {
            render("instance-mods", InstanceSetupPage(instance: pack, tab: .mods), width: 1040, height: 680)
            render("instance-worlds", InstanceSetupPage(instance: pack, tab: .worlds), width: 1040, height: 680)
            render("instance-resourcepacks", InstanceSetupPage(instance: pack, tab: .resourcepacks), width: 1040, height: 680)
            render("instance-overview", InstanceSetupPage(instance: pack, tab: .overview), width: 1040, height: 680)
            render("sheet-export", ModpackExportSheet(instance: pack).background(Theme.panel))
            render("sheet-rename", InstanceNameSheet(instance: pack, mode: .duplicate).background(Theme.panel))
        }
        state.manualDownloads = [Modpack.ManualFile(title: "ServerCore", fileName: "servercore-1.3.5-1.19.4.jar",
                                                     pageURL: "https://www.curseforge.com", destination: URL(fileURLWithPath: "/tmp/x"), sha1: nil)]
        render("sheet-manual", ManualDownloadsSheet().background(Theme.panel))
        state.manualDownloads = []
        render("sheet-ygg", YggdrasilLoginSheet(show: .constant(true)).background(Theme.panel))
        var demo = Account(kind: .offline, name: "KilnSkin", uuid: Account.offlineUUID("KilnSkin"))
        demo.skin = Account.OfflineSkin(premium: "jeb_")
        render("sheet-skin", SkinSheet(account: demo, show: .constant(true)).background(Theme.panel))
        if let (url, slim) = try? await Skins.premium("jeb_"), let skin = SkinRender.load(url) {
            render("skin-render", HStack(spacing: 20) {
                PixelImage(image: SkinRender.face(skin)).frame(width: 64, height: 64)
                PixelImage(image: SkinRender.front(skin, slim: slim)).frame(width: 80, height: 160)
            }.padding(20))
        }
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: AccountPopover().environment(state).environment(\.colorScheme, scheme)
                .background(Theme.panel).environment(\.snapshotMode, true))
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("accounts-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        // 示例通知，用于检查通知样式
        Hint.show(T("已取消启动", "Launch cancelled"), .blue)
        Hint.show(T("安装 1.21.1 失败：下载 5de7eb14 失败：请求超时（共 1 个文件未能下载，请检查网络或在设置中切换下载源）", "Installing 1.21.1 failed: request timed out"), .red)
        let original = LauncherSettings.shared.language
        defer { LauncherSettings.shared.language = original }
        for (lang, scheme) in [(AppLanguage.zhHans, ColorScheme.light), (.zhHans, .dark), (.en, .light)] {
        LauncherSettings.shared.language = lang
        for (name, page, section, download) in pages {
            state.page = page
            state.subPage = nil
            if let section { state.setupSection = section }
            if let download { state.downloadSection = download }
            let view = MainView().environment(state).environment(\.snapshotMode, true)
                .environment(\.colorScheme, scheme).frame(width: 1040, height: 680)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name)-\(lang.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
                print("已渲染 \(name)-\(lang.rawValue)-\(scheme == .dark ? "dark" : "light").png")
            }
        }
        }
    }
}
