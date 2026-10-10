import SwiftUI
import AppKit
import Observation
import LauncherCore

/// 设计语言：游戏画面是主角，界面像贴在画面上的 HUD。
/// 中性的石灰色系，跟随系统浅色 / 深色；草绿只用于“开始游戏”。
/// 圆角按层级区分：整页与主图 0，面板 4，按钮 3，物品栏格子 0。
enum Theme {
    // 跟随系统外观的颜色
    static let bg = dynamic(light: 0xE8E8E6, dark: 0x1B1B1A)          // 画布
    static let bg2 = dynamic(light: 0xDEDEDB, dark: 0x151514)         // 侧栏
    static let panel = dynamic(light: 0xF6F6F5, dark: 0x242423)       // 面板
    static let panel2 = dynamic(light: 0xEDEDEB, dark: 0x2C2C2A)      // 面板内的次级区域
    static let panelHover = dynamic(light: 0xE3E3E0, dark: 0x323230)  // 悬停
    static let stroke = dynamic(light: 0xD2D2CE, dark: 0x3A3A37)      // 发丝线
    static let text = dynamic(light: 0x1E1E1D, dark: 0xECECE9)
    static let text2 = dynamic(light: 0x62625E, dark: 0xA2A29C)
    static let text3 = dynamic(light: 0x8E8E89, dark: 0x6F6F6A)

    /// 普通强调（选中、焦点）使用文字色本身，不引入第二种品牌色
    static let accent = text
    static let accentDeep = text
    static let accentSoft = dynamic(light: 0xDCDCD8, dark: 0x343432)

    /// 草绿：只用于开始游戏
    static let play = Color(hex: 0x3D8B2F)
    static let playEdge = Color(hex: 0x2B6620)
    static let playLight = Color(hex: 0x4FA33F)

    static let green = dynamic(light: 0x2F7A24, dark: 0x6CBF5A)
    static let red = dynamic(light: 0xB8322A, dark: 0xF07167)
    static let yellow = dynamic(light: 0x9A6B00, dark: 0xE2B451)

    static let accentGradient = LinearGradient(colors: [playLight, play], startPoint: .top, endPoint: .bottom)
    static let shadow = Color.black.opacity(0.0)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    // 字体：标题与启动按钮使用宽体
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// 版本图标（代码绘制的方块）
struct BundleImage: View {
    let name: String
    var body: some View { BlockIcon(kind: name) }
}

// MARK: - 面板

/// 带标题的面板：平面、发丝线边框、4pt 圆角，不使用阴影
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
                Rectangle().fill(Theme.stroke).frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.stroke))
    }
}

/// 贴在游戏画面上的半透明底（HUD）
struct Glass: View {
    var radius: CGFloat = 3
    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.14)))
    }
}

// MARK: - 按钮

struct KilnButtonStyle: ButtonStyle {
    enum Kind { case normal, highlight, red }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var enabled
        @PState private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: kind == .highlight ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(border))
                // 主按钮底部的深色边，呼应游戏里按钮的厚度
                .overlay(alignment: .bottom) {
                    if kind == .highlight {
                        Rectangle().fill(Theme.playEdge).frame(height: configuration.isPressed ? 0 : 2)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3))
                    }
                }
                .offset(y: kind == .highlight && configuration.isPressed ? 1 : 0)
                .opacity(enabled ? 1 : 0.45)
                .onHover { hover = $0 }
                .contentShape(Rectangle())
        }

        private var foreground: Color {
            switch kind {
            case .normal: return Theme.text
            case .highlight: return .white
            case .red: return Theme.red
            }
        }

        private var background: Color {
            switch kind {
            case .normal: return hover && enabled ? Theme.panelHover : Theme.panel
            case .highlight: return hover && enabled ? Theme.playLight : Theme.play
            case .red: return hover && enabled ? Theme.panelHover : Theme.panel
            }
        }

        private var border: Color {
            kind == .highlight ? .clear : Theme.stroke
        }
    }
}

