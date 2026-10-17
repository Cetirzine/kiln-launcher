import SwiftUI
import AppKit
import LauncherCore

/// 从其他启动器导入版本
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @PState private var candidates: [LauncherImport.Candidate] = []
    @PState private var selected: Set<String> = []
    @PState private var loading = true

    /// preview：截图时直接显示的候选项
    init(preview: [LauncherImport.Candidate]? = nil) {
        if let preview {
            _candidates = PState(initialValue: preview)
            _loading = PState(initialValue: false)
            _selected = PState(initialValue: Set(preview.prefix(1).map(\.id)))
        }
    }

    /// 已经导入过的来源目录
    private var imported: Set<String> { Set(state.instances.compactMap { $0.setup.importedFrom }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("从其他启动器导入", "Import from other launchers")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            Text(T("支持 Prism Launcher、MultiMC、PolyMC、CurseForge App，以及官方启动器中使用独立游戏目录的配置。Kiln 会重新安装同样的游戏与加载器，再复制 Mod、存档、资源包与设置；原来的文件不会改动。",
                   "Supports Prism Launcher, MultiMC, PolyMC, the CurseForge app, and official launcher profiles with their own game directory. Kiln installs the same game and loader, then copies mods, worlds, resource packs and settings. The original files aren't touched."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Group {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(T("正在查找……", "Looking…")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else if candidates.isEmpty {
                    Text(T("没有在本机找到其他启动器的版本。可以点“选择文件夹…”手动选择实例文件夹。", "No instances from other launchers were found on this Mac. Use “Choose folder…” to pick an instance folder."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    PageScroll {
                        ForEach(candidates) { c in row(c) }
                    }
                    .frame(height: min(CGFloat(candidates.count) * 50 + 4, 320))
                    .background(Theme.panel2.opacity(0.5))
                    .overlay(Rectangle().stroke(Theme.stroke))
                }
            }
            HStack {
                Button(T("选择文件夹…", "Choose folder…")) { chooseFolder() }.buttonStyle(.kiln)
                Spacer()
                Button(T("取消", "Cancel")) { dismiss() }.buttonStyle(.kiln)
                Button(selected.isEmpty ? T("导入", "Import") : T("导入（\(selected.count)）", "Import (\(selected.count))")) { start() }
                    .buttonStyle(.kilnPrimary)
                    .disabled(selected.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task {
            guard loading else { return }
            let found = await Task.detached { LauncherImport.discover() }.value
            candidates = found
            loading = false
        }
    }

    private func row(_ c: LauncherImport.Candidate) -> some View {
        let done = imported.contains(c.contentDir.path)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { selected.contains(c.id) }, set: { on in
                if on { selected.insert(c.id) } else { selected.remove(c.id) }
            }))
            .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if done { Badge(text: T("已导入", "Imported"), color: Theme.green) }
                }
                Text(details(c)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            Badge(text: c.source.rawValue, color: Theme.text2)
            IconButton(systemImage: "folder", help: T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([c.contentDir]) }
        }
        .padding(.horizontal, 10).frame(height: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func details(_ c: LauncherImport.Candidate) -> String {
        var parts = [c.summary]
        let mods = c.modCount, worlds = c.worldCount
        if mods > 0 { parts.append(T("\(mods) 个 Mod", "\(mods) mods")) }
        if worlds > 0 { parts.append(T("\(worlds) 个存档", "\(worlds) worlds")) }
        return parts.joined(separator: " · ")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = T("选择实例文件夹（包含 instance.cfg 或 minecraftinstance.json）", "Choose an instance folder (with instance.cfg or minecraftinstance.json)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let c = LauncherImport.inspect(folder: url) else {
            Hint.show(T("这个文件夹不是 Prism、MultiMC 或 CurseForge 的实例", "This folder isn't a Prism, MultiMC or CurseForge instance"), .red)
            return
        }
        if !candidates.contains(c) { candidates.insert(c, at: 0) }
        selected.insert(c.id)
    }

    private func start() {
        let folder = LauncherSettings.shared.minecraftURL
        var reserved: [String] = []
        for c in candidates where selected.contains(c.id) {
            // 同时导入多个时，名称不能互相冲突
            var name = LauncherImport.availableName(c.name, folder: folder)
            var i = 2
            let base = name
            while reserved.contains(name) { name = "\(base) (\(i))"; i += 1 }
            reserved.append(name)
            JobCenter.shared.start(T("导入 \(name)", "Import \(name)")) { job in
                try await LauncherImport.run(c, name: name, folder: folder, job: job)
                AppState.shared.refreshInstances()
            }
        }
        dismiss()
        state.subPage = nil
        state.page = .download
        state.downloadSection = .manager
    }
}
