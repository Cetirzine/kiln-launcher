import SwiftUI
import AppKit
import Observation
import LauncherCore

/// 方块图标使用 Minecraft 原版材质。
/// 材质不随应用分发，而是从用户本机已安装的游戏客户端 jar 中读取（Mojang 官方下载的文件），缓存到本地。
@MainActor
@Observable
final class BlockTextures {
    static let shared = BlockTextures()

    struct Faces {
        let top: CGImage
        let left: CGImage
        let right: CGImage
    }

    private(set) var faces: [String: Faces] = [:]
    /// 在本机游戏中找不到材质的自定义图标
    private(set) var missing: Set<String> = []
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var jars: [URL] = []

    /// 内置图标种类 → 顶面、左面（正面）、右面材质，以及顶面的着色
    private static let specs: [String: (top: String, left: String, right: String, tint: UInt32?)] = [
        "Grass": ("grass_block_top", "grass_block_side", "grass_block_side", 0x91BD59),
        "CommandBlock": ("command_block_side", "command_block_front", "command_block_side", nil),
        "CobbleStone": ("cobblestone", "cobblestone", "cobblestone", nil),
        "GoldBlock": ("gold_block", "gold_block", "gold_block", nil),
        "Anvil": ("anvil_top", "anvil", "anvil", nil),
        "NeoForge": ("smithing_table_top", "smithing_table_front", "smithing_table_side", nil),
        "Fabric": ("loom_top", "loom_front", "loom_side", nil),
        "Quilt": ("purple_wool", "purple_wool", "purple_wool", nil),
        "GrassPath": ("dirt_path_top", "dirt_path_side", "dirt_path_side", nil),
        "RedstoneBlock": ("redstone_block", "redstone_block", "redstone_block", nil),
        "Kiln": ("furnace_top", "furnace_front_on", "furnace_side", nil),
        "block:bookshelf": ("oak_planks", "bookshelf", "bookshelf", nil),
    ]

    /// 图标选择器中列出的方块（按游戏创造模式物品栏的大致顺序）
    static let picker: [String] = [
        "Grass", "block:dirt", "block:podzol", "block:mycelium", "block:stone", "block:cobblestone", "block:mossy_cobblestone",
        "block:deepslate", "block:sand", "block:gravel", "block:oak_log", "block:birch_log", "block:cherry_log", "block:oak_planks",
        "block:cherry_planks", "block:bricks", "block:stone_bricks", "block:moss_block", "block:snow", "block:ice", "block:packed_ice",
        "block:crafting_table", "block:furnace", "block:bookshelf", "block:jukebox", "block:note_block", "block:barrel", "block:tnt",
        "block:pumpkin", "block:melon", "block:hay_block", "block:honey_block", "block:slime_block", "block:glowstone",
        "block:sea_lantern", "block:amethyst_block", "block:iron_block", "block:gold_block", "block:diamond_block",
        "block:emerald_block", "block:lapis_block", "block:redstone_block", "block:copper_block", "block:netherite_block",
        "block:diamond_ore", "block:ancient_debris", "block:obsidian", "block:crying_obsidian", "block:netherrack",
        "block:soul_sand", "block:end_stone", "block:purpur_block", "block:prismarine", "block:sculk",
        "block:command_block", "block:anvil", "block:smithing_table", "block:loom",
    ]

