import SwiftUI
import LauncherCore

/// 实例图标：点击后弹出选择器
struct InstanceIconButton: View {
    let instance: McInstance
    var size: CGFloat = 52
    @PState private var show = false
    @PState private var hover = false

    var body: some View {
        Button { show = true } label: {
            BlockIcon(kind: instance.icon)
                .frame(width: size, height: size)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 3).fill(hover ? Theme.panel2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(T("更换图标", "Change icon"))
        .popover(isPresented: $show, arrowEdge: .bottom) {
            IconPicker(instance: instance) { show = false }
        }
    }
}

/// 图标选择器，外观仿照游戏里的背包界面
struct IconPicker: View {
    let instance: McInstance
    let done: () -> Void
    @PState private var textures = BlockTextures.shared
    @PState private var custom = ""
    @PState private var error: String?
    @PState private var checking = false

    // 游戏界面的配色
    private let guiBG = Color(hex: 0xC6C6C6)
    private let guiLight = Color.white
    private let guiDark = Color(hex: 0x555555)
    private let guiText = Color(hex: 0x404040)

    var body: some View {
        let current = instance.setup.icon
        let choices = BlockTextures.picker.filter { !textures.missing.contains($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("选择图标", "Choose an icon")).font(.system(size: 13, weight: .semibold)).foregroundStyle(guiText)
                Spacer()
                Button(T("恢复默认", "Use default")) { save(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(current == nil ? guiText.opacity(0.4) : guiText)
                    .disabled(current == nil)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 0), count: 9), spacing: 0) {
                ForEach(choices, id: \.self) { kind in
                    Slot(kind: kind, selected: kind == (current ?? instance.defaultIcon)) { save(kind) }
                }
            }
            if textures.faces.isEmpty {
                Text(T("安装任意一个 1.13 或更新的版本后，这里会显示游戏里的方块材质。", "Install any version from 1.13 on to see the in-game block textures here."))
                    .font(.system(size: 11.5)).foregroundStyle(guiText).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(T("其他方块", "Another block")).font(.system(size: 12, weight: .medium)).foregroundStyle(guiText)
                HStack(spacing: 6) {
                    TextField(T("材质名，例如 diamond_ore", "Texture name, e.g. diamond_ore"), text: $custom)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(useCustom)
                    Button(T("使用", "Use"), action: useCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                }
                if let error {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(Color(hex: 0xA01818)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(width: 9 * 36 + 24)
        .background(guiBG)
        // 游戏界面的立体边框：左上亮、右下暗
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) { guiLight.frame(height: 2); Spacer() }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) { guiLight.frame(width: 2); Spacer() }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 0) { Spacer(); guiDark.frame(height: 2) }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 0) { Spacer(); guiDark.frame(width: 2) }
        }
        .environment(\.colorScheme, .light)
        .task { await BlockTextures.shared.ensure(BlockTextures.picker) }
    }

    private func useCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "minecraft:", with: "").replacingOccurrences(of: " ", with: "_")
        guard !name.isEmpty else { return }
        let kind = "block:" + name
        checking = true
        Task { @MainActor in
            defer { checking = false }
            if await BlockTextures.shared.exists(kind) {
                error = nil
                save(kind)
            } else if BlockTextures.shared.faces.isEmpty {
                error = T("还没有可用的游戏文件，先安装一个版本再试。", "No game files yet. Install a version first.")
            } else {
                error = T("游戏里没有名为 \(name) 的方块材质。", "There's no block texture named \(name) in the game.")
            }
        }
    }

    private func save(_ kind: String?) {
        var setup = instance.setup
        // 选中默认图标等同于恢复默认
        setup.icon = (kind == instance.defaultIcon) ? nil : kind
        LauncherSettings.shared.saveInstanceSetup(setup, instance.dir)
        AppState.shared.refreshInstances()
        done()
    }
}

/// 背包中的一个格子
private struct Slot: View {
    let kind: String
    let selected: Bool
    let action: () -> Void
    @PState private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Color(hex: 0x8B8B8B)
                BlockIcon(kind: kind).frame(width: 26, height: 26)
                if hover { Color.white.opacity(0.45) }
            }
            .frame(width: 36, height: 36)
            // 凹陷的格子：左上暗、右下亮
            .overlay(alignment: .topLeading) { VStack(spacing: 0) { Color(hex: 0x373737).frame(height: 1); Spacer() } }
            .overlay(alignment: .topLeading) { HStack(spacing: 0) { Color(hex: 0x373737).frame(width: 1); Spacer() } }
            .overlay(alignment: .bottomTrailing) { VStack(spacing: 0) { Spacer(); Color.white.frame(height: 1) } }
            .overlay(alignment: .bottomTrailing) { HStack(spacing: 0) { Spacer(); Color.white.frame(width: 1) } }
            .overlay { if selected { Rectangle().stroke(Color.white, lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(kind.hasPrefix("block:") ? String(kind.dropFirst(6)) : kind)
    }
}
