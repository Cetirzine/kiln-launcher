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
                    (.modpack, T("整合包", "Modpacks"), "shippingbox.fill"),
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
                case .modpack: ResourceSearchPage(type: .modpack).id("modpack")
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
                HStack(spacing: 10) {
                    Segmented(items: McVersionKind.allCases.map { ($0, $0.title) }, selection: $kind)
                    SearchField(placeholder: T("搜索", "Search"), text: $search).frame(width: 180)
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
    // 随 Forge 一起安装的附加组件
    @PState private var optifineVersions: [OptiFine.Version] = []
    @PState private var optifineFile = ""
    @PState private var withOptiFine = false
    @PState private var liteVersions: [LiteLoader.Version] = []
    @PState private var withLiteLoader = false

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
            Segmented(items: Loader.allCases.map { ($0, $0.title) }, selection: $loader)
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
            if loader == .forge && (!optifineVersions.isEmpty || !liteVersions.isEmpty) {
                forgeAddOns
            }
            if metalAvailable && (loader == .fabric || loader == .quilt) {
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
        .onChange(of: loader) { _, _ in
            Task { await loadLoaders() }
            Task { await loadForgeAddOns() }
        }
        .task {
            // 检查 MetalUniversal 是否支持该版本（仅 Apple 芯片）
            guard MetalRenderer.deviceSupported else { return }
            metalAvailable = !((try? await MetalRenderer.versions(game: version.id)) ?? []).isEmpty
        }
    }

    /// OptiFine / LiteLoader 选项（只显示该游戏版本支持的组件）
    private var forgeAddOns: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !optifineVersions.isEmpty {
                HStack(spacing: 8) {
                    Toggle(T("同时安装 OptiFine", "Also install OptiFine"), isOn: $withOptiFine).toggleStyle(.checkbox)
                    if withOptiFine {
                        Picker("", selection: $optifineFile) {
                            ForEach(optifineVersions) { v in
                                Text(v.display + (v.isPreview ? T("（预览）", " (preview)") : "")).tag(v.filename)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 170)
                    }
                }
                if withOptiFine, let warning = optifineCompatibility {
                    Text(warning.text).font(.system(size: 11)).foregroundStyle(warning.ok ? Theme.text3 : Theme.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let lite = liteVersions.first {
                Toggle(T("同时安装 LiteLoader \(lite.version)", "Also install LiteLoader \(lite.version)"), isOn: $withLiteLoader)
                    .toggleStyle(.checkbox)
            }
            if withOptiFine || withLiteLoader {
                Text(T("会作为 Mod 放入该版本的 mods 文件夹。OptiFine 与部分 Mod 兼容性不佳，遇到问题时可以在 Mod 管理中禁用。",
                       "They're added to this instance's mods folder. OptiFine conflicts with some mods; disable it in Mods if you run into problems."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 检查所选 OptiFine 要求的最低 Forge 版本
    private var optifineCompatibility: (text: String, ok: Bool)? {
        guard let v = optifineVersions.first(where: { $0.filename == optifineFile }), let need = v.forge else { return nil }
        let required = need.replacingOccurrences(of: "Forge ", with: "")
        guard !required.isEmpty, required.first?.isNumber == true else { return nil }
        // Forge 版本号形如 1.20.1-47.4.26，取后半部分比较
        let chosen = loaderVersion.split(separator: "-").dropFirst().first.map(String.init) ?? loaderVersion
        let ok = chosen.compare(required, options: .numeric) != .orderedAscending
        return ok ? (T("需要 Forge \(required) 或更新版本", "Requires Forge \(required) or newer"), true)
                  : (T("这个 OptiFine 需要 Forge \(required) 或更新版本，当前选择的 Forge 较旧。", "This OptiFine needs Forge \(required) or newer; the selected Forge is older."), false)
    }

    private func loadForgeAddOns() async {
        optifineVersions = []; liteVersions = []
        withOptiFine = false; withLiteLoader = false
        guard loader == .forge else { return }
        async let of = OptiFine.versions(game: version.id)
        async let ll = LiteLoader.versions(game: version.id)
        optifineVersions = (try? await of) ?? []
        liteVersions = (try? await ll) ?? []
        optifineFile = (optifineVersions.first { !$0.isPreview } ?? optifineVersions.first)?.filename ?? ""
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
        let metal = (loader == .fabric || loader == .quilt) && withMetal && metalAvailable
        let optifine = loader == .forge && withOptiFine ? optifineVersions.first { $0.filename == optifineFile } : nil
        let liteLoader = loader == .forge && withLiteLoader ? liteVersions.first : nil
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
            let mods = instance.gameDir.appendingPathComponent("mods")
            if let optifine {
                job.stage = T("下载 OptiFine \(optifine.display)", "Downloading OptiFine \(optifine.display)")
                try await OptiFine.install(optifine, into: mods, job: job)
            }
            if let liteLoader {
                job.stage = T("下载 LiteLoader \(liteLoader.version)", "Downloading LiteLoader \(liteLoader.version)")
                try await LiteLoader.install(liteLoader, into: mods, job: job)
            }
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
    /// Mod 加载器筛选，空字符串表示全部
    @PState private var loader: String = ""
    /// 来源：空字符串表示全部（Modrinth 在前，CurseForge 补充）
    @PState private var source: String = ""
    /// 当前结果是否来自中文名表（不支持“加载更多”）
    @PState private var fromNameTable = false
    @PState private var detail: Modrinth.Project?
    @PState private var searchTask: Task<Void, Never>?

    private var instance: McInstance? { state.instances.first { $0.name == target } }

    private static let filterWidth: CGFloat = 88

    private func filterLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                SearchField(placeholder: T("搜索\(type.title)", "Search \(type.title)"), text: $query) { runSearch() }
                if type == .modpack {
                    Button { ModpackActions.chooseFile() } label: {
                        Label(T("从文件安装…", "Install from file…"), systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.kiln)
                    .help(T("也可以直接把 .mrpack 或整合包 .zip 拖到窗口上", "You can also drop a .mrpack or modpack .zip onto the window"))
                } else {
                    Picker(T("安装到", "Install to"), selection: $target) {
                        Text(T("不限版本（另存为文件）", "Any version (save as file)")).tag("")
                        ForEach(state.instances.filter { $0.category != .error }) { Text($0.name).tag($0.name) }
                    }
                    .frame(width: 240)
                }
            }
            // 筛选：标签一列、各段等宽，上下两行的分段对齐
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    filterLabel(T("来源", "Source"))
                    Segmented(items: [("", T("全部", "All")),
                                      (Modrinth.Source.modrinth.rawValue, "Modrinth"),
                                      (Modrinth.Source.curseforge.rawValue, "CurseForge")],
                              selection: $source, segmentWidth: Self.filterWidth)
                    Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical)
                }
                if type == .mod || type == .modpack {
                    GridRow {
                        filterLabel(T("加载器", "Loader"))
                        Segmented(items: [("", T("全部", "All"))] + ["Fabric", "Forge", "NeoForge", "Quilt"].map { ($0, $0) },
                                  selection: $loader, segmentWidth: Self.filterWidth)
                        Group {
                            if loader == "Quilt" {
                                Text(T("包含可在 Quilt 上运行的 Fabric Mod", "Includes Fabric mods, which run on Quilt"))
                                    .foregroundStyle(Theme.text3)
                            } else if let i = instance, let own = instanceLoader(i), !loader.isEmpty, own != loader {
                                Text(T("与所选版本的加载器（\(own)）不同", "Differs from the selected instance's loader (\(own))"))
                                    .foregroundStyle(Theme.yellow)
                            }
                        }
                        .font(.system(size: 11.5)).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PageScroll {
                LazyVStack(spacing: 0) {
                    if loading && results.isEmpty { ProgressView().padding(40) }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.red).padding() }
                    ForEach(results) { p in
                        ProjectRow(project: p).onTapGesture { detail = p }
                    }
                    if !results.isEmpty && !fromNameTable && results.count >= 30 {
                        Button(T("加载更多", "Load more")) { runSearch(more: true) }.buttonStyle(.kiln).padding()
                    }
                }
            }
            Text(T("搜索结果来自 Modrinth 与 CurseForge（经 MCIM 镜像）；可以用中文、拼音或拼音首字母搜索", "Results from Modrinth and CurseForge (via the MCIM mirror)"))
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .onAppear {
            if let t = ResourceSearchPage.targetInstance { target = t; ResourceSearchPage.targetInstance = nil }
            else if type != .modpack, let s = state.selectedInstance, type != .mod || s.isModded { target = s.name }
            if let i = instance, let own = instanceLoader(i) { loader = own }
            runSearch()
        }
        .onChange(of: target) { _, _ in
            // 切换目标版本时，加载器跟随该版本
            if let i = instance, let own = instanceLoader(i) { loader = own }
            runSearch()
        }
        .onChange(of: loader) { _, _ in runSearch() }
        .onChange(of: source) { _, _ in runSearch() }
        .task { await ModNames.shared.refresh() }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task { try? await Task.sleep(nanoseconds: 400_000_000); if !Task.isCancelled { runSearch() } }
        }
        .sheet(item: $detail) { p in ProjectVersionsSheet(project: p, type: type, instance: instance, loader: loaderFilter) }
    }

    /// 实例使用的 Mod 加载器
    private func instanceLoader(_ i: McInstance) -> String? {
        i.loaders.first { ["Fabric", "Forge", "NeoForge", "Quilt"].contains($0) }
    }

    private var loaderFilter: String? {
        (type == .mod || type == .modpack) && !loader.isEmpty ? loader : nil
    }

    private func runSearch(more: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespaces), gv = instance?.vanillaVersion, lf = loaderFilter
        let type = type, source = source
        let useModrinth = source != Modrinth.Source.curseforge.rawValue
        let useCurseForge = source != Modrinth.Source.modrinth.rawValue
        Task { @MainActor in
            loading = true
            error = nil
            defer { loading = false }
            // 中文名表：中文、拼音或首字母搜索
            let named = type == .mod && !q.isEmpty ? ModNames.shared.search(q) : []
            if ModNames.containsCJK(q) && !more {
                // 中文搜索：从名表找到对应的 Mod，再按 slug 取回
                fromNameTable = true
                var list: [Modrinth.Project] = []
                if useModrinth { list += (try? await Modrinth.projects(named, gameVersion: gv, loader: lf)) ?? [] }
                if useCurseForge && list.count < 10 {
                    // CurseForge 用名表中的英文 slug 作为搜索词补充
                    for slug in named.prefix(3) where !list.contains(where: { $0.slug == slug }) {
                        if let hit = try? await CurseForge.search(slug.replacingOccurrences(of: "-", with: " "), type: type, gameVersion: gv, loader: lf).first(where: { $0.slug == slug }) {
                            list.append(hit)
                        }
                    }
                }
                results = list
                if list.isEmpty {
                    error = named.isEmpty
                        ? T("名表里没有找到“\(q)”，可以试试英文名。", "\"\(q)\" isn't in the name table; try the English name.")
                        : T("找到了对应的 Mod，但没有适用于当前版本或加载器的。", "Found matching mods, but none for this version or loader.")
                }
                return
            }
            fromNameTable = false
            let offset = more ? results.count : 0
            async let mr: [Modrinth.Project] = useModrinth ? Modrinth.search(q, type: type, gameVersion: gv, loader: lf, offset: offset) : []
            async let cf: [Modrinth.Project] = useCurseForge ? CurseForge.search(q, type: type, gameVersion: gv, loader: lf, offset: offset) : []
            var merged: [Modrinth.Project] = []
            var failures: [String] = []
            do { merged += try await mr } catch { failures.append("Modrinth：\(error.friendly)") }
            do {
                // CurseForge 作为补充：去掉与 Modrinth 重复的项目
                let known = Set(merged.map(\.slug) + (more ? results.map(\.slug) : []))
                merged += try await cf.filter { !known.contains($0.slug) }
            } catch { failures.append("CurseForge：\(error.friendly)") }
            // 拼音或首字母命中名表时，把对应的 Mod 放在最前面
            if !more, !named.isEmpty, useModrinth, !q.contains(" ") {
                let pinned = (try? await Modrinth.projects(Array(named.prefix(5)), gameVersion: gv, loader: lf)) ?? []
                merged = pinned + merged.filter { m in !pinned.contains { $0.slug == m.slug } }
            }
            results = more ? results + merged : merged
            if merged.isEmpty && !failures.isEmpty { error = failures.joined(separator: "\n") }
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
                // 英文名后面跟灰色的中文名
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(project.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let zh = chineseName {
                        Text(zh).font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                }
                Text(project.description).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(2)
                HStack(spacing: 8) {
                    if project.source == .curseforge {
                        Text("CurseForge").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0xC0592B))
                    }
                    Text(project.categories.prefix(4).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
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

    /// 中文界面下显示中文名（与英文名相同时不显示）
    private var chineseName: String? {
        guard Localizer.shared.language != .en, let zh = ModNames.shared.chinese(project.slug), zh != project.title else { return nil }
        return T(zh, zh)
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
    var loader: String?
    @PState private var versions: [Modrinth.Version] = []
    @PState private var loading = true
    @PState private var error: String?
    /// 正在检查前置的版本
    @PState private var checking: String?
    /// 需要一起安装的前置
    @PState private var pending: (version: Modrinth.Version, deps: [(project: Modrinth.Project?, version: Modrinth.Version)])?

    private var website: String {
        project.pageURL ?? "https://modrinth.com/\(type == .shader ? "shader" : type.rawValue)/\(project.slug)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: project.iconURL) { $0.resizable() } placeholder: { Theme.panel2 }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(project.title).font(.system(size: 16, weight: .bold))
                        if Localizer.shared.language != .en, let zh = ModNames.shared.chinese(project.slug), zh != project.title {
                            Text(T(zh, zh)).font(.system(size: 13)).foregroundStyle(Theme.text3)
                        }
                    }
                    Text(project.description).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                }
                Spacer()
                Button(T("在 \(project.source.rawValue) 查看", "View on \(project.source.rawValue)")) { Links.open(website) }
                    .buttonStyle(.kiln)
                if type == .mod && Localizer.shared.language != .en {
                    // 跳转到 MC 百科查看中文资料（只是链接，不抓取内容）
                    Button(T("在 MC 百科查看", "View on MC Wiki (mcmod.cn)")) {
                        var allowed = CharacterSet.alphanumerics
                        allowed.insert(charactersIn: "-._~")
                        let key = (ModNames.shared.chinese(project.slug) ?? project.title).addingPercentEncoding(withAllowedCharacters: allowed) ?? project.slug
                        Links.open("https://search.mcmod.cn/s?key=\(key)")
                    }
                    .buttonStyle(.kiln)
                }
            }
            if type == .modpack {
                Text(T("选择一个版本，安装为新的游戏版本", "Choose a version to install as a new instance"))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            } else {
                Text(instance.map { T("将安装到版本 \($0.name)", "Will be installed into \($0.name)") } ?? T("未选择版本，将另存为文件", "No instance selected; the file will be saved"))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            if let pending {
                // 前置确认
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("\(project.title) 需要以下前置 Mod：", "\(project.title) requires these mods:"))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(pending.deps.map { $0.project?.title ?? $0.version.fileName }.joined(separator: "、"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(T("一起安装（\(pending.deps.count + 1) 个）", "Install all (\(pending.deps.count + 1))")) {
                            download(pending.version, with: pending.deps.map(\.version))
                        }.buttonStyle(.kilnPrimary)
                        Button(T("只安装 \(project.title)", "Only \(project.title)")) { download(pending.version, with: []) }.buttonStyle(.kiln)
                        Button(T("取消", "Cancel")) { self.pending = nil }.buttonStyle(.kiln)
                    }
                }
                .padding(12)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 3))
            }
            PageScroll {
                LazyVStack(spacing: 4) {
                    if loading { ProgressView().padding(30) }
                    if let error { Text(error).foregroundStyle(Theme.red).font(.system(size: 12)) }
                    if !loading && versions.isEmpty && error == nil {
                        Text(T("没有可用的版本", "No compatible versions")).foregroundStyle(Theme.text3).padding()
                    }
                    ForEach(versions) { v in
                        ListItem(systemIcon: "shippingbox.fill", title: v.name.isEmpty ? v.number : v.name,
                                 info: "\(v.gameVersions.suffix(3).joined(separator: ", "))   \(v.loaders.joined(separator: ", "))   \(v.published.formatted(date: .abbreviated, time: .omitted))") {
                            if v.blocked {
                                // 作者禁止第三方下载：只能到网站手动下载
                                Button(T("到网站下载", "Download on website")) { Links.open(website) }.buttonStyle(.kiln)
                                    .help(T("作者不允许第三方启动器下载此文件", "The author doesn't allow third-party launchers to download this file"))
                            } else if checking == v.id {
                                ProgressView().controlSize(.small).help(T("正在检查前置", "Checking dependencies"))
                            } else {
                                Button(T("安装", "Install")) { install(v) }.buttonStyle(.kilnPrimary).disabled(checking != nil)
                            }
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
                let loader = type == .mod || type == .modpack ? self.loader : nil
                switch project.source {
                case .modrinth: versions = try await Modrinth.versions(project.id, gameVersion: type == .modpack ? nil : instance?.vanillaVersion, loader: loader)
                case .curseforge: versions = try await CurseForge.files(project, gameVersion: type == .modpack ? nil : instance?.vanillaVersion, loader: loader)
                }
            } catch { self.error = error.friendly }
            loading = false
        }
    }

    /// 点击安装：整合包打开安装窗口；Mod 先检查前置
    private func install(_ v: Modrinth.Version) {
        if type == .modpack {
            AppState.shared.modpackInstall = .remote(v, project)
            dismiss()
            return
        }
        guard type == .mod, let instance, !v.dependencies.filter(\.required).isEmpty else { download(v, with: []); return }
        checking = v.id
        Task { @MainActor in
            defer { checking = nil }
            // 跳过已安装的前置：识别 mods 文件夹中的文件
            let mods = instance.gameDir.appendingPathComponent("mods")
            let files = ((try? FileManager.default.contentsOfDirectory(at: mods, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jar" || $0.lastPathComponent.hasSuffix(".jar.disabled") }
            let installed = ModIndex.installedProjects(await ModIndex.identify(files))
            let loader = instance.loaders.first { ["Fabric", "Forge", "NeoForge", "Quilt"].contains($0) }
            let deps = (try? await ModIndex.requiredDependencies(of: v, gameVersion: instance.vanillaVersion, loader: loader,
                                                                  installedProjects: installed)) ?? []
            if deps.isEmpty { download(v, with: []) } else { pending = (v, deps) }
        }
    }

    private func download(_ v: Modrinth.Version, with deps: [Modrinth.Version]) {
        var dest: URL
        if let instance {
            dest = instance.gameDir.appendingPathComponent("\(type.folder)/\(v.fileName)")
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = v.fileName
            guard panel.runModal() == .OK, let u = panel.url else { return }
            dest = u
        }
        func item(_ v: Modrinth.Version, _ dest: URL) -> DownloadItem {
            var item = DownloadItem(url: v.fileURL, destination: dest, sha1: v.sha1, size: v.size)
            if v.source == .curseforge { item.urls = CurseForge.downloadURLs(v) }
            return item
        }
        var items = [item(v, dest)]
        if let instance {
            for d in deps where !d.blocked {
                items.append(item(d, instance.gameDir.appendingPathComponent("mods/\(d.fileName)")))
            }
        }
        let title = deps.isEmpty ? v.fileName : T("\(v.fileName) 及 \(deps.count) 个前置", "\(v.fileName) and \(deps.count) dependencies")
        JobCenter.shared.start(T("下载 \(title)", "Download \(title)")) { job in
            job.enter(title, index: 0, of: 1)
            try await Downloader.run(items, job: job)
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
