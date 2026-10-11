import SwiftUI
import LauncherCore
import AppKit

// MARK: - 版本列表（网格）

struct InstancesPage: View {
    @Environment(AppState.self) private var state
    @PState private var settings = LauncherSettings.shared
    @PState private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(T("版本", "Instances"), subtitle: settings.minecraftFolder) {
                folderMenu
                Button(T("安装新版本", "Install a version")) { state.page = .download; state.downloadSection = .game }
                    .buttonStyle(.kiln)
                IconButton(systemImage: "folder", help: T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.open(settings.minecraftURL) }
            }
            SearchField(placeholder: T("按名称筛选", "Filter by name"), text: $search)
            .padding(.horizontal, 28).padding(.bottom, 14)

            columnHeader
            PageScroll {
                if state.loadingInstances && state.instances.isEmpty {
                    ProgressView().padding(40)
                } else if state.instances.isEmpty {
                    empty
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.0) { title, list in
                            HStack(spacing: 6) {
                                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                                Text("\(list.count)").font(.system(size: 12)).foregroundStyle(Theme.text3)
                            }
                            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 6)
                            ForEach(list) { InstanceRow(instance: $0) }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(T("名称", "Name")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 42)
            Text(T("运行方式", "Runs as")).frame(width: 150, alignment: .leading)
            Text(T("上次游玩", "Last played")).frame(width: 110, alignment: .leading)
            Color.clear.frame(width: 80, height: 1)
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        .padding(.horizontal, 28).padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("这个文件夹里还没有游戏版本", "There are no game versions in this folder yet"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Text(T("安装一个版本，或者在上方切换到已有的 Minecraft 文件夹。", "Install a version, or switch to an existing Minecraft folder above."))
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
            Button(T("安装新版本", "Install a version")) { state.page = .download; state.downloadSection = .game }.buttonStyle(.kilnPrimary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groups: [(String, [McInstance])] {
        let list = state.instances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let order: [(McInstance.Category, String)] = [
            (.modded, T("装有 Mod 加载器", "With a mod loader")), (.release, T("原版", "Vanilla")),
            (.snapshot, T("快照", "Snapshots")), (.old, T("远古版本", "Old alpha and beta")),
            (.aprilFool, T("愚人节版本", "April Fools")), (.error, T("无法识别", "Unrecognized")),
        ]
        return order.compactMap { cat, title in
            let l = list.filter { $0.category == cat }
            return l.isEmpty ? nil : (title, l)
        }
    }

    private var folderMenu: some View {
        Menu {
            ForEach([Paths.defaultMinecraft.path] + settings.extraFolders, id: \.self) { f in
                Button(f + (f == settings.minecraftFolder ? "  ✓" : "")) {
                    settings.minecraftFolder = f
                    state.refreshInstances()
                }
            }
            Divider()
            Button(T("添加游戏文件夹", "Add game folder") + "…") { addFolder() }
            if settings.extraFolders.contains(settings.minecraftFolder) {
                Button(T("从列表中移除当前文件夹", "Remove current folder from list")) {
                    settings.extraFolders.removeAll { $0 == settings.minecraftFolder }
                    settings.minecraftFolder = Paths.defaultMinecraft.path
                    state.refreshInstances()
                }
            }
        } label: {
            Label(T("文件夹", "Folders"), systemImage: "externaldrive")
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !settings.extraFolders.contains(url.path) && url.path != Paths.defaultMinecraft.path {
            settings.extraFolders.append(url.path)
        }
        settings.minecraftFolder = url.path
        state.refreshInstances()
    }
}

/// 版本列表中的一行
struct InstanceRow: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    @PState private var hover = false
    @PState private var iconPicker = false
    @PState private var nameSheet: InstanceNameSheet.Mode?
    @PState private var exporting = false

    var body: some View {
        let selected = state.selectedInstance == instance
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                BlockIcon(kind: instance.icon).frame(width: 28, height: 28)
                    .popover(isPresented: $iconPicker, arrowEdge: .trailing) {
                        IconPicker(instance: instance) { iconPicker = false }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name).font(.system(size: 13, weight: selected ? .semibold : .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if instance.category == .error {
                    Text("—").foregroundStyle(Theme.text3)
                } else if Arch.isAppleSilicon {
                    Badge(text: instance.preferredArch == "arm64" ? T("原生", "Native") : "Rosetta 2",
                          color: instance.preferredArch == "arm64" ? Theme.green : Theme.yellow)
                } else {
                    Text("Intel").foregroundStyle(Theme.text2)
                }
            }
            .font(.system(size: 12))
            .frame(width: 150, alignment: .leading)
            Text(lastPlayed).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 110, alignment: .leading)
            HStack(spacing: 4) {
                if hover && instance.category != .error {
                    Button(T("开始", "Play")) { state.select(instance); state.launchSelected() }.buttonStyle(.kilnPrimary)
                }
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 28).padding(.vertical, 8)
        .background(selected ? Theme.accentSoft : (hover ? Theme.panel2 : Color.clear))
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.text).frame(width: 2) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 68) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { state.subPage = .instanceSetup(instance) }
        .onTapGesture { state.select(instance) }
        .contextMenu {
            Button(T("开始游戏", "Play")) { state.select(instance); state.launchSelected() }
            Button(T("版本设置", "Instance settings")) { state.subPage = .instanceSetup(instance) }
            Button(T("更换图标…", "Change icon…")) { iconPicker = true }
            Divider()
            Button(T("重命名…", "Rename…")) { nameSheet = .rename }
            Button(T("复制…", "Duplicate…")) { nameSheet = .duplicate }
            Button(T("导出整合包…", "Export modpack…")) { exporting = true }
            Button(T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.open(instance.dir) }
            Divider()
            Button(T("删除…", "Delete…"), role: .destructive) { InstanceActions.delete(instance) }
        }
        .sheet(item: Binding(get: { nameSheet.map { NameSheetItem(mode: $0) } }, set: { nameSheet = $0?.mode })) { item in
            InstanceNameSheet(instance: instance, mode: item.mode)
        }
        .sheet(isPresented: $exporting) { ModpackExportSheet(instance: instance) }
    }

    private var detail: String {
        if let e = instance.error { return e }
        var parts = [instance.vanillaVersion]
        for l in instance.loaders { parts.append(instance.loaderVersion(l).map { "\(l) \($0)" } ?? l) }
        if MetalRenderer.isEnabled(instance) { parts.append("Metal") }
        // 名称就是版本号时，第二行改为显示版本类型
        if parts == [instance.name] {
            switch instance.category {
            case .release: return T("正式版", "Release")
            case .snapshot: return T("快照", "Snapshot")
            case .old: return T("远古版本", "Old alpha or beta")
            case .aprilFool: return T("愚人节版本", "April Fools")
            default: break
            }
        }
        return parts.joined(separator: "   ")
    }

    private var lastPlayed: String {
        guard let d = instance.setup.lastPlayed else { return T("从未", "Never") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: LauncherSettings.shared.language == .en ? "en" : (LauncherSettings.shared.language == .zhHant ? "zh-Hant" : "zh-Hans"))
        return f.localizedString(for: d, relativeTo: Date())
    }
}

enum InstanceActions {
    @MainActor
    static func delete(_ instance: McInstance) {
        Task { @MainActor in
            let r = await MsgBox.show(title: T("删除版本", "Delete instance"),
                                      content: T("确定要删除版本 \(instance.name) 吗？\n版本文件夹会被移到废纸篓，其中的存档与 Mod 也会一并移除（可从废纸篓恢复）。", "Delete instance \(instance.name)?\nThe instance folder, including its worlds and mods, will be moved to the Trash (you can restore it from there)."),
                                      buttons: [T("删除", "Delete"), T("取消", "Cancel")], warn: true)
            guard r == 1 else { return }
            // 移到废纸篓，可以恢复
            NSWorkspace.shared.recycle([instance.dir]) { _, error in
                Task { @MainActor in
                    if let error {
                        Hint.show(T("无法删除 \(instance.name)", "Couldn't delete \(instance.name)") + "：" + error.friendly, .red)
                    } else {
                        Hint.show(T("已删除 \(instance.name)", "Deleted \(instance.name)"), .green)
                        AppState.shared.subPage = nil
                        AppState.shared.refreshInstances()
                    }
                }
            }
        }
    }

