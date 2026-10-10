import SwiftUI
import LauncherCore
import AppKit

struct DownloadPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PageHeader(T("下载", "Download"))
            HStack {
                SegmentBar(items: [
                    (AppState.DownloadSection.game, T("游戏", "Game"), "cube.fill"),
                    (.mod, "Mod", "puzzlepiece.extension.fill"),
                    (.resourcepack, T("资源包", "Resource packs"), "photo.stack.fill"),
                    (.shader, T("光影", "Shaders"), "sun.max.fill"),
                    (.manager, T("任务", "Tasks"), "list.bullet.rectangle.fill"),
                ], selection: $state.downloadSection)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            Group {
                switch state.downloadSection {
                case .game: DownloadGamePage()
                case .mod: ResourceSearchPage(type: .mod).id("mod")
                case .resourcepack: ResourceSearchPage(type: .resourcepack).id("rp")
                case .shader: ResourceSearchPage(type: .shader).id("shader")
                case .manager: TaskManagerPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 游戏下载

struct DownloadGamePage: View {
    /// 从主页“最新版本”跳转过来时预先选中的版本
    @MainActor static var pendingVersion: String?

    @Environment(AppState.self) private var state
    @PState private var manifest: VersionManifest.Result?
    @PState private var error: String?
    @PState private var kind: McVersionKind = .release
    @PState private var search = ""
    @PState private var selected: RemoteVersion?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                HStack {
                    Picker("", selection: $kind) {
                        ForEach(McVersionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    TextField(T("搜索", "Search"), text: $search).textFieldStyle(.roundedBorder).frame(width: 150)
                }
                PageScroll {
                    LazyVStack(spacing: 2) {
                        if let error {
                            VStack(spacing: 8) {
                                Text(T("无法获取版本列表：", "Couldn't load the version list: ") + error).font(.system(size: 12)).foregroundStyle(Theme.red)
                                Button(T("重试", "Retry")) { Task { await load(force: true) } }.buttonStyle(.kiln)
                            }.padding(30)
                        } else if manifest == nil {
                            ProgressView().padding(40)
                        }
                        ForEach(list) { v in
                            ListItem(icon: v.kind.icon, title: v.id,
                                     info: v.releaseTime.formatted(date: .abbreviated, time: .omitted) + (installed(v) ? " · " + T("已安装", "Installed") : ""),
                                     selected: selected == v, action: { selected = v })
                        }
                    }
                    .padding(8)
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.stroke))
            }
            .frame(minWidth: 300)

            Group {
                if let v = selected {
                    InstallPanel(version: v).id(v.id)
                } else {
                    Card {
                        VStack(spacing: 10) {
                            BundleImage(name: "Grass").frame(width: 48, height: 48)
                            Text(T("在左侧选择一个版本", "Choose a version on the left")).font(.system(size: 13)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
            }
            .frame(width: 320)
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .task { await load(force: false) }
    }

    private var list: [RemoteVersion] {
        (manifest?.versions ?? []).filter { $0.kind == kind && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search)) }
    }

    private func installed(_ v: RemoteVersion) -> Bool { state.instances.contains { $0.name == v.id } }

    private func load(force: Bool) async {
        error = nil
        do {
            manifest = try await VersionManifest.fetch(force: force)
            if let p = DownloadGamePage.pendingVersion, let v = manifest?.versions.first(where: { $0.id == p }) {
                kind = v.kind
                selected = v
                DownloadGamePage.pendingVersion = nil
            }
        } catch {
            self.error = error.friendly
        }
    }
}

/// 安装面板：原版，或附带 Fabric / Quilt / Forge / NeoForge
struct InstallPanel: View {
    @Environment(AppState.self) private var state
    let version: RemoteVersion

    enum Loader: String, CaseIterable, Identifiable {
        case none, fabric = "Fabric", quilt = "Quilt", forge = "Forge", neoforge = "NeoForge"
        var id: String { rawValue }
        var title: String { self == .none ? T("无", "None") : rawValue }
        var icon: String {
            switch self {
            case .none: return ""
            case .fabric: return "Fabric"
            case .quilt: return "Quilt"
            case .forge: return "Anvil"
            case .neoforge: return "NeoForge"
            }
        }
    }

    @PState private var loader: Loader = .none
    @PState private var loaderVersions: [String] = []
    @PState private var loaderVersion = ""
    @PState private var loadingLoader = false
    @PState private var loaderError: String?
    @PState private var name = ""
    @PState private var withFabricApi = true
    @PState private var metalAvailable = false
    @PState private var withMetal = false

    var body: some View {
        Card(T("安装", "Install")) {
            HStack(spacing: 12) {
                BundleImage(name: loader == .none ? version.kind.icon : loader.icon).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minecraft \(version.id)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text(version.kind.title).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            Text(T("Mod 加载器", "Mod loader")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            Picker("", selection: $loader) {
                ForEach(Loader.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if loader != .none {
                if loadingLoader {
                    ProgressView().controlSize(.small)
                } else if let loaderError {
                    Text(loaderError).font(.system(size: 11.5)).foregroundStyle(Theme.red)
                } else if loaderVersions.isEmpty {
                    Text(T("没有适用于该版本的 \(loader.rawValue)", "No \(loader.rawValue) for this version")).font(.system(size: 12)).foregroundStyle(Theme.yellow)
                } else {
                    Picker(T("加载器版本", "Loader version"), selection: $loaderVersion) {
                        ForEach(loaderVersions, id: \.self) { Text($0).tag($0) }
                    }
                }
                if loader == .fabric {
                    Toggle(T("同时安装 Fabric API", "Also install Fabric API"), isOn: $withFabricApi).toggleStyle(.checkbox)
                }
            }
            if metalAvailable && loader == .fabric {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(T("启用 Metal 渲染（实验性）", "Enable Metal rendering (experimental)"), isOn: $withMetal).toggleStyle(.checkbox)
                    Text(T("安装 MetalUniversal，使用 Apple Metal 代替 OpenGL / Vulkan 渲染。", "Installs MetalUniversal to render with Apple Metal instead of OpenGL / Vulkan."))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(T("名称", "Name")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            TextField(defaultName, text: $name).textFieldStyle(.roundedBorder)
            if let warn = nameWarning {
                Text(warn).font(.system(size: 11.5)).foregroundStyle(Theme.red)
            }
            if Arch.isAppleSilicon { archNote }
            Button { install() } label: {
                Label(T("安装", "Install"), systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.kilnPrimary)
            .disabled(nameWarning != nil || (loader != .none && loaderVersion.isEmpty))
        }
        .onChange(of: loader) { _, _ in Task { await loadLoaders() } }
        .task {
            // 检查 MetalUniversal 是否支持该版本（仅 Apple 芯片）
            guard MetalRenderer.deviceSupported else { return }
            metalAvailable = !((try? await MetalRenderer.versions(game: version.id)) ?? []).isEmpty
        }
    }

    private var archNote: some View {
        // 根据发布时间预估 LWJGL 版本：1.13（2018-07）起为 LWJGL 3，1.19（2022-06）起自带 arm64 原生库
        let t = version.releaseTime
        let native = t >= ISO8601DateFormatter().date(from: "2022-06-01T00:00:00Z")!
        let patch = t >= ISO8601DateFormatter().date(from: "2018-07-01T00:00:00Z")!
        let nativeMode = LauncherSettings.shared.arm64Native
        let (text, color): (String, Color) = native
            ? (T("该版本可以在 Apple 芯片上原生运行。", "This version runs natively on Apple Silicon."), Theme.green)
            : nativeMode
                ? (patch ? T("将自动替换为 arm64 版 LWJGL，在 Apple 芯片上原生运行。", "LWJGL will be swapped for an arm64 build to run natively on Apple Silicon.")
                         : T("将使用 arm64 版 LWJGL 2 与 Java 8，在 Apple 芯片上原生运行。", "Runs natively on Apple Silicon with arm64 LWJGL 2 and Java 8."), Theme.green)
                : (T("将通过 Rosetta 2 运行。", "Runs through Rosetta 2."), Theme.yellow)
        return HStack(spacing: 6) {
            Image(systemName: color == Theme.green ? "bolt.fill" : "arrow.triangle.2.circlepath").foregroundStyle(color)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var defaultName: String { loader == .none ? version.id : "\(version.id)-\(loader.rawValue)" }

    private var finalName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? defaultName : n
    }

    private var nameWarning: String? {
        let n = finalName
        if n.contains("/") || n.contains(":") || n.contains("!") || n.hasPrefix(".") { return T("名称包含不允许的字符", "The name contains invalid characters") }
        if state.instances.contains(where: { $0.name == n }) { return T("已存在名为 \(n) 的版本", "An instance named \(n) already exists") }
        return nil
    }

    private func loadLoaders() async {
        loaderVersions = []
        loaderVersion = ""
        loaderError = nil
        guard loader != .none else { return }
        loadingLoader = true
        defer { loadingLoader = false }
        do {
            switch loader {
            case .fabric, .quilt:
                let list = try await ModLoaderKind(rawValue: loader.rawValue)!.versions(for: version.id)
                loaderVersions = list.map(\.version)
                loaderVersion = (list.first { $0.stable } ?? list.first)?.version ?? ""
            case .forge, .neoforge:
                let list = try await ForgeInstaller.versions(ForgeKind(rawValue: loader.rawValue)!, game: version.id)
                loaderVersions = list.map(\.version)
                loaderVersion = (list.first { !$0.isBeta } ?? list.first)?.version ?? ""
            case .none: break
            }
        } catch {
            loaderError = error.friendly
        }
    }

    private func install() {
        let name = finalName, version = version, loader = loader, loaderVersion = loaderVersion
        let folder = LauncherSettings.shared.minecraftURL
        let fabricApi = loader == .fabric && withFabricApi
        let metal = loader == .fabric && withMetal && metalAvailable
        JobCenter.shared.start(T("安装 \(name)", "Install \(name)")) { job in
            switch loader {
            case .none:
                try await Installer.install(version: version, name: name, loader: nil, folder: folder, job: job)
            case .fabric, .quilt:
                try await Installer.install(version: version, name: name, loader: (ModLoaderKind(rawValue: loader.rawValue)!, loaderVersion),
                                            folder: folder, job: job)
            case .forge, .neoforge:
                try await ForgeInstaller.install(ForgeKind(rawValue: loader.rawValue)!, version: loaderVersion, game: version,
                                                 name: name, folder: folder, job: job)
            }
            let instance = McInstance(folder: folder, name: name)
            if fabricApi, let v = try? await Modrinth.versions("P7dR8mSH", gameVersion: version.id, loader: "fabric").first {
                try? await Downloader.fetch(DownloadItem(url: v.fileURL, destination: instance.gameDir.appendingPathComponent("mods/\(v.fileName)"),
                                                         sha1: v.sha1, size: v.size))
            }
            if metal { try await MetalRenderer.enable(instance, job: nil) }
            AppState.shared.refreshInstances()
            LauncherSettings.shared.selectedInstance = name
        }
        state.downloadSection = .manager
    }
}

// MARK: - 社区资源（Modrinth）

struct ResourceSearchPage: View {
    @MainActor static var targetInstance: String?

    @Environment(AppState.self) private var state
    let type: Modrinth.ProjectType
    @PState private var query = ""
    @PState private var results: [Modrinth.Project] = []
    @PState private var loading = false
    @PState private var error: String?
    @PState private var target: String = ""
    @PState private var detail: Modrinth.Project?
    @PState private var searchTask: Task<Void, Never>?

    private var instance: McInstance? { state.instances.first { $0.name == target } }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3)
                    TextField(T("搜索\(type.title)", "Search \(type.title)"), text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { runSearch() }
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.stroke))
                Picker(T("安装到", "Install to"), selection: $target) {
                    Text(T("不限版本（另存为文件）", "Any version (save as file)")).tag("")
                    ForEach(state.instances.filter { $0.category != .error }) { Text($0.name).tag($0.name) }
                }
                .frame(width: 240)
            }
            PageScroll {
                LazyVStack(spacing: 0) {
                    if loading && results.isEmpty { ProgressView().padding(40) }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.red).padding() }
                    ForEach(results) { p in
                        ProjectRow(project: p).onTapGesture { detail = p }
                    }
                    if !results.isEmpty && results.count % 30 == 0 {
                        Button(T("加载更多", "Load more")) { runSearch(more: true) }.buttonStyle(.kiln).padding()
                    }
                }
            }
            Text(T("搜索结果来自 Modrinth", "Results from Modrinth")).font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .onAppear {
            if let t = ResourceSearchPage.targetInstance { target = t; ResourceSearchPage.targetInstance = nil }
            else if let s = state.selectedInstance, type != .mod || s.isModded { target = s.name }
            runSearch()
        }
        .onChange(of: target) { _, _ in runSearch() }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task { try? await Task.sleep(nanoseconds: 400_000_000); if !Task.isCancelled { runSearch() } }
        }
        .sheet(item: $detail) { p in ProjectVersionsSheet(project: p, type: type, instance: instance) }
    }

    private var loaderFilter: String? {
        guard type == .mod, let i = instance else { return nil }
        return i.loaders.first { $0 != "OptiFine" }
    }

    private func runSearch(more: Bool = false) {
        let offset = more ? results.count : 0
        let q = query, gv = instance?.vanillaVersion, lf = loaderFilter
        Task { @MainActor in
            loading = true
            error = nil
            defer { loading = false }
            do {
                let r = try await Modrinth.search(q, type: type, gameVersion: gv, loader: lf, offset: offset)
                results = more ? results + r : r
            } catch {
                self.error = error.friendly
            }
        }
    }
}

struct ProjectRow: View {
    let project: Modrinth.Project
    @PState private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: project.iconURL) { $0.resizable() } placeholder: {
                Rectangle().fill(Theme.panel2)
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(project.description).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(2)
                Text(project.categories.prefix(4).joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Label(formatCount(project.downloads), systemImage: "arrow.down.circle")
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(10)
        .background(hover ? Theme.panel2 : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : (n >= 1000 ? String(format: "%.1fK", Double(n) / 1e3) : "\(n)")
    }
}

struct ProjectVersionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: Modrinth.Project
    let type: Modrinth.ProjectType
    let instance: McInstance?
    @PState private var versions: [Modrinth.Version] = []
    @PState private var loading = true
    @PState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: project.iconURL) { $0.resizable() } placeholder: { Theme.panel2 }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title).font(.system(size: 16, weight: .bold))
                    Text(project.description).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                }
                Spacer()
                Button(T("查看网页", "Website")) { Links.open("https://modrinth.com/\(type == .shader ? "shader" : type.rawValue)/\(project.slug)") }
                    .buttonStyle(.kiln)
            }
            Text(instance.map { T("将安装到版本 \($0.name)", "Will be installed into \($0.name)") } ?? T("未选择版本，将另存为文件", "No instance selected; the file will be saved"))
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
            PageScroll {
                LazyVStack(spacing: 4) {
                    if loading { ProgressView().padding(30) }
                    if let error { Text(error).foregroundStyle(Theme.red).font(.system(size: 12)) }
                    if !loading && versions.isEmpty && error == nil {
                        Text(T("没有可用的版本", "No compatible versions")).foregroundStyle(Theme.text3).padding()
                    }
                    ForEach(versions) { v in
                        ListItem(systemIcon: "shippingbox.fill", title: v.name.isEmpty ? v.number : v.name,
                                 info: "\(v.gameVersions.suffix(3).joined(separator: ", ")) · \(v.loaders.joined(separator: ", ")) · \(v.published.formatted(date: .abbreviated, time: .omitted))") {
                            Button(T("安装", "Install")) { download(v) }.buttonStyle(.kilnPrimary)
                        }
                    }
                }
            }
            HStack { Spacer(); Button(T("取消", "Cancel")) { dismiss() }.buttonStyle(.kiln) }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task {
            do {
                let loader = type == .mod ? instance?.loaders.first { $0 != "OptiFine" } : nil
                versions = try await Modrinth.versions(project.id, gameVersion: instance?.vanillaVersion, loader: loader)
            } catch { self.error = error.friendly }
            loading = false
        }
    }

    private func download(_ v: Modrinth.Version) {
        var dest: URL
        if let instance {
            dest = instance.gameDir.appendingPathComponent("\(type.folder)/\(v.fileName)")
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = v.fileName
            guard panel.runModal() == .OK, let u = panel.url else { return }
            dest = u
        }
        JobCenter.shared.start(T("下载 \(v.fileName)", "Download \(v.fileName)")) { job in
            job.enter(v.fileName, index: 0, of: 1)
            try await Downloader.run([DownloadItem(url: v.fileURL, destination: dest, sha1: v.sha1, size: v.size)], job: job)
        }
        dismiss()
    }
}

