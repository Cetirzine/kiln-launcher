import AppKit
import SwiftUI
import UserNotifications
import LauncherCore

// MARK: - 系统通知

/// 启动器不在前台时，用系统通知告诉用户任务完成、游戏崩溃
@MainActor
enum Notifier {
    private static var requested = false
    private static let delegate = NotificationDelegate()

    /// 第一次需要时才请求权限（开始下载或启动游戏时）
    static func requestIfNeeded() {
        guard !requested, LauncherSettings.shared.systemNotifications else { return }
        requested = true
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { log("[Notify] 无法请求通知权限：\(error.localizedDescription)") }
            else if !granted { log("[Notify] 用户未允许通知") }
        }
    }

    /// 发送通知；启动器在前台时不发送（界面里已经有提示）
    static func post(_ title: String, _ body: String, action: String? = nil, force: Bool = false) {
        guard LauncherSettings.shared.systemNotifications, force || !NSApp.isActive else { return }
        requestIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let action { content.userInfo = ["action": action] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { log("[Notify] 发送通知失败：\(error.localizedDescription)") }
        }
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.notification.request.content.userInfo["action"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            let state = AppState.shared
            switch action {
            case "log": if let game = state.games.first(where: { $0.state == .crashed }) { state.showLog = game }
            case "tasks": state.subPage = nil; state.page = .download; state.downloadSection = .manager
            default: break
            }
        }
    }
}

// MARK: - Dock 图标上的进度条

@MainActor
final class DockProgress {
    static let shared = DockProgress()
    private var timer: Timer?
    private let view = DockProgressView()

    /// 有任务开始时调用；所有任务结束后自动移除进度条
    func start() {
        guard timer == nil else { return }
        NSApp.dockTile.contentView = view
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { DockProgress.shared.tick() }
        }
        tick()
    }

    private func tick() {
        let running = JobCenter.shared.running
        if running.isEmpty {
            timer?.invalidate()
            timer = nil
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.display()
            return
        }
        view.fraction = running.map(\.fraction).reduce(0, +) / Double(running.count)
        NSApp.dockTile.badgeLabel = running.count > 1 ? "\(running.count)" : nil
        NSApp.dockTile.display()
    }
}

private final class DockProgressView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        // 与界面中的进度条一致：方角，青金石色
        let bar = NSRect(x: bounds.width * 0.12, y: bounds.height * 0.1, width: bounds.width * 0.76, height: bounds.height * 0.1)
        NSColor(white: 0.12, alpha: 0.9).setFill()
        bar.fill()
        let inner = bar.insetBy(dx: bar.height * 0.18, dy: bar.height * 0.18)
        NSColor(white: 1, alpha: 0.25).setFill()
        inner.fill()
        NSColor(red: 0x4F / 255, green: 0x7C / 255, blue: 0xF5 / 255, alpha: 1).setFill()
        NSRect(x: inner.minX, y: inner.minY, width: inner.width * min(1, max(0.03, fraction)), height: inner.height).fill()
    }
}

// MARK: - Dock 菜单与启动链接

/// 带闭包的菜单项
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

@MainActor
enum LaunchLinks {
    static let scheme = "kiln"

    /// kiln://launch/<版本名>[?world=<存档>|server=<地址>]
    static func url(for instance: McInstance, world: String? = nil) -> URL { url(for: instance.name, world: world) }

    static func url(for name: String, world: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "launch"
        c.path = "/" + name
        if let world { c.queryItems = [URLQueryItem(name: "world", value: world)] }
        return c.url!
    }

    /// 解析启动链接：版本名（为空表示当前版本）与启动选项
    static func parse(_ url: URL) -> (name: String?, options: LaunchOptions)? {
        guard url.scheme?.lowercased() == scheme, ["launch", "play"].contains(url.host?.lowercased() ?? "") else { return nil }
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((c?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        var name = String((c?.path ?? "").drop(while: { $0 == "/" }))
        if name.isEmpty { name = query["instance"] ?? "" }
        let options = LaunchOptions(serverIp: query["server"].flatMap { $0.isEmpty ? nil : $0 },
                                    world: query["world"].flatMap { $0.isEmpty ? nil : $0 })
        return (name.isEmpty ? nil : name, options)
    }

    /// 处理启动链接
    static func handle(_ url: URL) {
        log("[Link] \(url.absoluteString)")
        NSApp.activate(ignoringOtherApps: true)
        guard let (name, options) = parse(url) else { return }
        AppState.shared.launch(named: name, options: options)
    }

    /// 在桌面创建双击即可启动的快捷方式：一个只打开启动链接的小 App（.webloc 不支持自定义链接），使用版本图标
    static func createDesktopShortcut(_ instance: McInstance) {
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first!
        var app = desktop.appendingPathComponent("\(instance.name).app")
        var i = 2
        while fm.fileExists(atPath: app.path) {
            app = desktop.appendingPathComponent("\(instance.name) \(i).app"); i += 1
        }
        let link = url(for: instance).absoluteString
        let id = "app.kiln.shortcut." + String(instance.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
        let info: [String: Any] = [
            "CFBundleName": instance.name, "CFBundleDisplayName": instance.name, "CFBundleIdentifier": id,
            "CFBundleExecutable": "launch", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0",
            "LSUIElement": true, "LSMinimumSystemVersion": "14.0",
        ]
        do {
            let macos = app.appendingPathComponent("Contents/MacOS")
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let script = macos.appendingPathComponent("launch")
            try "#!/bin/sh\n# \(AppInfo.shortName) 启动快捷方式\nexec /usr/bin/open '\(link.replacingOccurrences(of: "'", with: "%27"))'\n"
                .write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let renderer = ImageRenderer(content: BlockIcon(kind: instance.icon).frame(width: 256, height: 256))
            renderer.scale = 2
            if let icon = renderer.nsImage { NSWorkspace.shared.setIcon(icon, forFile: app.path) }
            NSWorkspace.shared.activateFileViewerSelecting([app])
            Hint.show(T("已在桌面创建 \(instance.name) 的快捷方式", "Created a desktop shortcut for \(instance.name)"), .green)
        } catch {
            try? fm.removeItem(at: app)
            Hint.show(error.friendly, .red)
        }
    }

    static func copyLink(_ instance: McInstance) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url(for: instance).absoluteString, forType: .string)
        Hint.show(T("已复制启动链接", "Launch link copied"), .green)
    }
}
