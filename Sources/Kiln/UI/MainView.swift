import SwiftUI
import LauncherCore
import AppKit

struct MainView: View {
    @Environment(AppState.self) private var state
    @PState private var settings = LauncherSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack(alignment: .top) {
                Theme.bg
                content
                    .transition(.opacity)
                    .id(pageKey)
            }
            .animation(.easeOut(duration: 0.12), value: pageKey)
        }
        // 切换语言后重建界面
        .id(settings.language)
        .overlay { HintOverlay() }
        .overlay { MsgBoxOverlay() }
        .background(WindowAccessor())
        .ignoresSafeArea(.container, edges: .top)
    }

    private var pageKey: String {
        switch state.subPage {
        case .none: return state.page.rawValue
        case .instanceSetup(let i): return "setup-" + i.name
        case .log(let g): return "log-" + g.id.uuidString
        }
    }

    @ViewBuilder private var content: some View {
        switch state.subPage {
        case .instanceSetup(let i): InstanceSetupPage(instance: i)
        case .log(let g): GameLogPage(game: g)
        case .none:
            switch state.page {
            case .home: HomePage()
            case .instances: InstancesPage()
            case .download: DownloadPage()
            case .setup: SetupPage()
            case .about: AboutPage()
            }
        }
    }
}

// MARK: - 左侧导航

struct Sidebar: View {
    @Environment(AppState.self) private var state
    @PState private var jobs = JobCenter.shared

    var body: some View {
        VStack(spacing: 2) {
            // 为红绿灯按钮留出空间
            Color.clear.frame(height: 46)
            Logo().padding(.bottom, 18)
            item(.home, T("开始", "Play"), "play.fill")
            item(.instances, T("版本", "Instances"), "square.grid.3x3.fill")
            item(.download, T("下载", "Download"), "arrow.down.to.line")
            item(.setup, T("设置", "Settings"), "slider.horizontal.3")
            Spacer()
            if !jobs.running.isEmpty {
                Button {
                    state.subPage = nil
                    state.page = .download
                    state.downloadSection = .manager
                } label: {
                    VStack(spacing: 4) {
                        ProgressView(value: jobs.running.first?.fraction ?? 0)
                            .progressViewStyle(BarProgressStyle())
                            .frame(width: 34, height: 3)
                        Text(T("\(jobs.running.count) 个任务", "\(jobs.running.count) task\(jobs.running.count == 1 ? "" : "s")"))
                            .font(.system(size: 9.5)).foregroundStyle(Theme.text2)
                    }
                    .frame(width: 64, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(T("查看任务", "Show tasks"))
            }
            item(.about, T("关于", "About"), "info.circle")
                .padding(.bottom, 12)
        }
        .frame(width: 76)
        .background(Theme.bg2)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }

    private func item(_ page: AppState.Page, _ title: String, _ icon: String) -> some View {
        SidebarButton(title: title, icon: icon, selected: state.page == page && state.subPage == nil) {
            state.subPage = nil
            state.page = page
        }
    }
}

struct SidebarButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @PState private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: selected ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected || hover ? Theme.text : Theme.text2)
            .frame(width: 76, height: 50)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(Theme.text).frame(width: 2, height: 30) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 标志：黑色圆角方块上的白色镐子
struct Logo: View {
    var body: some View {
        LogoMark().frame(width: 30, height: 30)
    }
}

struct BarProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.stroke)
                Rectangle().fill(Theme.text).frame(width: g.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
    }
}

/// 页面标题行：左侧标题，右侧操作与账号
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var back: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, back: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title; self.subtitle = subtitle; self.back = back; self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let back {
                IconButton(systemImage: "chevron.left", help: T("返回", "Back"), action: back)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(21)).foregroundStyle(Theme.text).lineLimit(1)
                if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle) }
            }
            Spacer()
            trailing()
            AccountChip()
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

/// 让窗口可以通过背景拖动，并使用透明标题栏
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
