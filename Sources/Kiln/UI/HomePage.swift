import SwiftUI
import LauncherCore
import AppKit

// MARK: - 主页：游戏画面为主体，物品栏切换版本，右下角开始游戏

struct HomePage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Hero()
                .frame(minHeight: 330, maxHeight: .infinity)
                .clipped()
            if !state.games.isEmpty { RunningGamesBar() }
            PatchNotesStrip()
                .frame(height: 214, alignment: .top)
        }
    }
}

/// 主视觉：全幅显示当前版本的标题全景图，界面元素以 HUD 的方式叠在上面
struct Hero: View {
    @Environment(AppState.self) private var state
    @PState private var panorama: NSImage?
    /// 已加载的全景图（也用于离屏截图）
    @MainActor static var cache: [String: NSImage] = [:]

    var body: some View {
        let instance = state.selectedInstance
        ZStack(alignment: .bottomLeading) {
            // 底部压暗，保证文字可读
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.62), location: 1)],
                           startPoint: .top, endPoint: .bottom)

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    if let i = instance {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(i.name).font(Theme.display(32, .heavy)).foregroundStyle(.white).lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 0, x: 2, y: 2)
                            HStack(spacing: 14) {
                                Text(i.vanillaVersion)
                                ForEach(i.loaders, id: \.self) { l in Text(i.loaderVersion(l).map { "\(l) \($0)" } ?? l) }
                                if Arch.isAppleSilicon { Text(archText(i)) }
                                if MetalRenderer.isEnabled(i) { Text(T("Metal 渲染", "Metal rendering")) }
                            }
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(T("还没有安装游戏", "No game installed yet")).font(Theme.display(28, .heavy)).foregroundStyle(.white)
                            Text(T("先下载一个版本，安装完成后会出现在这里。", "Download a version first; it will show up here once installed."))
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    Hotbar()
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if let i = instance {
                        Button { state.subPage = .instanceSetup(i) } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 52, height: 52).background(Glass())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(T("版本设置", "Instance settings"))
                    }
                    PlayButton()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 图片放在背景层：由内容决定尺寸，图片按填充模式铺满后裁切
        .background {
            if let panorama = panorama ?? instance.flatMap({ Hero.cache[$0.name] }) {
                Image(nsImage: panorama).resizable().aspectRatio(contentMode: .fill)
            } else {
                DirtTexture()
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            AccountChip(onImage: true).padding(.top, 18).padding(.trailing, 22)
        }
        .task(id: instance?.name) {
            if let i = instance, let c = Hero.cache[i.name] { panorama = c; return }
            panorama = await Hero.loadPanorama(instance)
            if let i = instance, let p = panorama { Hero.cache[i.name] = p }
        }
    }

    private func archText(_ i: McInstance) -> String {
        i.preferredArch == "arm64" ? T("Apple 芯片原生", "Native on Apple silicon") : T("Rosetta 2", "Rosetta 2")
    }

    /// 从已安装的资源中读取标题界面全景图
    static func loadPanorama(_ instance: McInstance?) async -> NSImage? {
        guard let instance else { return nil }
        return await Task.detached(priority: .utility) {
            let indexFile = instance.folder.appendingPathComponent("assets/indexes/\(instance.assetIndexId).json")
            guard let data = try? Data(contentsOf: indexFile), let j = try? JSON(data: data) else { return nil }
            for n in [0, 1, 3] {
                if let hash = j["objects"]["minecraft/textures/gui/title/background/panorama_\(n).png"]["hash"].string {
                    let u = instance.folder.appendingPathComponent("assets/objects/\(hash.prefix(2))/\(hash)")
                    if let img = NSImage(contentsOf: u) { return img }
                }
            }
            return nil
        }.value
    }
}

/// 没有全景图时的背景：游戏菜单里那种压暗的泥土纹理
struct DirtTexture: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
            let tones: [UInt32] = [0x2b2219, 0x332819, 0x3a2e1f, 0x2f2519, 0x27201a, 0x3f3324]
            for x in stride(from: 0, to: size.width, by: s) {
                for y in stride(from: 0, to: size.height, by: s) {
                    let t = tones[Int(next() * Double(tones.count)) % tones.count]
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(hex: t)))
                }
            }
        }
    }
}

// MARK: - 物品栏

/// 与游戏相同的物品栏：每格一个版本，按 1–9 切换；切换时上方浮现名称，片刻后淡出
struct Hotbar: View {
    @Environment(AppState.self) private var state
    @PState private var shownName: String?
    @PState private var hideTask: Task<Void, Never>?

