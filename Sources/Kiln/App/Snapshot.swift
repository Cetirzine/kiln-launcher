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
        if let sel = state.selectedInstance, let img = await Hero.loadPanorama(sel) { Hero.cache[sel.name] = img }
        await BlockTextures.shared.load(from: state.instances)
        let pages: [(String, AppState.Page, AppState.SetupSection?)] = [
            ("home", .home, nil), ("instances", .instances, nil), ("download", .download, nil),
            ("settings-performance", .setup, .performance), ("about", .about, nil),
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
        let original = LauncherSettings.shared.language
        defer { LauncherSettings.shared.language = original }
        for (lang, scheme) in [(AppLanguage.zhHans, ColorScheme.light), (.zhHans, .dark), (.en, .light)] {
        LauncherSettings.shared.language = lang
        for (name, page, section) in pages {
            state.page = page
            state.subPage = nil
            if let section { state.setupSection = section }
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