extension ButtonStyle where Self == KilnButtonStyle {
    static var kiln: KilnButtonStyle { KilnButtonStyle() }
    static var kilnPrimary: KilnButtonStyle { KilnButtonStyle(kind: .highlight) }
    static var kilnDanger: KilnButtonStyle { KilnButtonStyle(kind: .red) }
}

struct IconButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void
    @PState private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hover ? Theme.text : Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 3).fill(hover ? Theme.panelHover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - 列表

/// 列表行：没有独立背景，靠悬停与选中区分；选中时左侧一条 2pt 竖线
struct ListItem<Trailing: View>: View {
    var icon: String?
    var systemIcon: String?
    var image: NSImage?
    var title: String
    var info: String?
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @PState private var hover = false

    init(icon: String? = nil, systemIcon: String? = nil, image: NSImage? = nil, title: String, info: String? = nil,
         selected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.icon = icon; self.systemIcon = systemIcon; self.image = image; self.title = title; self.info = info
        self.selected = selected; self.action = action; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon { BundleImage(name: icon).frame(width: 26, height: 26) }
            if let image { Image(nsImage: image).resizable().interpolation(.none).frame(width: 26, height: 26) }
            if let systemIcon {
                Image(systemName: systemIcon).font(.system(size: 14)).foregroundStyle(Theme.text2).frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Theme.text).lineLimit(1)
                if let info, !info.isEmpty {
                    Text(info).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Theme.accentSoft : (hover && action != nil ? Theme.panel2 : Color.clear))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Theme.text).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action?() }
    }
}

/// 页内标签：文字加下划线，不使用胶囊
struct SegmentBar<T: Hashable>: View {
    let items: [(T, String, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 22) {
            ForEach(items, id: \.0) { item in
                let selected = item.0 == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = item.0 }
                } label: {
                    VStack(spacing: 7) {
                        Text(item.1).font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.text : Theme.text2)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if selected {
                                Rectangle().fill(Theme.text).frame(height: 2).matchedGeometryEffect(id: "underline", in: ns)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

/// 设置项一行
struct SettingRow<Content: View>: View {
    let title: String
    var help: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.text)
                if let help, !help.isEmpty {
                    Text(help).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 230, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// 状态标记：一个小方块加文字，不用胶囊
struct Badge: View {
    let text: String
    var color: Color = Theme.text2
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
        }
    }
}

// MARK: - 通知

@MainActor
@Observable
final class Hint {
    enum Kind { case blue, green, red
        var color: Color {
            switch self { case .blue: return Theme.text2; case .green: return Theme.green; case .red: return Theme.red }
        }
    }
    struct Item: Identifiable { let id = UUID(); let text: String; let kind: Kind }

    static let shared = Hint()
    var items: [Item] = []
    /// 鼠标悬停中的通知不会自动消失
    var hovering: UUID?

    static func show(_ text: String, _ kind: Kind = .blue) {
        let item = Item(text: text, kind: kind)
        log("[Hint] \(text)")
        withAnimation(.easeOut(duration: 0.25)) {
            shared.items.append(item)
            // 最多同时显示 4 条
            if shared.items.count > 4 { shared.items.removeFirst(shared.items.count - 4) }
        }
        Task { @MainActor in
            // 显示时长随文字长度增加，错误多停留一会儿
            let seconds = max(kind == .red ? 6 : 3.5, Double(text.count) * 0.09)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            while shared.hovering == item.id { try? await Task.sleep(nanoseconds: 300_000_000) }
            dismiss(item.id)
        }
    }

    static func dismiss(_ id: UUID) {
        withAnimation(.easeIn(duration: 0.25)) { shared.items.removeAll { $0.id == id } }
    }

    nonisolated static func showOnMain(_ text: String, _ kind: Kind = .blue) async {
        await MainActor.run { show(text, kind) }
    }
}

/// 右下角的通知卡片：淡入淡出，可提前关闭
struct HintOverlay: View {
    @PState private var hint = Hint.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(hint.items) { item in
                HintCard(item: item)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.trailing, 20).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct HintCard: View {
    let item: Hint.Item
    @PState private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(item.kind.color).frame(width: 7, height: 7).padding(.top, 5)
            Text(item.text).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button { Hint.dismiss(item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(hover ? Theme.text : Theme.text3)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(T("关闭", "Close"))
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 9)
        .frame(width: 320, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.stroke))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .onHover { h in
            hover = h
            Hint.shared.hovering = h ? item.id : (Hint.shared.hovering == item.id ? nil : Hint.shared.hovering)
        }
    }
}

// MARK: - 对话框

@MainActor
@Observable
final class MsgBox {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let content: String
        let buttons: [String]
        let warn: Bool
        var input: String?
        var inputHint: String?
        var keepOpenOnFirst = false
        var firstAction: (() -> Void)?
        let resume: (Int, String) -> Void
    }

    static let shared = MsgBox()
    var queue: [Item] = []

    /// 显示对话框，返回按下的按钮序号（从 1 开始）
    static func show(title: String, content: String, buttons: [String] = [], warn: Bool = false,
                     keepOpenOnFirst: Bool = false, firstAction: (() -> Void)? = nil) async -> Int {
        await withCheckedContinuation { (c: CheckedContinuation<Int, Never>) in
            shared.queue.append(Item(title: title, content: content,
                                     buttons: buttons.isEmpty ? [T("好", "OK")] : buttons,
                                     warn: warn, keepOpenOnFirst: keepOpenOnFirst, firstAction: firstAction,
                                     resume: { i, _ in c.resume(returning: i) }))
        }
    }

    /// 带输入框的对话框，取消时返回 nil
    static func input(title: String, content: String, initial: String = "", hint: String = "") async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            shared.queue.append(Item(title: title, content: content,
                                     buttons: [T("确定", "OK"), T("取消", "Cancel")],
                                     warn: false, input: initial, inputHint: hint,
                                     resume: { i, t in c.resume(returning: i == 1 ? t : nil) }))
        }
    }