    @MainActor
    static func completeFiles(_ instance: McInstance) {
        JobCenter.shared.start(T("补全文件：\(instance.name)", "Repair files: \(instance.name)")) { job in
            try await Installer.completeFiles(instance, job: job)
        }
    }
}

// MARK: - 版本设置

struct InstanceSetupPage: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    enum Tab: Hashable { case overview, mods, worlds, resourcepacks, shaders, screenshots, settings }
    @PState private var tab: Tab

    init(instance: McInstance, tab: Tab = .overview) {
        self.instance = instance
        _tab = PState(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(instance.name, subtitle: instance.description, back: { state.subPage = nil })
            HStack {
                SegmentBar(items: [(Tab.overview, T("概览", "Overview"), "square.grid.2x2"),
                                   (Tab.mods, "Mod", "puzzlepiece.extension"),
                                   (Tab.worlds, T("存档", "Worlds"), "globe"),
                                   (Tab.resourcepacks, T("资源包", "Resource packs"), "photo.stack"),
                                   (Tab.shaders, T("光影", "Shaders"), "sun.max"),
                                   (Tab.screenshots, T("截图", "Screenshots"), "camera"),
                                   (Tab.settings, T("设置", "Settings"), "slider.horizontal.3")], selection: $tab)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            PageScroll {
                Group {
                    switch tab {
                    case .overview: InstanceOverview(instance: instance)
                    case .mods: ModManager(instance: instance)
                    case .worlds: WorldsView(instance: instance)
                    case .resourcepacks: PacksView(instance: instance, type: .resourcepack)
                    case .shaders: PacksView(instance: instance, type: .shader)
                    case .screenshots: ScreenshotsView(instance: instance)
                    case .settings: InstanceSettingsForm(instance: instance)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}

struct InstanceOverview: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    @PState private var nameSheet: InstanceNameSheet.Mode?
    @PState private var exporting = false

    var body: some View {
        VStack(spacing: 14) {
            Card {
                HStack(spacing: 14) {
                    InstanceIconButton(instance: instance)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instance.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                        Text(instance.description).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        HStack(spacing: 6) {
                            Badge(text: "Java \(instance.javaMajor)+")
                            if Arch.isAppleSilicon {
                                Badge(text: instance.preferredArch == "arm64" ? "Apple Silicon" : "Rosetta 2",
                                      color: instance.preferredArch == "arm64" ? Theme.green : Theme.yellow)
                            }
                            if instance.isolated { Badge(text: T("独立游戏目录", "Separate game directory"), color: Theme.text2) }
                        }
                    }
                    Spacer()
                    Button { state.select(instance); state.subPage = nil; state.page = .home; state.launchSelected() } label: {
                        Label(T("开始游戏", "Play"), systemImage: "play.fill")
                    }
                    .buttonStyle(.kilnPrimary)
                }
            }
            if MetalRenderer.deviceSupported && instance.loaders.contains("Fabric") {
                MetalCard(instance: instance)
            }
            Card(T("文件夹", "Folders")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    folder(T("版本文件夹", "Version folder"), instance.dir)
                    folder(T("游戏目录", "Game directory"), instance.gameDir)
                    folder("Mods", instance.gameDir.appendingPathComponent("mods"))
                    folder(T("存档", "Worlds"), instance.gameDir.appendingPathComponent("saves"))
                    folder(T("资源包", "Resource packs"), instance.gameDir.appendingPathComponent("resourcepacks"))
                    folder(T("光影", "Shaders"), instance.gameDir.appendingPathComponent("shaderpacks"))
                    folder(T("截图", "Screenshots"), instance.gameDir.appendingPathComponent("screenshots"))
                    folder(T("崩溃报告", "Crash reports"), instance.gameDir.appendingPathComponent("crash-reports"))
                }
            }
            Card(T("管理", "Manage")) {
                HStack(spacing: 8) {
                    Button(T("重命名…", "Rename…")) { nameSheet = .rename }.buttonStyle(.kiln)
                    Button(T("复制…", "Duplicate…")) { nameSheet = .duplicate }.buttonStyle(.kiln)
                    Button(T("导出整合包…", "Export modpack…")) { exporting = true }.buttonStyle(.kiln)
                    Button(T("补全文件", "Repair files")) { InstanceActions.completeFiles(instance) }.buttonStyle(.kiln)
                    Button(T("导出启动脚本…", "Export launch script…")) {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "\(instance.name).command"
                        if panel.runModal() == .OK, let url = panel.url {
                            state.select(instance)
                            state.launchSelected(options: LaunchOptions(exportScript: url))
                        }
                    }.buttonStyle(.kiln)
                    Spacer()
                    Button(T("删除", "Delete")) { InstanceActions.delete(instance) }.buttonStyle(.kilnDanger)
                }
            }
        }
        .sheet(item: Binding(get: { nameSheet.map { NameSheetItem(mode: $0) } }, set: { nameSheet = $0?.mode })) { item in
            InstanceNameSheet(instance: instance, mode: item.mode)
        }
        .sheet(isPresented: $exporting) { ModpackExportSheet(instance: instance) }
    }

    private func folder(_ title: String, _ url: URL) -> some View {
        Button {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.kiln)
    }
}

/// 本地 Mod 管理：识别每个文件对应的 Mod（Modrinth / CurseForge），检查并安装更新
struct ModManager: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    struct ModFile: Identifiable, Hashable { let url: URL; var id: URL { url }
        var enabled: Bool { url.pathExtension == "jar" }
        var name: String { url.lastPathComponent.replacingOccurrences(of: ".disabled", with: "") }
    }
    @PState private var files: [ModFile] = []
    @PState private var search = ""
    /// 识别结果，按文件名（不含 .disabled）索引，启用 / 禁用后仍然有效
    @PState private var entries: [String: ModIndex.Entry] = [:]
    @PState private var updates: [String: ModIndex.Update] = [:]
    @PState private var identifying = false
    @PState private var checking = false
    @PState private var updating: Set<String> = []
    @PState private var checkedAt: Date?

    private var modsDir: URL { instance.gameDir.appendingPathComponent("mods") }
    private var loader: String? { instance.loaders.first { ["Fabric", "Forge", "NeoForge", "Quilt"].contains($0) } }

    var body: some View {
        Card(T("已安装的 Mod", "Installed mods") + " · \(files.count)",
             trailing: AnyView(HStack(spacing: 6) {
                 if checking || identifying {
                     ProgressView().controlSize(.small)
                     Text(identifying ? T("正在识别…", "Identifying…") : T("正在检查更新…", "Checking for updates…"))
                         .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                 } else {
                     Button(T("检查更新", "Check for updates")) { Task { await refresh(force: true) } }.buttonStyle(.kiln)
                 }
                 if !updates.isEmpty {
                     Button(T("全部更新（\(updates.count)）", "Update all (\(updates.count))")) { updateAll() }
                         .buttonStyle(.kilnPrimary).disabled(!updating.isEmpty)
                 }
                 Button(T("下载 Mod", "Download mods")) {
                     state.subPage = nil
                     state.page = .download
                     state.downloadSection = .mod
                     ResourceSearchPage.targetInstance = instance.name
                 }.buttonStyle(.kiln)
                 IconButton(systemImage: "folder", help: T("打开文件夹", "Open folder")) {
                     try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
                     NSWorkspace.shared.open(modsDir)
                 }
             })) {
            if !instance.isModded {
                Text(T("该版本没有安装 Mod 加载器，Mod 不会生效。", "This instance has no mod loader, so mods won't load.")).font(.system(size: 12)).foregroundStyle(Theme.yellow)
            }
            SearchField(placeholder: T("搜索", "Search"), text: $search)
            if files.isEmpty {
                Text(T("还没有安装 Mod", "No mods installed")).font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.vertical, 8)
            } else if let checkedAt, !checking {
                Text(updates.isEmpty
                     ? T("所有能识别的 Mod 都是最新版本（\(checkedAt.formatted(date: .omitted, time: .shortened)) 检查）", "All identified mods are up to date (checked \(checkedAt.formatted(date: .omitted, time: .shortened)))")
                     : T("\(updates.count) 个 Mod 可以更新", "\(updates.count) mods can be updated"))
                    .font(.system(size: 11.5)).foregroundStyle(updates.isEmpty ? Theme.text3 : Theme.green)
            }
            VStack(spacing: 0) {
                ForEach(visible) { f in row(f) }
            }
        }
        .task { reload(); await refresh(force: false) }
        // 游戏目录中的 Mod 变化后自动刷新
        .onChange(of: state.fileRevision) { _, _ in reload(); Task { await refresh(force: false) } }
    }

    private var visible: [ModFile] {
        files.filter { f in
            guard !search.isEmpty else { return true }
            let e = entries[f.name]
            return f.name.localizedCaseInsensitiveContains(search)
                || (e?.project?.title.localizedCaseInsensitiveContains(search) ?? false)
                || (e?.project.flatMap { ModNames.shared.chinese($0.slug) }?.contains(search) ?? false)
        }
        // 可更新的排在前面
        .sorted { (updates[$0.name] != nil ? 0 : 1, title($0).lowercased()) < (updates[$1.name] != nil ? 0 : 1, title($1).lowercased()) }
    }

    private func title(_ f: ModFile) -> String { entries[f.name]?.project?.title ?? f.name }

    private func row(_ f: ModFile) -> some View {
        let e = entries[f.name]
        let u = updates[f.name]
        return HStack(spacing: 12) {
            Group {
                if let icon = e?.project?.iconURL {
                    AsyncImage(url: icon) { $0.resizable().interpolation(.medium) } placeholder: { Theme.panel2 }
                } else {
                    Image(systemName: f.enabled ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
                        .font(.system(size: 14)).foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title(f)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if Localizer.shared.language != .en, let slug = e?.project?.slug, let zh = ModNames.shared.chinese(slug), zh != e?.project?.title {
                        Text(zh).font(.system(size: 11.5)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                    if !f.enabled { Text(T("已禁用", "Disabled")).font(.system(size: 11)).foregroundStyle(Theme.text3) }
                }
                Text(detail(f, e)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let u {
                if updating.contains(f.name) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(T("更新到 \(shortVersion(u.latest))", "Update to \(shortVersion(u.latest))")) { update([u]) }
                        .buttonStyle(.kiln).help(u.latest.fileName)
                }
            }
            Toggle("", isOn: Binding(get: { f.enabled }, set: { toggle(f, $0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            IconButton(systemImage: "trash", help: T("删除", "Delete")) {
                NSWorkspace.shared.recycle([f.url]) { _, _ in Task { @MainActor in reload() } }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(f.enabled ? 1 : 0.6)
        .contextMenu {
            if let p = e?.project {
                Button(T("在 \(e?.source?.rawValue ?? "") 查看", "View on \(e?.source?.rawValue ?? "")")) {
                    Links.open(p.pageURL ?? "https://modrinth.com/mod/\(p.slug)")
                }
            }
            Button(T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
        }
    }

    private func detail(_ f: ModFile, _ e: ModIndex.Entry?) -> String {
        guard let e, let v = e.version else { return f.name + (identifying ? "" : T("　·　未识别", " · not identified")) }
        return "\(shortVersion(v))　·　\(e.source?.rawValue ?? "")　·　\(f.name)"
    }

    private func shortVersion(_ v: Modrinth.Version) -> String {
        let n = v.number.isEmpty ? v.name : v.number
        return n.count > 24 ? String(n.prefix(24)) + "…" : n
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: modsDir, includingPropertiesForKeys: nil)) ?? []
        files = urls.filter { $0.pathExtension == "jar" || $0.lastPathComponent.hasSuffix(".jar.disabled") }
            .map(ModFile.init).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// 识别新文件，并检查更新
    private func refresh(force: Bool) async {
        guard !identifying && !checking, !files.isEmpty else { return }
        let names = Set(files.map(\.name))
        entries = entries.filter { names.contains($0.key) }
        updates = updates.filter { names.contains($0.key) }
        let unknown = files.filter { entries[$0.name] == nil }
        if !unknown.isEmpty {
            identifying = true
            let found = await ModIndex.identify(unknown.map(\.url))
            for (url, e) in found { entries[url.lastPathComponent.replacingOccurrences(of: ".disabled", with: "")] = e }
            identifying = false
        }
        guard force || checkedAt == nil || !unknown.isEmpty else { return }
        checking = true
        let list = files.compactMap { f in entries[f.name].map { ModIndex.Entry(file: f.url, sha1: $0.sha1, project: $0.project, version: $0.version) } }
        let found = await ModIndex.updates(list, gameVersion: instance.vanillaVersion, loader: loader)
        updates = Dictionary(found.map { ($0.file.lastPathComponent.replacingOccurrences(of: ".disabled", with: ""), $0) }, uniquingKeysWith: { a, _ in a })
        checking = false
        checkedAt = Date()
    }

    private func update(_ list: [ModIndex.Update]) {
        let keys = list.map { $0.file.lastPathComponent.replacingOccurrences(of: ".disabled", with: "") }
        updating.formUnion(keys)
        let title = list.count == 1 ? (list[0].project?.title ?? list[0].latest.fileName) : T("\(list.count) 个 Mod", "\(list.count) mods")
        JobCenter.shared.start(T("更新 \(title)", "Update \(title)")) { job in
            defer {
                updating.subtract(keys)
                for k in keys { updates[k] = nil; entries[k] = nil }
                reload()
                Task { await refresh(force: false) }
            }
            job.enter(title, index: 0, of: 1)
            for u in list { try await ModIndex.apply(u, job: job) }
        }
    }

    private func updateAll() { update(Array(updates.values)) }

    private func toggle(_ f: ModFile, _ on: Bool) {
        let target = on ? f.url.deletingPathExtension() : f.url.appendingPathExtension("disabled")
        try? FileManager.default.moveItem(at: f.url, to: target)
        reload()
    }
}

/// 版本独立设置
struct InstanceSettingsForm: View {
    let instance: McInstance
    @Environment(AppState.self) private var state
    @PState private var store = AccountStore.shared
    @PState private var setup = LauncherSettings.InstanceSetup()
    @PState private var javas: [JavaInfo] = []
    @PState private var loaded = false

    var body: some View {
        VStack(spacing: 14) {
            Card(T("游戏", "Game")) {
                SettingRow(title: T("独立游戏目录", "Separate game directory"),
                           help: T("存档、Mod、资源包与设置保存在版本文件夹中", "Worlds, mods, resource packs and options are kept inside the instance folder")) {
                    Toggle("", isOn: Binding(get: { setup.isolation ?? instance.isolated }, set: { setup.isolation = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                }
                SettingRow(title: T("账号", "Account"),
                           help: T("固定后，启动该版本时总是使用这个账号，不受右上角切换影响", "When pinned, this instance always launches with this account, whatever is selected in the top-right corner")) {
                    Picker("", selection: Binding(get: { store.account(id: setup.account)?.id ?? "" },
                                                  set: { setup.account = $0.isEmpty ? nil : $0 })) {
                        Text(T("使用当前账号", "Use the current account")).tag("")
                        ForEach(store.accounts) { Text("\($0.name)（\($0.typeText)）").tag($0.id) }
                    }
                    .labelsHidden().frame(maxWidth: 320)
                }
                SettingRow(title: "Java") {
                    Picker("", selection: Binding(get: { setup.javaPath ?? "" }, set: { setup.javaPath = $0.isEmpty ? nil : $0 })) {
                        Text(T("跟随全局设置", "Use global setting")).tag("")
                        ForEach(javas) { Text($0.displayName).tag($0.path) }
                    }
                    .labelsHidden().frame(maxWidth: 320)
                }
                SettingRow(title: T("内存", "Memory"), help: T("拖到最左侧则跟随全局设置", "Drag fully left to use the global setting")) {
                    Slider(value: Binding(get: { setup.memoryGB ?? 0 }, set: { setup.memoryGB = $0 < 0.5 ? nil : ($0 * 2).rounded() / 2 }),
                           in: 0...maxMemory)
                        .frame(maxWidth: 260)
                    Text(setup.memoryGB.map { String(format: "%.1f GB", $0) } ?? T("跟随全局设置", "Use global setting"))
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2).frame(width: 90, alignment: .leading)
                }
                SettingRow(title: T("自动进入服务器", "Auto-join server"), help: T("启动后直接进入该服务器", "Join this server right after launching")) {
                    TextField("mc.example.com:25565", text: bind(\.serverEnter)).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                }
                SettingRow(title: T("版本类型文字", "Version type text")) {
                    TextField(T("跟随全局设置", "Use global setting"), text: bind(\.customInfo)).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                }
            }
            Card(T("高级", "Advanced")) {
                SettingRow(title: T("额外 JVM 参数", "Extra JVM arguments")) {
                    TextField(T("跟随全局设置", "Use global setting"), text: bind(\.jvmArgs)).textFieldStyle(.roundedBorder)
                }
                SettingRow(title: T("额外游戏参数", "Extra game arguments")) {
                    TextField(T("跟随全局设置", "Use global setting"), text: bind(\.gameArgs)).textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear {
            setup = instance.setup
            loaded = true
            Task { javas = await JavaManager.search() }
        }
        .onChange(of: setup) { _, new in
            if loaded {
                LauncherSettings.shared.saveInstanceSetup(new, instance.dir)
                state.pinRevision += 1
            }
        }
        // 在右上角账号菜单中固定 / 取消固定时同步
        .onChange(of: state.pinRevision) { _, _ in
            let current = instance.setup.account
            if setup.account != current { setup.account = current }
        }
    }

    private var maxMemory: Double { max(2, Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024 * 0.75).rounded() }

    private func bind(_ kp: WritableKeyPath<LauncherSettings.InstanceSetup, String?>) -> Binding<String> {
        Binding(get: { setup[keyPath: kp] ?? "" }, set: { setup[keyPath: kp] = $0.isEmpty ? nil : $0 })
    }
}

// MARK: - 游戏日志

struct GameLogPage: View {
    @Environment(AppState.self) private var state
    let game: GameProcess
    @PState private var follow = true
    @PState private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(T("游戏日志", "Game log"), subtitle: game.instanceName, back: { state.subPage = nil }) {
                SearchField(placeholder: T("搜索", "Search"), text: $filter).frame(width: 180)
                Toggle(T("自动滚动", "Auto scroll"), isOn: $follow).toggleStyle(.checkbox)
                IconButton(systemImage: "doc.on.doc", help: T("复制", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(game.lines.joined(separator: "\n"), forType: .string)
                    Hint.show(T("已复制！", "Copied!"), .green)
                }
                if let f = game.logFile {
                    IconButton(systemImage: "doc.text.magnifyingglass", help: T("打开日志文件", "Open log file")) { NSWorkspace.shared.open(f) }
                }
                if game.state == .running || game.state == .starting {
                    Button(T("结束进程", "Kill")) { game.kill() }.buttonStyle(.kilnDanger)
                }
            }
            ScrollViewReader { proxy in
                PageScroll {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(color(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(14)
                }
                .background(Color(hex: 0x161615), in: RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 24).padding(.bottom, 24)
                .onChange(of: game.lines.count) { _, _ in
                    if follow, !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private var lines: [String] {
        filter.isEmpty ? game.lines : game.lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private func color(_ line: String) -> Color {
        if line.contains("ERROR") || line.contains("Exception") || line.contains("FATAL") { return Color(hex: 0xff7b7b) }
        if line.contains("WARN") { return Color(hex: 0xf5c04f) }
        return Color(hex: 0xd6dbe6)
    }
}

/// MetalUniversal 渲染开关
struct MetalCard: View {
    let instance: McInstance
    @PState private var enabled = false
    @PState private var available: Bool?
    @PState private var busy = false

    var body: some View {
        Card(T("Metal 渲染", "Metal rendering")) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.horizontal.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("使用 MetalUniversal 以 Apple Metal 渲染游戏（实验性）。需要 Fabric，启用后在视频设置中选择“Prefer Metal”。",
                           "Render with Apple Metal via MetalUniversal (experimental). Requires Fabric; choose \"Prefer Metal\" in Video Settings."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if available == false && !enabled {
                        Text(T("MetalUniversal 暂不支持 Minecraft \(instance.vanillaVersion)。", "MetalUniversal doesn't support Minecraft \(instance.vanillaVersion) yet."))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.yellow)
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { enabled }, set: { toggle($0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(busy || (available == false && !enabled))
            }
        }
        .task {
            enabled = MetalRenderer.isEnabled(instance)
            available = !((try? await MetalRenderer.versions(game: instance.vanillaVersion)) ?? []).isEmpty
        }
    }

    private func toggle(_ on: Bool) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                if on { try await MetalRenderer.enable(instance, job: nil) } else { try MetalRenderer.disable(instance) }
                enabled = MetalRenderer.isEnabled(instance)
                Hint.show(on ? T("已启用 Metal 渲染", "Metal rendering enabled") : T("已关闭 Metal 渲染", "Metal rendering disabled"), .green)
            } catch {
                Hint.show(error.friendly, .red)
            }
        }
    }
}