    private static var cacheDir: URL {
        let u = Paths.cache.appendingPathComponent("block-textures", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 从缓存或本机的游戏客户端中加载内置图标的材质
    func load(from instances: [McInstance]) async {
        // 优先使用较新的版本（1.13 起材质路径为 textures/block/）
        jars = instances.filter { $0.category != .error }
            .sorted { $0.releaseTime > $1.releaseTime }
            .map(\.clientJar)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        await ensure(Array(Self.specs.keys) + instances.compactMap { $0.setup.icon })
    }

    /// 确保这些图标的材质已加载（自定义方块按需从游戏文件中读取）
    func ensure(_ kinds: [String]) async {
        // 等待正在进行的加载完成，再决定还缺哪些
        while loading { try? await Task.sleep(nanoseconds: 50_000_000) }
        let todo = Set(kinds).filter { faces[$0] == nil && !missing.contains($0) && (Self.specs[$0] != nil || $0.hasPrefix("block:")) }
        guard !todo.isEmpty else { return }
        loading = true
        defer { loading = false }
        let specs = Self.specs, jars = jars, cacheDir = Self.cacheDir
        let (result, notFound): ([String: Faces], Set<String>) = await Task.detached(priority: .utility) {
            // 每个图标的候选材质
            var candidates: [String: [[String]]] = [:]  // kind → [顶面候选, 正面候选, 侧面候选]
            for kind in todo {
                if let s = specs[kind] {
                    candidates[kind] = [[s.top], [s.left], [s.right]]
                } else {
                    let n = String(kind.dropFirst("block:".count)).lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                    candidates[kind] = [["\(n)_top", n, "\(n)_side"], ["\(n)_front", "\(n)_side", n], ["\(n)_side", n]]
                }
            }
            let names = Set(candidates.values.flatMap { $0.flatMap { $0 } })
            // 缓存中没有的，从客户端 jar 中一次性解压
            let absent = names.filter { !FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("\($0).png").path) }
            if !absent.isEmpty, let jar = jars.first {
                _ = try? Zip.run(["-o", "-q", "-j", jar.path] + absent.map { "assets/minecraft/textures/block/\($0).png" } + ["-d", cacheDir.path])
            }
            var images: [String: CGImage] = [:]
            for n in names {
                if let img = Self.cgImage(try? Data(contentsOf: cacheDir.appendingPathComponent("\(n).png"))).flatMap(Self.firstFrame) {
                    images[n] = img
                }
            }
            var out: [String: Faces] = [:]
            var notFound = Set<String>()
            for (kind, c) in candidates {
                guard let t = c[0].lazy.compactMap({ images[$0] }).first,
                      let l = c[1].lazy.compactMap({ images[$0] }).first,
                      let r = c[2].lazy.compactMap({ images[$0] }).first else { notFound.insert(kind); continue }
                let tint = specs[kind]?.tint
                out[kind] = Faces(top: tint.flatMap { Self.tint(t, $0) } ?? t, left: l, right: r)
            }
            return (out, notFound)
        }.value
        faces.merge(result) { $1 }
        // 本机没有游戏文件时不标记为缺失，等安装游戏后再试
        if !jars.isEmpty { missing.formUnion(notFound) }
    }

    /// 检查自定义材质名是否存在于本机游戏中
    func exists(_ kind: String) async -> Bool {
        await ensure([kind])
        return faces[kind] != nil
    }

    nonisolated private static func cgImage(_ data: Data?) -> CGImage? {
        guard let data, let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }

    /// 动画材质是纵向排列的多帧，只取第一帧
    nonisolated private static func firstFrame(_ img: CGImage) -> CGImage? {
        img.height > img.width ? img.cropping(to: CGRect(x: 0, y: 0, width: img.width, height: img.width)) : img
    }

    /// 按生物群系颜色给灰度材质着色（与游戏相同的正片叠底）
    nonisolated private static func tint(_ img: CGImage, _ color: UInt32) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let tr = Int((color >> 16) & 0xff), tg = Int((color >> 8) & 0xff), tb = Int(color & 0xff)
        for i in 0..<(w * h) {
            buf[i * 4] = UInt8(Int(buf[i * 4]) * tr / 255)
            buf[i * 4 + 1] = UInt8(Int(buf[i * 4 + 1]) * tg / 255)
            buf[i * 4 + 2] = UInt8(Int(buf[i * 4 + 2]) * tb / 255)
        }
        return ctx.makeImage()
    }
}

/// 用原版材质渲染的等轴测方块（与游戏物品栏中的方块相同的视角与明暗）
struct TexturedBlock: View {
    let faces: BlockTextures.Faces

    var body: some View {
        Canvas { ctx, size in
            // 物品栏中方块的投影：顶面为菱形，两个侧面为平行四边形
            let g = IsoGeometry(size)
            let (top, left, right, center, leftBottom, bottom) = (g.top, g.left, g.right, g.center, g.leftBottom, g.bottom)

            func face(_ image: CGImage, origin a: CGPoint, u b: CGPoint, v d: CGPoint, shade: Double) {
                let t = CGAffineTransform(a: b.x - a.x, b: b.y - a.y, c: d.x - a.x, d: d.y - a.y, tx: a.x, ty: a.y)
                ctx.drawLayer { layer in
                    layer.concatenate(t)
                    let img = layer.resolve(Image(decorative: image, scale: 1).interpolation(.none))
                    layer.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    if shade > 0 { layer.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(.black.opacity(shade))) }
                }
            }
            // 顶面：从左角开始，u 指向后角，v 指向前角
            face(faces.top, origin: left, u: top, v: center, shade: 0)
            // 左面（正面）：左上 → 中上，向下到左下
            face(faces.left, origin: left, u: center, v: leftBottom, shade: 0.2)
            // 右面：中上 → 右上，向下到中下
            face(faces.right, origin: center, u: right, v: bottom, shade: 0.4)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