    func finish(_ item: Item, _ index: Int, _ text: String) {
        if index == 1, item.keepOpenOnFirst {
            item.firstAction?()
            return
        }
        queue.removeAll { $0.id == item.id }
        item.resume(index, text)
    }
}

struct MsgBoxOverlay: View {
    @PState private var box = MsgBox.shared
    @PState private var text = ""

    var body: some View {
        ZStack {
            if let item = box.queue.first {
                Color.black.opacity(0.32).ignoresSafeArea().transition(.opacity)
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.warn ? Theme.red : Theme.text)
                    PageScroll {
                        Text(item.content).font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    if item.input != nil {
                        TextField(item.inputHint ?? "", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { box.finish(item, 1, text) }
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        ForEach(Array(item.buttons.enumerated()).reversed(), id: \.offset) { i, b in
                            Button(b) { box.finish(item, i + 1, text) }
                                .buttonStyle(i == 0 ? (item.warn ? KilnButtonStyle(kind: .red) : .kilnPrimary) : .kiln)
                                .keyboardShortcut(i == 0 ? .defaultAction : (i == item.buttons.count - 1 ? .cancelAction : nil))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 440)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                .transition(.opacity)
                .id(item.id)
                .onAppear { text = item.input ?? "" }
            }
        }
        .animation(.easeOut(duration: 0.15), value: box.queue.first?.id)
    }
}

/// 新版 SDK 中 `@State` 会优先解析为宏（SwiftUIMacros），而命令行工具链不带该宏插件。
/// 通过类型别名直接使用属性包装器版本，使项目无需完整 Xcode 也能编译。
typealias PState = SwiftUI.State

// MARK: - 页面滚动容器

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// 离屏截图模式（ImageRenderer 不会渲染 ScrollView 的内容）
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct PageScroll<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshot
    @ViewBuilder var content: () -> Content
    var body: some View {
        if snapshot {
            VStack(spacing: 0, content: content).frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView(content: content)
        }
    }
}
