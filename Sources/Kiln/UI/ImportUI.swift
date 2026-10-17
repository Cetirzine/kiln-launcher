import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

/// 从其他启动器导入版本
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(\.snapshotMode) private var snapshot
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
                Button(T("选择文件夹或压缩包…", "Choose folder or archive…")) { chooseFolder() }.buttonStyle(.kiln)
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
        .onAppear {
            if let url = state.importFile { state.importFile = nil; add(url) }
        }
        .modifier(FileDrop(enabled: !snapshot) { add($0) })
        .task {
            guard loading else { return }
            let found = await Task.detached { LauncherImport.discover() }.value
            candidates = candidates.filter { $0.temporary != nil || !found.contains($0) } + found
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
            .disabled(c.unsupported != nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if done { Badge(text: T("已导入", "Imported"), color: Theme.green) }
                }
                if let reason = c.unsupported {
                    Text(reason).font(.system(size: 11.5)).foregroundStyle(Theme.red).lineLimit(1).help(reason)
                } else if let warning = c.warning {
                    Text(details(c) + " · " + warning).font(.system(size: 11.5)).foregroundStyle(Theme.yellow).lineLimit(1).help(warning)
                } else {
                    Text(details(c)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
                }
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
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip, UTType(filenameExtension: "mrpack") ?? .zip]
        panel.message = T("选择实例文件夹（包含 instance.cfg 或 minecraftinstance.json），或 Prism / MultiMC 导出的 .zip",
                          "Choose an instance folder (with instance.cfg or minecraftinstance.json), or a .zip exported from Prism / MultiMC")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url)
    }

    /// 加入一个文件夹或压缩包；整合包交给整合包安装
    private func add(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let c: LauncherImport.Candidate
        if isDir.boolValue {
            guard let found = LauncherImport.inspect(folder: url) else {
                Hint.show(T("这个文件夹不是 Prism、MultiMC 或 CurseForge 的实例", "This folder isn't a Prism, MultiMC or CurseForge instance"), .red)
                return
            }
            c = found
        } else if LauncherImport.isInstanceArchive(url) {
            do { c = try LauncherImport.inspect(archive: url) } catch { Hint.show(error.friendly, .red); return }
        } else if (try? Modpack.inspect(url)) != nil {
            dismiss()
            state.modpackInstall = .file(url)
            return
        } else {
            Hint.show(T("不是支持的实例或整合包", "Not a supported instance or modpack"), .red)
            return
        }
        if !candidates.contains(c) { candidates.insert(c, at: 0) }
        if let reason = c.unsupported { Hint.show(reason, .red) } else { selected.insert(c.id) }
    }

    private func start() {
        let folder = LauncherSettings.shared.minecraftURL
        var reserved: [String] = []
        for c in candidates where selected.contains(c.id) && c.unsupported == nil {
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

/// 接收拖进来的文件；离屏截图时不加（ImageRenderer 无法渲染拖放视图）
private struct FileDrop: ViewModifier {
    let enabled: Bool
    let handle: @MainActor (URL) -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], isTargeted: nil) { providers in dropFiles(providers, handle) }
        } else {
            content
        }
    }
}