// MARK: - 任务管理

struct TaskManagerPage: View {
    @PState private var center = JobCenter.shared

    var body: some View {
        PageScroll {
            VStack(spacing: 10) {
                if center.jobs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(Theme.text3)
                        Text(T("没有正在进行的任务", "No tasks")).font(.system(size: 13)).foregroundStyle(Theme.text3)
                    }
                    .padding(50)
                }
                ForEach(center.jobs) { JobRow(job: $0) }
                if center.jobs.contains(where: { $0.state != .running }) {
                    Button(T("清除已结束的任务", "Clear finished tasks")) { center.clearFinished() }.buttonStyle(.kiln)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

struct JobRow: View {
    let job: Job
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(job.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        if job.state == .running {
                            Text("\(Int(job.fraction * 100))%").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                        }
                    }
                    if job.state == .running { ProgressView(value: job.fraction) }
                    HStack(spacing: 10) {
                        Text(job.error ?? job.stage).lineLimit(2)
                        Spacer()
                        if job.state == .running && !job.fileText.isEmpty { Text(job.fileText) }
                        if job.state == .running && job.speed > 0 { Text(Job.formatSpeed(job.speed)) }
                    }
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(job.state == .failed ? Theme.red : Theme.text2)
                }
                if job.state == .running {
                    IconButton(systemImage: "xmark", help: T("取消", "Cancel")) { job.cancel() }
                }
            }
        }
    }

    private var icon: String {
        switch job.state {
        case .running: return "arrow.down"
        case .success: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark"
        }
    }
    private var color: Color {
        switch job.state {
        case .running: return Theme.accent
        case .success: return Theme.green
        case .failed: return Theme.red
        case .cancelled: return Theme.text3
        }
    }
}
