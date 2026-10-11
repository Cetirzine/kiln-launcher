import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

/// 要安装的整合包：本地文件，或 Modrinth / CurseForge 上的某个版本
enum ModpackSource: Identifiable {
    case file(URL)
    case remote(Modrinth.Version, Modrinth.Project)
    var id: String {
        switch self {
        case .file(let u): return u.path
        case .remote(let v, _): return v.id
        }
    }
}

enum ModpackActions {
    /// 选择本地整合包文件
    @MainActor
    static func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mrpack") ?? .zip, .zip]
        panel.allowsMultipleSelection = false
        panel.message = T("选择 Modrinth（.mrpack）或 CurseForge（.zip）整合包", "Choose a Modrinth (.mrpack) or CurseForge (.zip) modpack")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppState.shared.modpackInstall = .file(url)
    }
}

/// 安装整合包：先显示整合包信息，确认名称后安装
struct ModpackInstallSheet: View {
    let source: ModpackSource
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @PState private var file: URL?
    @PState private var info: Modpack.Info?
    @PState private var error: String?
    @PState private var name = ""
    @PState private var downloading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("安装整合包", "Install modpack")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            if let info {
                HStack(alignment: .top, spacing: 12) {
                    if case .remote(_, let p) = source {
                        AsyncImage(url: p.iconURL) { $0.resizable() } placeholder: { Theme.panel2 }
                            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "shippingbox.fill").font(.system(size: 26)).foregroundStyle(Theme.text2).frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(info.name) \(info.version)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        if !info.summary.isEmpty {
                            Text(info.summary).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                        }
                        HStack(spacing: 6) {
                            Badge(text: "Minecraft \(info.gameVersion)", color: Theme.text2)
                            Badge(text: info.loader.map { "\($0.kind) \($0.version)" } ?? T("原版", "Vanilla"), color: Theme.text2)
                            Badge(text: T("\(info.fileCount) 个文件", "\(info.fileCount) files"), color: Theme.text2)
                            Badge(text: info.format.rawValue, color: Theme.text2)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("版本名称", "Instance name")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                    TextField(info.name, text: $name).textFieldStyle(.roundedBorder)
                    if let warn = nameWarning {
                        Text(warn).font(.system(size: 11.5)).foregroundStyle(Theme.red)
                    }
                }
                Text(T("整合包会安装为使用独立游戏目录的新版本。", "The modpack is installed as a new instance with its own game directory."))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            } else if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(downloading ? T("正在下载整合包……", "Downloading the modpack…") : T("正在读取……", "Reading…"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            HStack {
                Spacer()
                Button(T("取消", "Cancel")) { dismiss() }.buttonStyle(.kiln)
                Button(T("安装", "Install")) { install() }.buttonStyle(.kilnPrimary)
                    .disabled(info == nil || nameWarning != nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .task { await load() }
    }

    private var finalName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameWarning: String? {
        InstanceManager.validateName(finalName, folder: LauncherSettings.shared.minecraftURL)
    }

    private func load() async {
        do {
            switch source {
            case .file(let u):
                file = u
            case .remote(let v, let p):
                downloading = true
                let dest = Paths.cache.appendingPathComponent("modpacks/\(v.fileName)")
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                var item = DownloadItem(url: v.fileURL, destination: dest, sha1: v.sha1, size: v.size)
                if p.source == .curseforge { item.urls = CurseForge.downloadURLs(v) }
                try await Downloader.run([item], job: nil)
                downloading = false
                file = dest
            }
            guard let file else { return }
            let i = try Modpack.inspect(file)
            info = i
            // 默认名称：整合包名称，重名时加序号
            let folder = LauncherSettings.shared.minecraftURL
            var n = i.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let base = n
            var k = 2
            while InstanceManager.validateName(n, folder: folder) != nil && k < 100 { n = "\(base) (\(k))"; k += 1 }
            name = n
        } catch {
            self.error = error.friendly
        }
    }

    private func install() {
        guard let file, let info else { return }
        let name = finalName
        let folder = LauncherSettings.shared.minecraftURL
        JobCenter.shared.start(T("安装整合包 \(info.name)", "Install modpack \(info.name)")) { job in
            let manual = try await Modpack.install(file, name: name, folder: folder, job: job)
            AppState.shared.refreshInstances()
            LauncherSettings.shared.selectedInstance = name
            if !manual.isEmpty { AppState.shared.manualDownloads = manual }
        }
        state.page = .download
        state.downloadSection = .manager
        dismiss()
    }
}

/// 需要手动下载的文件：打开下载页后，自动从“下载”文件夹中取回
struct ManualDownloadsSheet: View {
    @Environment(AppState.self) private var state
    @PState private var remaining: [Modpack.ManualFile] = []
    @PState private var total = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("还有 \(remaining.count) 个文件需要手动下载", "\(remaining.count) files need to be downloaded manually"))
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            Text(T("这些文件的作者不允许第三方启动器下载。点击“下载”打开 CurseForge 页面下载，Kiln 会自动从“下载”文件夹取回并放到正确位置。",
                   "The authors of these files don't allow third-party launchers to download them. Click Download to open the CurseForge page; Kiln picks the file up from your Downloads folder and moves it into place."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(remaining) { m in
                    ListItem(systemIcon: "arrow.down.doc", title: m.title, info: m.fileName) {
                        Button(T("下载", "Download")) { Links.open(m.pageURL) }.buttonStyle(.kiln)
                    }
                }
            }
            if remaining.isEmpty {
                Label(T("全部文件已就位", "All files are in place"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.green)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(T("正在等待下载……（\(total - remaining.count)/\(total)）", "Waiting for downloads… (\(total - remaining.count)/\(total))"))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
            }
            HStack {
                if remaining.count > 1 {
                    Button(T("全部打开", "Open all")) { remaining.forEach { Links.open($0.pageURL) } }.buttonStyle(.kiln)
                }
                Spacer()
                Button(remaining.isEmpty ? T("完成", "Done") : T("稍后再说", "Later")) { state.manualDownloads = [] }
                    .buttonStyle(remaining.isEmpty ? .kilnPrimary : .kiln)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { remaining = state.manualDownloads; total = remaining.count }
        .task {
            // 每 2 秒检查一次“下载”文件夹
            while !Task.isCancelled && !remaining.isEmpty {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let before = remaining.count
                let left = await Task.detached { [remaining] in Modpack.collectManualDownloads(remaining) }.value
                remaining = left
                if left.count < before { Hint.show(T("已放入 \(before - left.count) 个文件", "Moved \(before - left.count) file(s) into place"), .green) }
            }
        }
    }
}

/// 导出整合包（.mrpack）
struct ModpackExportSheet: View {
    let instance: McInstance
    @Environment(\.dismiss) private var dismiss
    @PState private var name = ""
    @PState private var version = "1.0.0"
    @PState private var summary = ""
    @PState private var items: [Modpack.ExportItem] = []
    @PState private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("导出整合包", "Export modpack")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(T("名称", "Name")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    TextField(instance.name, text: $name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(T("版本", "Version")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    TextField("1.0.0", text: $version).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(T("简介", "Summary")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    TextField(T("可选", "Optional"), text: $summary).textFieldStyle(.roundedBorder)
                }
            }
            Text(T("包含的内容", "Include")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            PageScroll {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { selected.contains(item.path) },
                                                     set: { if $0 { selected.insert(item.path) } else { selected.remove(item.path) } }))
                                .toggleStyle(.checkbox).labelsHidden()
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc").foregroundStyle(Theme.text2).frame(width: 18)
                            Text(item.path).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                            if !item.suggested {
                                Text(T("个人数据", "Personal")).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            Text(Job.formatSize(Double(item.size))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text3)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6)
                    }
                }
            }
            .frame(height: 220)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 3))
            Text(T("在 Modrinth 上能找到的 Mod、资源包与光影只记录下载地址，不打包文件本身；其余文件直接打包。",
                   "Mods, resource packs and shaders found on Modrinth are referenced by download link instead of being packed; everything else is packed."))
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(T("取消", "Cancel")) { dismiss() }.buttonStyle(.kiln)
                Button(T("导出…", "Export…")) { export() }.buttonStyle(.kilnPrimary).disabled(selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            name = instance.name
            items = Modpack.exportItems(instance)
            selected = Set(items.filter(\.suggested).map(\.path))
        }
    }

    private func export() {
        let panel = NSSavePanel()
        let packName = name.trimmingCharacters(in: .whitespaces).isEmpty ? instance.name : name.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = "\(packName)-\(version).mrpack"
        panel.allowedContentTypes = [UTType(filenameExtension: "mrpack") ?? .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let instance = instance, include = selected, version = version, summary = summary
        JobCenter.shared.start(T("导出整合包 \(packName)", "Export modpack \(packName)"), silent: true) { job in
            let r = try await Modpack.export(instance, name: packName, version: version, summary: summary, include: include, to: url, job: job)
            Hint.show(T("已导出：\(r.linked) 个文件引用 Modrinth，\(r.embedded) 个文件已打包", "Exported: \(r.linked) files linked from Modrinth, \(r.embedded) packed"), .green)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        dismiss()
    }
}
