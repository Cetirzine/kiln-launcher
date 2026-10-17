import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import LauncherCore

// MARK: - 存档

struct WorldsView: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    @PState private var worlds: [InstanceManager.World] = []

    private var saves: URL { instance.gameDir.appendingPathComponent("saves") }

    var body: some View {
        Card(T("存档", "Worlds") + " · \(worlds.count)", trailing: AnyView(HStack(spacing: 6) {
            Button(T("导入…", "Import…")) { importWorld() }.buttonStyle(.kiln)
            IconButton(systemImage: "folder", help: T("打开文件夹", "Open folder")) { openFolder(saves) }
        })) {
            if worlds.isEmpty {
                Text(T("还没有存档", "No worlds yet")).font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.vertical, 8)
            }
            VStack(spacing: 0) {
                ForEach(worlds) { w in
                    HStack(spacing: 12) {
                        Group {
                            if let icon = w.icon, let img = NSImage(contentsOf: icon) {
                                Image(nsImage: img).resizable().interpolation(.none)
                            } else {
                                BlockIcon(kind: "grass_block")
                            }
                        }
                        .frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(T("上次游玩：", "Last played: ") + w.lastPlayed.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Button(T("进入", "Play")) {
                            state.select(instance)
                            state.launchSelected(options: LaunchOptions(world: w.name))
                        }
                        .buttonStyle(.kilnPrimary)
                        .disabled(!instance.supportsQuickPlay || state.isLaunching)
                        .help(instance.supportsQuickPlay ? T("启动游戏并直接进入这个存档", "Launch the game straight into this world")
                                                         : T("Minecraft 1.20 及以上才能直接进入存档", "Jumping straight into a world needs Minecraft 1.20 or later"))
                        Button(T("导出…", "Export…")) { export(w) }.buttonStyle(.kiln)
                        IconButton(systemImage: "folder", help: T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.open(w.url) }
                        IconButton(systemImage: "trash", help: T("删除", "Delete")) { delete(w) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.fileRevision) { _, _ in reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            dropFiles(providers) { url in if url.pathExtension.lowercased() == "zip" { importFile(url) } }
        }
    }

    private func reload() { worlds = InstanceManager.worlds(instance) }

    private func importWorld() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.message = T("选择存档压缩包（.zip）", "Choose a world archive (.zip)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    private func importFile(_ url: URL) {
        do {
            let name = try InstanceManager.importWorld(url, into: instance)
            Hint.show(T("已导入存档 \(name)", "Imported world \(name)"), .green)
            reload()
        } catch { Hint.show(error.friendly, .red) }
    }

    private func export(_ w: InstanceManager.World) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(w.name).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        JobCenter.shared.start(T("导出存档 \(w.name)", "Export world \(w.name)")) { _ in
            try await Task.detached { try InstanceManager.exportWorld(w, to: url) }.value
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func delete(_ w: InstanceManager.World) {
        Task {
            let r = await MsgBox.show(title: T("删除存档", "Delete world"),
                                      content: T("确定要删除存档 \(w.name) 吗？存档会被移到废纸篓。", "Delete the world \(w.name)? It will be moved to the Trash."),
                                      buttons: [T("删除", "Delete"), T("取消", "Cancel")], warn: true)
            guard r == 1 else { return }
            NSWorkspace.shared.recycle([w.url]) { _, _ in Task { @MainActor in reload() } }
        }
    }
}

// MARK: - 资源包 / 光影

struct PacksView: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    let type: Modrinth.ProjectType
    @PState private var files: [URL] = []

    private var dir: URL { instance.gameDir.appendingPathComponent(type.folder) }

    var body: some View {
        Card(type.title + " · \(files.count)", trailing: AnyView(HStack(spacing: 6) {
            Button(T("添加文件…", "Add files…")) { addFiles() }.buttonStyle(.kiln)
            Button(T("下载\(type.title)", "Download \(type.title.lowercased())")) {
                state.subPage = nil
                state.page = .download
                state.downloadSection = type == .shader ? .shader : .resourcepack
                ResourceSearchPage.targetInstance = instance.name
            }.buttonStyle(.kiln)
            IconButton(systemImage: "folder", help: T("打开文件夹", "Open folder")) { openFolder(dir) }
        })) {
            if type == .shader && !instance.loaders.contains(where: { ["Fabric", "Quilt", "OptiFine", "NeoForge", "Forge"].contains($0) }) {
                Text(T("光影需要 Iris（Fabric / Quilt）、Oculus（Forge）或 OptiFine。", "Shaders need Iris (Fabric / Quilt), Oculus (Forge) or OptiFine."))
                    .font(.system(size: 12)).foregroundStyle(Theme.yellow)
            }
            if files.isEmpty {
                Text(T("还没有\(type.title)，可以把文件拖到这里", "No \(type.title.lowercased()) yet. You can drop files here."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.vertical, 8)
            }
            VStack(spacing: 0) {
                ForEach(files, id: \.self) { f in
                    ListItem(systemIcon: type == .shader ? "sun.max.fill" : "photo.stack.fill", title: f.deletingPathExtension().lastPathComponent,
                             info: fileInfo(f)) {
                        HStack(spacing: 4) {
                            IconButton(systemImage: "magnifyingglass", help: T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                            IconButton(systemImage: "trash", help: T("删除", "Delete")) {
                                NSWorkspace.shared.recycle([f]) { _, _ in Task { @MainActor in reload() } }
                            }
                        }
                    }
                }
            }
            if type == .resourcepack && !files.isEmpty {
                Text(T("在游戏的“选项 → 资源包”中启用。", "Enable them in the game under Options → Resource Packs."))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.fileRevision) { _, _ in reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in dropFiles(providers) { copyIn($0) } }
    }

    private func fileInfo(_ f: URL) -> String {
        let isDir = (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir { return T("文件夹", "Folder") }
        let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Job.formatSize(Double(size))
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        files = urls.filter { !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasSuffix(".txt") }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(copyIn)
    }

    private func copyIn(_ url: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest) } catch { Hint.show(error.friendly, .red) }
        reload()
    }
}

// MARK: - 截图

struct ScreenshotsView: View {
    @Environment(AppState.self) private var state
    let instance: McInstance
    @PState private var shots: [URL] = []

    private var dir: URL { instance.gameDir.appendingPathComponent("screenshots") }

    var body: some View {
        Card(T("截图", "Screenshots") + " · \(shots.count)", trailing: AnyView(
            IconButton(systemImage: "folder", help: T("打开文件夹", "Open folder")) { openFolder(dir) }
        )) {
            if shots.isEmpty {
                Text(T("还没有截图，在游戏中按 F2 截图", "No screenshots yet. Press F2 in game to take one."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.vertical, 8)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(shots, id: \.self) { url in
                    Thumbnail(url: url)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.stroke))
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .help(url.lastPathComponent)
                        .contextMenu {
                            Button(T("打开", "Open")) { NSWorkspace.shared.open(url) }
                            Button(T("拷贝图片", "Copy image")) {
                                if let img = NSImage(contentsOf: url) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.writeObjects([img])
                                    Hint.show(T("已复制！", "Copied!"), .green)
                                }
                            }
                            Button(T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button(T("删除", "Delete"), role: .destructive) {
                                NSWorkspace.shared.recycle([url]) { _, _ in Task { @MainActor in reload() } }
                            }
                        }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.fileRevision) { _, _ in reload() }
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        shots = urls.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
    }
}

/// 缩略图（异步生成，不加载原图）
struct Thumbnail: View {
    let url: URL
    @PState private var image: NSImage?
    var body: some View {
        ZStack {
            Theme.panel2
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        }
        .task(id: url) {
            let url = url
            image = await Task.detached {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                           kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
        }
    }
}

// MARK: - 重命名 / 复制

struct InstanceNameSheet: View {
    enum Mode { case rename, duplicate }
    let instance: McInstance
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @PState private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .rename ? T("重命名版本", "Rename instance") : T("复制版本", "Duplicate instance"))
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            if mode == .duplicate {
                Text(T("复制版本文件夹（包括 Mod、存档与设置）。在 APFS 磁盘上为写时复制，几乎不占用额外空间。",
                       "Copies the instance folder, including mods, worlds and settings. On APFS the copy shares storage until files change."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            TextField(T("名称", "Name"), text: $name).textFieldStyle(.roundedBorder).onSubmit(commit)
            if let warn {
                Text(warn).font(.system(size: 11.5)).foregroundStyle(Theme.red)
            }
            HStack {
                Spacer()
                Button(T("取消", "Cancel")) { dismiss() }.buttonStyle(.kiln)
                Button(mode == .rename ? T("重命名", "Rename") : T("复制", "Duplicate"), action: commit)
                    .buttonStyle(.kilnPrimary).disabled(warn != nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { name = mode == .rename ? instance.name : instance.name + T(" 副本", " copy") }
    }

    private var finalName: String { name.trimmingCharacters(in: .whitespaces) }
    private var warn: String? {
        if mode == .rename && finalName == instance.name { return nil }
        return InstanceManager.validateName(finalName, folder: instance.folder)
    }

    private func commit() {
        guard warn == nil else { return }
        if mode == .rename && finalName == instance.name { dismiss(); return }
        do {
            switch mode {
            case .rename:
                try InstanceManager.rename(instance, to: finalName)
                AppState.shared.subPage = nil
                Hint.show(T("已重命名为 \(finalName)", "Renamed to \(finalName)"), .green)
            case .duplicate:
                try InstanceManager.duplicate(instance, as: finalName)
                Hint.show(T("已复制为 \(finalName)", "Duplicated as \(finalName)"), .green)
            }
            AppState.shared.refreshInstances()
            dismiss()
        } catch { Hint.show(error.friendly, .red) }
    }
}

struct NameSheetItem: Identifiable {
    let mode: InstanceNameSheet.Mode
    var id: String { mode == .rename ? "rename" : "duplicate" }
}

// MARK: - 工具

@MainActor
func openFolder(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.open(url)
}

/// 处理拖入的文件
@MainActor
func dropFiles(_ providers: [NSItemProvider], _ handle: @escaping @MainActor (URL) -> Void) -> Bool {
    for p in providers {
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in handle(url) }
        }
    }
    return !providers.isEmpty
}