    private var slots: [McInstance] {
        let usable = state.instances.filter { $0.category != .error }
        let sorted = usable.sorted { ($0.setup.lastPlayed ?? .distantPast) > ($1.setup.lastPlayed ?? .distantPast) }
        var list = Array(sorted.prefix(9))
        if let sel = state.selectedInstance, !list.contains(sel) {
            if list.count == 9 { list.removeLast() }
            list.insert(sel, at: 0)
        }
        return list
    }

    var body: some View {
        let list = slots
        let selected = state.selectedInstance
        VStack(alignment: .leading, spacing: 6) {
            Text(shownName ?? " ")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 0, x: 1, y: 1)
                .opacity(shownName == nil ? 0 : 1)
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { n in
                    let instance = n < list.count ? list[n] : nil
                    slot(instance, selected: instance != nil && instance == selected)
                        .overlay(alignment: .topLeading) {
                            Text("\(n + 1)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white.opacity(0.45)).padding(3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let instance { pick(instance) } }
                        .help(instance?.name ?? "")
                        .background {
                            if let instance {
                                Button("") { pick(instance) }
                                    .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")), modifiers: [])
                                    .opacity(0)
                            }
                        }
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.5))
            .overlay(Rectangle().stroke(Color.white.opacity(0.22), lineWidth: 1))
        }
        .fixedSize()
    }

    private func slot(_ instance: McInstance?, selected: Bool) -> some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.04))
            if let instance { BlockIcon(kind: instance.icon).frame(width: 26, height: 26) }
        }
        .frame(width: 42, height: 42)
        .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .overlay {
            if selected {
                Rectangle().stroke(Color.white, lineWidth: 2).padding(-2)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 1).padding(-3))
            }
        }
        .zIndex(selected ? 1 : 0)
    }

    private func pick(_ instance: McInstance) {
        state.select(instance)
        shownName = instance.name
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { shownName = nil }
        }
    }
}

// MARK: - 开始游戏

/// 开始游戏按钮；启动时按钮本身就是进度条，点击可取消
struct PlayButton: View {
    @Environment(AppState.self) private var state
    @PState private var hover = false

    var body: some View {
        let job = state.isLaunching ? state.launchJob : nil
        Button {
            if job != nil { state.cancelLaunch() }
            else if state.selectedInstance == nil { state.page = .download; state.downloadSection = .game }
            else { state.launchSelected() }
        } label: {
            ZStack(alignment: .leading) {
                Rectangle().fill(job == nil ? (hover ? Theme.playLight : Theme.play) : Theme.playEdge)
                if let job {
                    GeometryReader { g in
                        Rectangle().fill(Theme.play).frame(width: g.size.width * job.fraction)
                            .animation(.linear(duration: 0.25), value: job.fraction)
                    }
                }
                VStack(spacing: 2) {
                    if let job {
                        Text(hover ? T("取消启动", "Cancel launch") : job.stage)
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(job.speed > 0 ? Job.formatSpeed(job.speed) : "\(Int(job.fraction * 100))%")
                            .font(.system(size: 11, weight: .medium).monospacedDigit()).opacity(0.8)
                    } else {
                        Text(state.selectedInstance == nil ? T("下载游戏", "Get the game") : T("开始游戏", "Play"))
                            .font(Theme.display(19, .heavy))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
            }
            .frame(width: 230, height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.28)).frame(height: 3) }
            .overlay(Rectangle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .keyboardShortcut(.return, modifiers: [])
        .contextMenu {
            Button(T("导出启动脚本…", "Export launch script…")) { exportScript() }
            Button(T("以试玩模式启动", "Play the demo")) { state.launchSelected(options: LaunchOptions(demo: true)) }
        }
    }

    private func exportScript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(state.selectedInstance?.name ?? "Minecraft").command"
        if panel.runModal() == .OK, let url = panel.url {
            state.launchSelected(options: LaunchOptions(exportScript: url))
        }
    }
}

// MARK: - 账号

/// 账号按钮（放在主图上时使用浅色文字）
struct AccountChip: View {
    var onImage = false
    @PState private var store = AccountStore.shared
    @PState private var show = false
    @PState private var hover = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 8) {
                Avatar(account: store.selected).frame(width: 22, height: 22)
                Text(store.selected?.name ?? T("添加账号", "Add account"))
                    .font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            }
            .foregroundStyle(onImage ? Color.white : Theme.text)
            .padding(.leading, 5).padding(.trailing, 9).frame(height: 32)
            .background {
                if onImage { Glass() } else { RoundedRectangle(cornerRadius: 3).fill(hover ? Theme.panelHover : Color.clear) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $show, arrowEdge: .bottom) { AccountPopover(show: $show) }
    }
}

