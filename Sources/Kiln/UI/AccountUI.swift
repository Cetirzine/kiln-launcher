import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

// MARK: - 皮肤渲染

/// 从皮肤图片生成头像与正面预览（像素放大，不模糊）
enum SkinRender {
    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func load(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 头像：脸 + 帽子层
    static func face(_ skin: CGImage) -> CGImage? {
        compose(width: 8, height: 8, skin) { draw in
            draw(8, 8, 8, 8, 0, 0, false)
            draw(40, 8, 8, 8, 0, 0, false)
        }
    }

    /// 正面全身
    static func front(_ skin: CGImage, slim: Bool) -> CGImage? {
        let legacy = skin.height == 32
        let arm = slim ? 3 : 4
        return compose(width: 16, height: 32, skin) { draw in
            // 基础层
            draw(8, 8, 8, 8, 4, 0, false)                         // 头
            draw(20, 20, 8, 12, 4, 8, false)                      // 身体
            draw(44, 20, arm, 12, 4 - arm, 8, false)              // 右臂（画面左侧）
            if legacy { draw(44, 20, arm, 12, 12, 8, true) } else { draw(36, 52, arm, 12, 12, 8, false) }
            draw(4, 20, 4, 12, 4, 20, false)                      // 右腿
            if legacy { draw(4, 20, 4, 12, 8, 20, true) } else { draw(20, 52, 4, 12, 8, 20, false) }
            // 外层
            draw(40, 8, 8, 8, 4, 0, false)
            if !legacy {
                draw(20, 36, 8, 12, 4, 8, false)
                draw(44, 36, arm, 12, 4 - arm, 8, false)
                draw(52, 52, arm, 12, 12, 8, false)
                draw(4, 36, 4, 12, 4, 20, false)
                draw(4, 52, 4, 12, 8, 20, false)
            }
        }
    }

    /// 把皮肤中的区域（左上角坐标）画到画布的指定位置（左上角坐标）
    private static func compose(width: Int, height: Int, _ skin: CGImage,
                                _ body: ((Int, Int, Int, Int, Int, Int, Bool) -> Void) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        body { sx, sy, w, h, dx, dy, mirror in
            guard let part = skin.cropping(to: CGRect(x: sx, y: sy, width: w, height: h)) else { return }
            let rect = CGRect(x: dx, y: height - dy - h, width: w, height: h)
            ctx.saveGState()
            if mirror {
                ctx.translateBy(x: rect.midX, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -rect.midX, y: 0)
            }
            ctx.draw(part, in: rect)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}

/// 像素图片（放大时保持清晰）
struct PixelImage: View {
    let image: CGImage?
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// 皮肤与头像缓存：离线账号的本地皮肤或同名正版皮肤、外置登录与微软账号的皮肤
@MainActor
final class FaceCache {
    static let shared = FaceCache()
    private var faces: [String: CGImage] = [:]
    private var skins: [String: (CGImage, Bool)] = [:]

    private func key(_ account: Account) -> String { account.id + (account.skin?.file ?? "") + (account.skin?.premium ?? "") }

    /// 账号当前的皮肤图片，以及是否为纤细手臂模型；取不到时返回 nil（使用默认的史蒂夫）
    func skin(for account: Account) async -> (CGImage, Bool)? {
        let k = key(account)
        if let s = skins[k] { return s }
        var result: (CGImage, Bool)?
        switch account.kind {
        case .offline:
            if let file = account.skin?.file, let img = SkinRender.load(Skins.file(file)) { result = (img, account.skin?.slim ?? false) }
            else if let name = account.skin?.premium, let (url, slim) = try? await Skins.premium(name), let img = SkinRender.load(url) { result = (img, slim) }
        case .yggdrasil:
            if let root = account.server { result = await Self.profileSkin(root + "/sessionserver/session/minecraft/profile/\(account.uuid)") }
        case .microsoft:
            // 正版皮肤是公开的，按 UUID 向 Mojang 查询，不需要登录令牌
            result = await Self.profileSkin("https://sessionserver.mojang.com/session/minecraft/profile/\(account.uuid.replacingOccurrences(of: "-", with: ""))")
        }
        if let result { skins[k] = result }
        return result
    }

    func face(for account: Account) async -> CGImage? {
        let k = key(account)
        if let f = faces[k] { return f }
        guard let (skin, _) = await skin(for: account), let face = SkinRender.face(skin) else { return nil }
        faces[k] = face
        return face
    }

    private static func profileSkin(_ url: String) async -> (CGImage, Bool)? {
        guard let profile = try? await Net.json(urls: [url]),
              let value = profile["properties"].array.first(where: { $0["name"].string == "textures" })?["value"].string,
              let data = Data(base64Encoded: value), let t = try? JSON(data: data),
              let skinURL = t["textures"]["SKIN"]["url"].string,
              let png = try? await Net.data([skinURL.replacingOccurrences(of: "http://", with: "https://")]),
              let img = SkinRender.load(png) else { return nil }
        return (img, t["textures"]["SKIN"]["metadata"]["model"].string == "slim")
    }

    func invalidate() { faces.removeAll(); skins.removeAll() }
}

// MARK: - 外置登录

struct YggdrasilLoginSheet: View {
    /// 重新登录时预先填写
    var account: Account?
    @Binding var show: Bool
    @PState private var server = Yggdrasil.presets[0].url
    @PState private var username = ""
    @PState private var password = ""
    @PState private var busy = false
    @PState private var error: String?
    @PState private var registerURL: String?
    /// 账号下有多个角色时选择
    @PState private var choices: (root: String, name: String, session: Yggdrasil.Session)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("外置登录", "Third-party login")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            Text(T("使用 LittleSkin 等支持 authlib-injector 的皮肤站账号登录。", "Sign in with an account from a skin site that supports authlib-injector, such as LittleSkin."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            if let choices {
                Text(T("选择要使用的角色", "Choose a character")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                VStack(spacing: 0) {
                    ForEach(choices.session.profiles, id: \.id) { p in
                        ListItem(systemIcon: "person.fill", title: p.name, action: { select(p, choices) })
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text(T("服务器", "Server")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        HStack(spacing: 6) {
                            TextField("https://littleskin.cn/api/yggdrasil", text: $server).textFieldStyle(.roundedBorder)
                            Menu {
                                ForEach(Yggdrasil.presets, id: \.url) { p in Button(p.name) { server = p.url } }
                            } label: { Image(systemName: "list.bullet") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .help(T("常用皮肤站", "Common skin sites"))
                        }
                    }
                    GridRow {
                        Text(T("账号", "Account")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        TextField(T("邮箱或用户名", "Email or username"), text: $username).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(T("密码", "Password")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        SecureField("", text: $password).textFieldStyle(.roundedBorder).onSubmit(login)
                    }
                }
                Text(T("密码只用于这一次登录，Kiln 不会保存密码；登录后只在本机保存服务器下发的令牌。",
                       "Your password is only used for this sign-in and is never stored. Kiln keeps only the token issued by the server, on this Mac."))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let registerURL, choices == nil {
                    Button(T("注册账号", "Create an account")) { Links.open(registerURL) }.buttonStyle(.plain)
                        .foregroundStyle(Theme.accent).font(.system(size: 12))
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(T("取消", "Cancel")) { show = false }.buttonStyle(.kiln)
                if choices == nil {
                    Button(T("登录", "Sign in"), action: login).buttonStyle(.kilnPrimary)
                        .disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            if let account {
                server = account.server ?? server
                username = account.loginName ?? ""
            }
        }
        .task(id: server) {
            // 读取注册地址（失败时不显示）
            try? await Task.sleep(nanoseconds: 500_000_000)
            registerURL = (try? await Yggdrasil.resolve(server)).flatMap { $0.meta["meta"]["links"]["register"].string }
        }
    }

    private func login() {
        guard !busy else { return }
        busy = true
        error = nil
        let server = server, username = username.trimmingCharacters(in: .whitespaces), password = password
        Task { @MainActor in
            defer { busy = false }
            do {
                let (root, meta) = try await Yggdrasil.resolve(server)
                let name = Yggdrasil.serverName(meta, root: root)
                let session = try await Yggdrasil.authenticate(root: root, username: username, password: password)
                self.password = ""
                if let selected = session.selected {
                    finish(root: root, name: name, profile: selected, access: session.accessToken, client: session.clientToken)
                } else if session.profiles.count == 1 {
                    select(session.profiles[0], (root, name, session))
                } else if session.profiles.isEmpty {
                    error = T("这个账号还没有角色，请先在皮肤站创建角色。", "This account has no characters yet. Create one on the skin site first.")
                } else {
                    choices = (root, name, session)
                }
            } catch {
                self.error = error.friendly
            }
        }
    }

    private func select(_ p: Yggdrasil.Profile, _ c: (root: String, name: String, session: Yggdrasil.Session)) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let s = try await Yggdrasil.refresh(root: c.root, accessToken: c.session.accessToken, clientToken: c.session.clientToken, select: p)
                finish(root: c.root, name: c.name, profile: s.selected ?? p, access: s.accessToken, client: s.clientToken)
            } catch { self.error = error.friendly }
        }
    }

    private func finish(root: String, name: String, profile: Yggdrasil.Profile, access: String, client: String) {
        AccountStore.shared.addYggdrasil(root: root, serverName: name, loginName: username.trimmingCharacters(in: .whitespaces),
                                         profile: profile, accessToken: access, clientToken: client)
        FaceCache.shared.invalidate()
        Hint.show(T("已登录 \(profile.name)（\(name)）", "Signed in as \(profile.name) (\(name))"), .green)
        show = false
    }
}

// MARK: - 皮肤设置

struct SkinSheet: View {
    let account: Account
    @Binding var show: Bool
    @PState private var store = AccountStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("\(account.name) 的皮肤", "Skin for \(account.name)")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
            switch account.kind {
            case .offline: OfflineSkinEditor(account: account, show: $show)
            case .microsoft: MicrosoftSkinEditor(account: account, show: $show)
            case .yggdrasil:
                Text(T("外置登录账号的皮肤在 \(account.serverName ?? "皮肤站") 上管理，修改后重新启动游戏即可生效。",
                       "Skins for third-party accounts are managed on \(account.serverName ?? "the skin site"). Changes apply the next time you launch."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(T("关闭", "Close")) { show = false }.buttonStyle(.kiln)
                    Button(T("打开 \(account.serverName ?? "皮肤站")", "Open \(account.serverName ?? "skin site")")) {
                        if let root = account.server, let u = URL(string: root), let host = u.host { Links.open("https://\(host)") }
                    }.buttonStyle(.kilnPrimary)
                }
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

private struct OfflineSkinEditor: View {
    let account: Account
    @Binding var show: Bool
    enum Mode: Hashable { case none, file, premium }
    @PState private var mode: Mode = .none
    @PState private var file: String?
    @PState private var slim = false
    @PState private var premium = ""
    @PState private var preview: CGImage?
    @PState private var previewSlim = false
    @PState private var error: String?

    var body: some View {
        Segmented(items: [(Mode.none, T("默认", "Default")), (.file, T("本地图片", "Image file")), (.premium, T("同名正版玩家", "Same-name player"))],
                  selection: $mode)
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Theme.panel2
                if mode == .none {
                    Text("Steve / Alex").font(.system(size: 11)).foregroundStyle(Theme.text3)
                } else {
                    PixelImage(image: preview.flatMap { SkinRender.front($0, slim: previewSlim) }).padding(10)
                }
            }
            .frame(width: 96, height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                mode = .file
                use(url)
                return true
            }
            VStack(alignment: .leading, spacing: 10) {
                switch mode {
                case .none:
                    Text(T("游戏中显示默认皮肤。", "The game shows a default skin."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                case .file:
                    Button(T("选择皮肤图片…", "Choose skin image…")) { choose() }.buttonStyle(.kiln)
                    Segmented(items: [(false, T("经典（Steve）", "Classic (Steve)")), (true, T("纤细（Alex）", "Slim (Alex)"))], selection: $slim)
                        .onChange(of: slim) { _, v in previewSlim = v }
                    Text(T("64×64 或 64×32 的 PNG，也可以拖到左边。", "A 64×64 or 64×32 PNG; you can also drop it on the left."))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                case .premium:
                    HStack {
                        TextField(T("正版玩家名称", "Player name"), text: $premium).textFieldStyle(.roundedBorder).onSubmit(loadPremium)
                        Button(T("预览", "Preview"), action: loadPremium).buttonStyle(.kiln)
                    }
                    Text(T("使用该正版玩家当前的皮肤，每天更新一次。", "Uses that player's current skin, refreshed daily."))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
                if let error { Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
                Text(T("离线皮肤由 Kiln 在本机通过 authlib-injector 提供，只在你自己的游戏中显示。",
                       "Kiln serves offline skins locally through authlib-injector; only you see them in your game."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        if mode == .file {
            SkinLibraryStrip(selected: file) { item in
                file = item.file; slim = item.slim; previewSlim = item.slim
                preview = SkinRender.load(item.url); error = nil
            }
        }
        HStack {
            Spacer()
            Button(T("取消", "Cancel")) { show = false }.buttonStyle(.kiln)
            Button(T("保存", "Save"), action: save).buttonStyle(.kilnPrimary)
                .disabled(mode == .file && file == nil || mode == .premium && premium.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            let s = account.skin
            file = s?.file
            slim = s?.slim ?? false
            previewSlim = slim
            premium = s?.premium ?? account.name
            mode = s?.file != nil ? .file : s?.premium != nil ? .premium : .none
            if let f = file { preview = SkinRender.load(Skins.file(f)) }
            else if s?.premium != nil { loadPremium() }
        }
        .onChange(of: mode) { _, m in
            error = nil
            if m == .file { preview = file.flatMap { SkinRender.load(Skins.file($0)) }; previewSlim = slim }
            if m == .premium { loadPremium() }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        use(url)
    }

    private func use(_ url: URL) {
        do {
            file = try Skins.addToLibrary(data: Data(contentsOf: url), slim: slim, label: url.deletingPathExtension().lastPathComponent).file
            preview = SkinRender.load(Skins.file(file!))
            previewSlim = slim
            error = nil
        } catch { self.error = error.friendly }
    }

    private func loadPremium() {
        let name = premium.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            do {
                let (url, s) = try await Skins.premium(name)
                preview = SkinRender.load(url)
                previewSlim = s
                error = nil
            } catch {
                preview = nil
                self.error = error.friendly
            }
        }
    }

    private func save() {
        switch mode {
        case .none: AccountStore.shared.setSkin(account, nil)
        case .file: AccountStore.shared.setSkin(account, Account.OfflineSkin(file: file, slim: slim))
        case .premium: AccountStore.shared.setSkin(account, Account.OfflineSkin(premium: premium.trimmingCharacters(in: .whitespaces)))
        }
        FaceCache.shared.invalidate()
        Hint.show(T("皮肤已保存，下次启动游戏时生效", "Skin saved; it applies the next time you launch"), .green)
        show = false
    }
}

/// 皮肤库：用过的皮肤一排小头像，点一下换上；右键可以移除
struct SkinLibraryStrip: View {
    var selected: String?
    let onPick: (Skins.SavedSkin) -> Void
    @PState private var items: [Skins.SavedSkin] = []
    @PState private var faces: [String: CGImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("皮肤库", "Skin library")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            if items.isEmpty {
                Text(T("上传或导入过的皮肤会留在这里，之后一键换回去。", "Skins you upload or import are kept here so you can switch back in one click."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            Button { onPick(item) } label: {
                                ZStack {
                                    Theme.panel2
                                    if let f = faces[item.file] { PixelImage(image: f).padding(4) }
                                }
                                .frame(width: 34, height: 34)
                                .overlay(Rectangle().stroke(selected == item.file ? Theme.accent : Theme.stroke, lineWidth: selected == item.file ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .help(item.label + (item.slim ? T("（纤细）", " (slim)") : ""))
                            .contextMenu {
                                Button(T("从皮肤库移除", "Remove from library")) { Skins.removeFromLibrary(item); reload() }
                                Button(T("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .onAppear(perform: reload)
    }

    func reload() {
        items = Skins.library()
        for item in items where faces[item.file] == nil {
            if let img = SkinRender.load(item.url), let f = SkinRender.face(img) { faces[item.file] = f }
        }
    }
}

/// 微软账号的皮肤：本地图片、别的正版玩家的皮肤、皮肤库三种来源；换之前先把当前皮肤存进皮肤库
private struct MicrosoftSkinEditor: View {
    let account: Account
    @Binding var show: Bool
    @PState private var profile: Skins.MinecraftProfile?
    @PState private var current: CGImage?
    @PState private var newFile: URL?
    @PState private var newLabel = ""
    @PState private var librarySelection: String?
    @PState private var playerName = ""
    @PState private var slim = false
    @PState private var cape: String = ""
    @PState private var busy = false
    @PState private var dropping = false
    @PState private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Theme.panel2
                if let img = newFile.flatMap(SkinRender.load) ?? current {
                    PixelImage(image: SkinRender.front(img, slim: slim)).padding(10)
                } else if profile == nil && error == nil {
                    ProgressView().controlSize(.small)
                }
                if dropping { Rectangle().stroke(Theme.accent, lineWidth: 2) }
            }
            .frame(width: 96, height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                pick(url, label: url.deletingPathExtension().lastPathComponent)
                return true
            } isTargeted: { dropping = $0 }
            .help(T("也可以把皮肤图片拖到这里", "You can also drop a skin image here"))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(T("选择图片…", "Choose image…")) { choose() }.buttonStyle(.kiln)
                    Button(T("恢复默认", "Reset")) { run { try await Skins.reset(token: $0) } }.buttonStyle(.kiln)
                }
                HStack {
                    TextField(T("用某个正版玩家的皮肤", "Use a player's skin"), text: $playerName)
                        .textFieldStyle(.roundedBorder).onSubmit(fetchPlayer)
                    Button(T("获取", "Get"), action: fetchPlayer).buttonStyle(.kiln)
                        .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Segmented(items: [(false, T("经典（Steve）", "Classic (Steve)")), (true, T("纤细（Alex）", "Slim (Alex)"))], selection: $slim)
                if let capes = profile?.capes, !capes.isEmpty {
                    Text(T("披风", "Cape")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                    Picker("", selection: $cape) {
                        Text(T("不显示", "None")).tag("")
                        ForEach(capes) { Text($0.alias).tag($0.id) }
                    }
                    .labelsHidden()
                }
                if let error { Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
            }
        }
        SkinLibraryStrip(selected: librarySelection) { item in
            newFile = item.url; newLabel = item.label; slim = item.slim; librarySelection = item.file; error = nil
        }
        HStack {
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(T("取消", "Cancel")) { show = false }.buttonStyle(.kiln)
            Button(T("应用", "Apply"), action: apply).buttonStyle(.kilnPrimary).disabled(busy || profile == nil)
        }
        .task { await load() }
    }

    private func token() async throws -> String { try await AccountStore.shared.login(account).accessToken }

    private func load() async {
        do {
            let p = try await Skins.profile(token: try await token())
            profile = p
            slim = p.slim
            cape = p.capes.first(where: \.active)?.id ?? ""
            if let url = p.skinURL, let data = try? await Net.data([url.replacingOccurrences(of: "http://", with: "https://")]) {
                current = SkinRender.load(data)
            }
        } catch { self.error = error.friendly }
    }

    private func pick(_ url: URL, label: String, slim: Bool? = nil) {
        do {
            try Skins.validate(Data(contentsOf: url))
            newFile = url; newLabel = label; librarySelection = nil; error = nil
            if let slim { self.slim = slim }
        } catch { self.error = error.friendly }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pick(url, label: url.deletingPathExtension().lastPathComponent)
    }

    private func fetchPlayer() {
        let name = playerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            do {
                let (url, s) = try await Skins.premium(name)
                pick(url, label: name, slim: s)
            } catch { self.error = error.friendly }
        }
    }

    private func run(_ action: @escaping (String) async throws -> Void) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                await backupCurrent()
                try await action(try await token())
                newFile = nil
                await load()
                FaceCache.shared.invalidate()
                Hint.show(T("已更新", "Updated"), .green)
            } catch { self.error = error.friendly }
        }
    }

    /// 换皮肤之前把现在的皮肤存进皮肤库，换错了还能换回来
    private func backupCurrent() async {
        guard let url = profile?.skinURL,
              let data = try? await Net.data([url.replacingOccurrences(of: "http://", with: "https://")]) else { return }
        try? Skins.addToLibrary(data: data, slim: profile?.slim ?? false, label: T("\(account.name) 之前的皮肤", "\(account.name)'s previous skin"))
    }

    private func apply() {
        let file = newFile, slim = slim, cape = cape, label = newLabel
        let skinChanged = file != nil || slim != profile?.slim
        let capeChanged = cape != (profile?.capes.first(where: \.active)?.id ?? "")
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let t = try await token()
                if skinChanged {
                    if let file {
                        await backupCurrent()
                        try await Skins.upload(token: t, skin: file, slim: slim)
                        try? Skins.addToLibrary(data: Data(contentsOf: file), slim: slim, label: label.isEmpty ? account.name : label)
                    } else if let url = profile?.skinURL {
                        // 只更换模型：重新上传当前皮肤
                        let tmp = Paths.cache.appendingPathComponent("current-skin.png")
                        try await Net.data([url.replacingOccurrences(of: "http://", with: "https://")]).write(to: tmp)
                        try await Skins.upload(token: t, skin: tmp, slim: slim)
                    }
                }
                if capeChanged { try await Skins.setCape(token: t, id: cape.isEmpty ? nil : cape) }
                FaceCache.shared.invalidate()
                Hint.show(T("皮肤已更新", "Skin updated"), .green)
                show = false
            } catch { self.error = error.friendly }
        }
    }
}

// MARK: - 正版档案

/// 微软账号的档案：拥有的游戏、联机与聊天权限、封禁状态，以及改名（30 天一次，输入时实时检查名称能不能用）
struct ProfileSheet: View {
    let account: Account
    @Binding var show: Bool
    @PState private var face: CGImage?
    @PState private var ownership: MinecraftServices.Ownership?
    @PState private var attributes: MinecraftServices.Attributes?
    @PState private var nameChange: MinecraftServices.NameChange?
    @PState private var loadError: String?
    @PState private var newName = ""
    @PState private var nameStatus: MinecraftServices.NameStatus?
    @PState private var checking = false
    @PState private var busy = false
    @PState private var confirming = false
    @PState private var error: String?

    private var current: Account { AccountStore.shared.account(id: account.id) ?? account }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Theme.panel2
                    if let face { PixelImage(image: face) }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(current.uuid, forType: .string)
                        Hint.show(T("已复制 UUID", "UUID copied"), .green)
                    } label: {
                        Text(current.uuid).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text3)
                    }
                    .buttonStyle(.plain).help(T("复制 UUID", "Copy UUID"))
                }
            }
            if let loadError {
                Text(loadError).font(.system(size: 12)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            } else if ownership == nil && attributes == nil {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(T("正在读取……", "Loading…")).font(.system(size: 12)).foregroundStyle(Theme.text2) }
            }
            if let o = ownership { row(T("游戏", "Game"), ownershipText(o)) }
            if let a = attributes { statusRows(a) }
            Divider()
            renameSection
            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(T("关闭", "Close")) { show = false }.buttonStyle(.kiln)
            }
        }
        .padding(22)
        .frame(width: 440)
        .task { await load() }
    }

    private func row(_ title: String, _ value: String, color: Color = Theme.text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 52, alignment: .leading)
            Text(value).font(.system(size: 12.5)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ownershipText(_ o: MinecraftServices.Ownership) -> String {
        var s = o.javaPurchased ? T("Minecraft: Java 版（已购买）", "Minecraft: Java Edition (purchased)")
                                : T("Minecraft: Java 版（Xbox Game Pass）", "Minecraft: Java Edition (Xbox Game Pass)")
        let extra = [o.bedrock ? T("基岩版", "Bedrock Edition") : nil, o.dungeons ? "Dungeons" : nil, o.legends ? "Legends" : nil].compactMap { $0 }
        if !extra.isEmpty { s += T("；还拥有 ", "; also owns ") + extra.joined(separator: T("、", ", ")) }
        return s
    }

    @ViewBuilder private func statusRows(_ a: MinecraftServices.Attributes) -> some View {
        if let ban = a.multiplayerBan {
            let until = ban.expires.map { T("，到 \(Self.dateText($0)) 解除", " until \(Self.dateText($0))") } ?? T("（永久）", " (permanent)")
            row(T("联机", "Online"), T("已被禁止进入多人游戏和 Realms", "Banned from multiplayer and Realms") + until
                + (ban.reason.map { T("。原因：", ". Reason: ") + $0 } ?? ""), color: Theme.red)
        } else {
            let items = [(T("多人游戏", "Multiplayer"), a.multiplayer), ("Realms", a.realms), (T("聊天", "Chat"), a.chat)]
            let off = items.filter { !$0.1 }.map(\.0)
            row(T("联机", "Online"), off.isEmpty ? T("多人游戏、Realms 和聊天都可以正常使用", "Multiplayer, Realms and chat are all available")
                                               : T("已关闭：", "Turned off: ") + off.joined(separator: T("、", ", ")) + T("（可在 Xbox 隐私设置或家庭设置中修改）", " (change it in Xbox privacy or family settings)"),
                color: off.isEmpty ? Theme.green : Theme.yellow)
        }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("修改玩家名称", "Change player name")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            HStack {
                TextField(T("新名称", "New name"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(rename)
                if confirming {
                    Button(T("取消", "Cancel")) { confirming = false }.buttonStyle(.kiln)
                }
                Button(confirming ? T("确认改名", "Confirm") : T("改名", "Rename"), action: rename).buttonStyle(.kilnPrimary)
                    .disabled(busy || nameStatus != .available || nameChange?.allowed == false)
            }
            Text(renameHint.0).font(.system(size: 11)).foregroundStyle(renameHint.1).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
        }
        .task(id: newName) { confirming = false; await check() }
    }

    private var renameHint: (String, Color) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if confirming {
            return (T("把 \(current.name) 改成 \(n)？改名后 30 天内不能再改。", "Change \(current.name) to \(n)? You won't be able to change it again for 30 days."), Theme.yellow)
        }
        if let nc = nameChange, !nc.allowed {
            return (T("距离上次改名还不到 30 天", "It's been less than 30 days since your last name change")
                    + (nc.nextChange.map { T("，\(Self.dateText($0)) 以后可以再改。", "; you can change it again after \(Self.dateText($0)).") } ?? "。"), Theme.yellow)
        }
        if n.isEmpty { return (T("每 30 天可以改一次名，改名后旧名称会保留 37 天才放出给别人用。", "You can change your name once every 30 days. Your old name is held for 37 days before others can take it."), Theme.text3) }
        if !MinecraftServices.isValidName(n) { return (T("只能用 3～16 个字母、数字或下划线", "Use 3–16 letters, digits or underscores"), Theme.red) }
        if n.caseInsensitiveCompare(current.name) == .orderedSame && n != current.name { return (T("只改大小写也算一次改名", "Changing only the capitalization still counts as a name change"), Theme.text3) }
        if checking { return (T("正在检查……", "Checking…"), Theme.text3) }
        switch nameStatus {
        case .available: return (T("\(n) 可以使用", "\(n) is available"), Theme.green)
        case .taken: return (T("\(n) 已经被别人用了", "\(n) is already taken"), Theme.red)
        case .notAllowed: return (T("\(n) 不能使用", "\(n) isn't allowed"), Theme.red)
        case nil: return ("", Theme.text3)
        }
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func token() async throws -> String { try await AccountStore.shared.login(current).accessToken }

    private func load() async {
        face = await FaceCache.shared.face(for: account)
        do {
            let t = try await token()
            async let o = try? MinecraftServices.ownership(token: t)
            async let a = try? MinecraftServices.attributes(token: t)
            async let n = try? MinecraftServices.nameChange(token: t)
            (ownership, attributes, nameChange) = await (o, a, n)
            if ownership == nil && attributes == nil && nameChange == nil {
                loadError = T("读取档案失败，请检查网络后重试。", "Couldn't load the profile. Check your network and try again.")
            }
        } catch { loadError = error.friendly }
    }

    private func check() async {
        nameStatus = nil
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard MinecraftServices.isValidName(n), n != current.name else { return }
        checking = true
        defer { checking = false }
        // 停止输入半秒后再查，避免每打一个字就请求一次
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        do {
            let status = try await MinecraftServices.nameStatus(n, token: try await token())
            if !Task.isCancelled { nameStatus = status }
        } catch { if !Task.isCancelled { self.error = error.friendly } }
    }

    private func rename() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard nameStatus == .available, !busy else { return }
        // 先按一次“改名”出确认，再按一次才真的改
        guard confirming else { confirming = true; return }
        confirming = false
        Task { @MainActor in
            busy = true
            error = nil
            defer { busy = false }
            do {
                let name = try await MinecraftServices.changeName(to: n, token: try await token())
                AccountStore.shared.updateName(account, to: name)
                FaceCache.shared.invalidate()
                newName = ""
                nameChange = try? await MinecraftServices.nameChange(token: try await token())
                Hint.show(T("已改名为 \(name)", "Renamed to \(name)"), .green)
            } catch { self.error = error.friendly }
        }
    }
}
