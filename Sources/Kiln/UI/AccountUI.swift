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
                Text(T("密码只用于这一次登录，Kiln 不会保存密码；登录后只在钥匙串中保存服务器下发的令牌。",
                       "Your password is only used for this sign-in and is never stored. Kiln keeps only the token issued by the server, in the Keychain."))
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
            VStack(alignment: .leading, spacing: 10) {
                switch mode {
                case .none:
                    Text(T("游戏中显示默认皮肤。", "The game shows a default skin."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                case .file:
                    Button(T("选择皮肤图片…", "Choose skin image…")) { choose() }.buttonStyle(.kiln)
                    Segmented(items: [(false, T("经典（Steve）", "Classic (Steve)")), (true, T("纤细（Alex）", "Slim (Alex)"))], selection: $slim)
                        .onChange(of: slim) { _, v in previewSlim = v }
                    Text(T("64×64 或 64×32 的 PNG。", "A 64×64 or 64×32 PNG."))
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
        do {
            file = try Skins.importSkin(url)
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

private struct MicrosoftSkinEditor: View {
    let account: Account
    @Binding var show: Bool
    @PState private var profile: Skins.MinecraftProfile?
    @PState private var current: CGImage?
    @PState private var newFile: URL?
    @PState private var slim = false
    @PState private var cape: String = ""
    @PState private var busy = false
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
            }
            .frame(width: 96, height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(T("选择新皮肤…", "Choose new skin…")) { choose() }.buttonStyle(.kiln)
                    Button(T("恢复默认", "Reset")) { run { try await Skins.reset(token: $0) } }.buttonStyle(.kiln)
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

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Skins.validate(Data(contentsOf: url)); newFile = url; error = nil } catch { self.error = error.friendly }
    }

    private func run(_ action: @escaping (String) async throws -> Void) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await action(try await token())
                newFile = nil
                await load()
                Hint.show(T("已更新", "Updated"), .green)
            } catch { self.error = error.friendly }
        }
    }

    private func apply() {
        let file = newFile, slim = slim, cape = cape
        let skinChanged = file != nil || slim != profile?.slim
        let capeChanged = cape != (profile?.capes.first(where: \.active)?.id ?? "")
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let t = try await token()
                if skinChanged {
                    if let file {
                        try await Skins.upload(token: t, skin: file, slim: slim)
                    } else if let url = profile?.skinURL {
                        // 只更换模型：重新上传当前皮肤
                        let tmp = Paths.cache.appendingPathComponent("current-skin.png")
                        try await Net.data([url.replacingOccurrences(of: "http://", with: "https://")]).write(to: tmp)
                        try await Skins.upload(token: t, skin: tmp, slim: slim)
                    }
                }
                if capeChanged { try await Skins.setCape(token: t, id: cape.isEmpty ? nil : cape) }
                Hint.show(T("皮肤已更新", "Skin updated"), .green)
                show = false
            } catch { self.error = error.friendly }
        }
    }
}