/// 玩家头像：通过 mc-heads.net 获取（离线账号按名称获取同名正版玩家的皮肤，没有则为默认皮肤）
struct Avatar: View {
    let account: Account?
    var body: some View {
        Group {
            if let a = account, let url = Avatar.url(a) {
                AsyncImage(url: url) { img in img.resizable().interpolation(.none) } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.35))
            .overlay(Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)))
    }

    static func url(_ a: Account) -> URL? {
        let id = a.kind == .microsoft ? a.uuid : a.name
        return URL(string: "https://mc-heads.net/avatar/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/64")
    }
}

struct AccountPopover: View {
    @Binding var show: Bool
    @PState private var store = AccountStore.shared
    @PState private var offlineName = ""
    @PState private var msLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("账号", "Accounts")).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            if store.accounts.isEmpty {
                Text(T("还没有账号，可添加离线账号或登录正版。", "No accounts yet. Add an offline account or sign in with Microsoft.")).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            ForEach(store.accounts) { acc in
                ListItem(systemIcon: acc.kind == .microsoft ? "checkmark.seal.fill" : "person.fill", title: acc.name,
                         info: acc.kind == .microsoft ? T("微软账号", "Microsoft") : T("离线账号", "Offline"),
                         selected: acc.id == store.selected?.id,
                         action: { store.selectedId = acc.id; show = false }) {
                    IconButton(systemImage: "trash", help: T("删除", "Delete")) { store.remove(acc) }
                }
            }
            Divider()
            Text(T("添加离线账号", "Add offline account")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            HStack {
                TextField(T("玩家名称", "Player name"), text: $offlineName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addOffline)
                Button(T("确定", "OK"), action: addOffline).buttonStyle(.kiln)
            }
            if let warn = offlineWarning {
                Text(warn).font(.system(size: 11)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button { msLogin = true } label: {
                    Label(T("微软账号登录", "Sign in with Microsoft"), systemImage: "person.badge.key.fill")
                }
                .buttonStyle(.kilnPrimary)
                Spacer()
                Button(T("购买 Minecraft", "Buy Minecraft").replacingOccurrences(of: "»  ", with: "")) { Links.open(Links.buyMinecraft) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12))
            }
        }
        .padding(16)
        .frame(width: 330)
        .sheet(isPresented: $msLogin) { MicrosoftLoginSheet(show: $msLogin) }
    }

    private var offlineWarning: String? {
        let n = offlineName
        if n.isEmpty { return nil }
        if let e = AccountStore.validateOffline(n) { return e }
        if n.count > 16 { return T("1.20.3 起名称最多 16 个字符", "Since 1.20.3 names are limited to 16 characters") }
        if n.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) == nil { return T("建议只使用字母、数字和下划线，否则可能无法进入 1.18 以后的世界", "Use only letters, digits and underscores, or worlds in 1.18+ may not load") }
        return nil
    }

    private func addOffline() {
        let n = offlineName.trimmingCharacters(in: .whitespaces)
        if let e = AccountStore.validateOffline(n) { Hint.show(e, .red); return }
        store.addOffline(n)
        offlineName = ""
        show = false
    }
}

struct MicrosoftLoginSheet: View {
    @Binding var show: Bool
    @PState private var code: MicrosoftAuth.DeviceCode?
    @PState private var status = T("请稍候……", "Please wait…")
    @PState private var failed = false
    @PState private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Text(T("微软账号登录", "Sign in with Microsoft")).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            if let code {
                Text(T("在打开的网页中输入下面的代码，完成后回到这里：", "Enter this code on the page that opened, then come back here:")).font(.system(size: 13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                Text(code.userCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .textSelection(.enabled)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 3))
                Button(T("复制代码并打开网页", "Copy code and open page")) { copyAndOpen(code) }.buttonStyle(.kilnPrimary)
            }
            HStack(spacing: 6) {
                if !failed { ProgressView().controlSize(.small) }
                Text(status).font(.system(size: 12)).foregroundStyle(failed ? Theme.red : Theme.text2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button(T("取消", "Cancel")) { task?.cancel(); show = false }.buttonStyle(.kiln)
        }
        .padding(26)
        .frame(width: 420)
        .onAppear(perform: start)
        .onDisappear { task?.cancel() }
    }

    private func copyAndOpen(_ c: MicrosoftAuth.DeviceCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c.userCode, forType: .string)
        Links.open(c.verificationURI)
    }

    private func start() {
        task = Task { @MainActor in
            do {
                let c = try await MicrosoftAuth.requestDeviceCode()
                code = c
                copyAndOpen(c)
                status = T("等待网页登录……", "Waiting for web sign-in…")
                let tokens = try await MicrosoftAuth.poll(c)
                status = T("请稍候……", "Please wait…")
                let r = try await MicrosoftAuth.minecraft(msAccess: tokens.access, refresh: tokens.refresh)
                AccountStore.shared.addMicrosoft(profile: (r.name, r.uuid), refreshToken: r.refreshToken,
                                                 accessToken: r.accessToken, expires: r.expires)
                Hint.show(T("已登录正版账号 \(r.name)！", "Signed in as \(r.name)!"), .green)
                show = false
            } catch is CancellationError {
            } catch {
                failed = true
                status = error.friendly
            }
        }
    }
}

// MARK: - 主图下方

/// 运行中的游戏：一行状态
struct RunningGamesBar: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: 0) {
            ForEach(state.games.prefix(3)) { g in
                HStack(spacing: 12) {
                    Rectangle().fill(color(g)).frame(width: 7, height: 7)
                    Text(g.instanceName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                    Text(stateText(g)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button(T("查看日志", "View log")) { state.showLog = g }.buttonStyle(.kiln)
                    if g.state == .running || g.state == .starting {
                        Button(T("结束进程", "Force quit")) { g.kill() }.buttonStyle(.kilnDanger)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 8)
                Rectangle().fill(Theme.stroke).frame(height: 1)
            }
        }
        .background(Theme.panel)
    }

    private func color(_ g: GameProcess) -> Color {
        switch g.state {
        case .starting: return Theme.yellow
        case .running: return Theme.green
        case .exited: return Theme.text3
        case .crashed: return Theme.red
        }
    }

    private func stateText(_ g: GameProcess) -> String {
        switch g.state {
        case .starting: return T("正在等待游戏窗口", "Waiting for the game window")
        case .running: return T("运行中", "Running")
        case .exited: return T("已退出", "Exited")
        case .crashed: return T("崩溃了，退出码 \(g.exitCode ?? -1)", "Crashed with exit code \(g.exitCode ?? -1)")
        }
    }
}

/// Minecraft 官方更新日志：横向排列，图片加标题
struct PatchNotesStrip: View {
    struct Note: Identifiable { let id: String; let title: String; let version: String; let type: String; let image: URL? }
    @PState private var notes: [Note] = []
    @PState private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(T("Minecraft 更新", "Minecraft updates")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if failed {
                    Text(T("无法加载更新日志，请检查网络。", "Couldn't load the update notes. Check your connection."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                ForEach(notes.prefix(4)) { n in
                    Button { Links.open("https://minecraft.wiki/w/Java_Edition_\(n.version)") } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: n.image) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Theme.panel2 }
                                .frame(height: 92).frame(maxWidth: .infinity).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(n.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(n.type == "release" ? T("正式版 \(n.version)", "Release \(n.version)") : T("快照 \(n.version)", "Snapshot \(n.version)"))
                                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(T("在 Minecraft Wiki 中查看", "Open on the Minecraft Wiki"))
                }
                if notes.isEmpty && !failed {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            Rectangle().fill(Theme.panel2).frame(height: 92)
                            Rectangle().fill(Theme.panel2).frame(width: 120, height: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .task { await load() }
    }

    private func load() async {
        guard notes.isEmpty else { return }
        do {
            let j = try await Net.json(urls: ["https://launchercontent.mojang.com/v2/javaPatchNotes.json"])
            notes = j["entries"].array.prefix(8).compactMap { e in
                guard let v = e["version"].string else { return nil }
                let img = e["image"]["url"].string.flatMap { URL(string: "https://launchercontent.mojang.com" + $0) }
                return Note(id: e["id"].string ?? v, title: e["title"].string ?? v, version: v, type: e["type"].string ?? "release", image: img)
            }
        } catch {
            failed = true
        }
    }
}
