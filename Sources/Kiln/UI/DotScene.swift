import SwiftUI
import AppKit

// MARK: - 主页主视觉：横版点阵场景
//
// 统一构图：版本新增的地形里，左边是这个版本的新生物，右边是史蒂夫，侧视。
// 一个方块 16×16 个点（与游戏贴图同分辨率），史蒂夫正好 32 个点高。
// 地形等不动的部分只在尺寸变化时画一次并缓存，每帧只画会动的点。

/// 点阵缓冲：cols × rows 个点，值为 0xRRGGBB | 0xFF000000；0 表示空
struct DotBuffer {
    let cols: Int
    let rows: Int
    var px: [UInt32]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        px = Array(repeating: 0, count: cols * rows)
    }

    subscript(x: Int, y: Int) -> UInt32 {
        get { x >= 0 && y >= 0 && x < cols && y < rows ? px[y * cols + x] : 0 }
        set { if x >= 0 && y >= 0 && x < cols && y < rows { px[y * cols + x] = newValue } }
    }

    mutating func set(_ x: Int, _ y: Int, _ rgb: UInt32) { self[x, y] = 0xFF00_0000 | rgb }

    mutating func fill(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ rgb: UInt32) {
        for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { set(x, y, rgb) } }
    }

    /// 把精灵画到 (x, 底边 bottom)，可缩放成 w×h（最近邻），用于落地时的压扁效果
    mutating func blit(_ s: Sprite, x: Int, bottom: Int, w: Int? = nil, h: Int? = nil, flip: Bool = false) {
        let tw = w ?? s.width, th = h ?? s.height
        for dy in 0..<th {
            let sy = dy * s.height / th
            for dx in 0..<tw {
                let sx = dx * s.width / tw
                let c = s.px[sy * s.width + (flip ? s.width - 1 - sx : sx)]
                if c != 0 { self[x + dx, bottom - th + 1 + dy] = c }
            }
        }
    }
}

/// 像素精灵：字符图 + 调色板
struct Sprite {
    let width: Int
    let height: Int
    let px: [UInt32]

    init(_ rows: [String], _ palette: [Character: UInt32]) {
        width = rows.map(\.count).max() ?? 0
        height = rows.count
        var p = [UInt32](repeating: 0, count: width * height)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                if let c = palette[ch] { p[y * width + x] = 0xFF00_0000 | c }
            }
        }
        px = p
    }

    init(width: Int, height: Int, _ f: (Int, Int) -> UInt32?) {
        self.width = width
        self.height = height
        var p = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { if let c = f(x, y) { p[y * width + x] = 0xFF00_0000 | c } } }
        px = p
    }
}

/// 一个版本的场景：静态部分画一次，动态部分每帧画
protocol DotScene {
    var id: String { get }
    var background: UInt32 { get }
    func paintStatic(_ b: inout DotBuffer)
    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast)
}

/// 场景里的人物：登录的玩家（用他自己的皮肤，没有自定义皮肤就是默认外观），以及其他所有角色（一律用作者 NelsonPence 的皮肤）
struct SceneCast {
    var player: PlayerLook = .steve
    var author: PlayerLook = .alex
}

/// 可复现的伪随机噪声，用来给方块加纹理
@inline(__always) func noise(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65_535
}

@inline(__always) func pick(_ tones: [UInt32], _ x: Int, _ y: Int, _ seed: Int = 0) -> UInt32 {
    tones[min(tones.count - 1, Int(noise(x, y, seed) * Double(tones.count)))]
}

/// 4×4 Bayer 有序抖动：frac 落在 [0,1]，返回这个点该用较亮的一侧
private let bayer4: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }
@inline(__always) func dither(_ x: Int, _ y: Int, _ frac: Double) -> Bool { bayer4[(y & 3) * 4 + (x & 3)] < frac }

/// 按 frac（0…1）在一组颜色之间做有序抖动的渐变，和官网的抖动风格一致
func ditherRamp(_ tones: [UInt32], _ frac: Double, _ x: Int, _ y: Int) -> UInt32 {
    let f = max(0, min(0.9999, frac)) * Double(tones.count - 1)
    let i = Int(f)
    return dither(x, y, f - Double(i)) ? tones[min(i + 1, tones.count - 1)] : tones[i]
}

/// 把 0xRRGGBB 调亮或调暗（k > 1 变亮）
func shade(_ c: UInt32, _ k: Double) -> UInt32 {
    func ch(_ v: UInt32) -> UInt32 { UInt32(max(0, min(255, Double(v) * k))) }
    return (ch((c >> 16) & 0xFF) << 16) | (ch((c >> 8) & 0xFF) << 8) | ch(c & 0xFF)
}

// MARK: - 玩家

/// 斜 45° 的玩家外观（身体转向画面左边的生物）：看得到正面，右侧再露出压窄、压暗的侧面。
/// 各部分都从皮肤贴图里取，与游戏的皮肤分辨率一致
struct PlayerLook {
    var headFront: Sprite      // 8×8
    var headSide: Sprite       // 4×8（左侧面压窄）
    var headFrontBlink: Sprite
    var bodyFront: Sprite      // 8×12
    var bodySide: Sprite       // 2×12
    var nearArm: Sprite        // 左臂：正面 + 外侧面，靠近镜头
    var farArm: Sprite         // 右臂：在身体后面，只露出 3 列
    var legs: Sprite           // 两条腿的正面 + 侧面，10×12
    /// 村民和灾厄村民的大鼻子垂过下巴的那一截（鼻子本身画在脸的正中间，只有这一个）
    var nose: Sprite?
    /// 村民抱在胸前的双手（有它时不画两只胳膊）
    var crossedArms: Sprite?

    init(headFront: Sprite, headSide: Sprite, headFrontBlink: Sprite? = nil, bodyFront: Sprite, bodySide: Sprite,
         nearArm: Sprite, farArm: Sprite, legs: Sprite, nose: Sprite? = nil, crossedArms: Sprite? = nil) {
        self.headFront = headFront; self.headSide = headSide; self.headFrontBlink = headFrontBlink ?? headFront
        self.bodyFront = bodyFront; self.bodySide = bodySide; self.nearArm = nearArm; self.farArm = farArm
        self.legs = legs; self.nose = nose; self.crossedArms = crossedArms
    }

    static let steve: PlayerLook = PlayerLook(skin: defaultSkin(), slim: false)!
    static let alex: PlayerLook = PlayerLook(skin: defaultSkin(alex: true), slim: true)!
    /// 掠夺者（1.14，对照原版）：比宽更高的灰色头，深色的眉带压在绿眼睛上，长鼻子垂过下巴；
    /// 深色外套上是暗红格纹，腰带中间一个灰色的扣子，红棕色的裤子
    static let pillager = PlayerLook(
        headFront: Sprite(["LLLLLLLL", "SSSSSSSS", "SSSSSSSS", "SSSSSSSS", "BBBBBBBB", "SkGSSGkS", "SSSnnSSS", "SSSnnSSS", "SMSnnSMS", "sSSnnSSs"],
                          ["L": 0xB4B6B8, "S": 0x9A9C9E, "s": 0x868A8E, "B": 0x3A3A3C, "k": 0x1E1E1D, "G": 0x3AA04A, "n": 0x7E8084, "M": 0x5A5C60]),
        headSide: Sprite(["LLLL", "SSSS", "SSSs", "SSSs", "BSSs", "SSSs", "SSss", "SSSs", "SSSs", "sSss"],
                         ["L": 0x9EA0A2, "S": 0x84868A, "s": 0x707276, "B": 0x343436]),
        bodyFront: Sprite(["cDcDDcDc", "DmDDmDDm", "cDcmcDcD", "DmDDmDmD", "cDcDDcDc", "DmDmDDmD", "cDcDcDcD", "KKKbbKKK", "DDDbbDDD", "mDmDDmDm", "DmDmmDmD", "mmDDDDmm"],
                          ["D": 0x2A2828, "c": 0x3A3434, "m": 0x6A2E34, "K": 0x1A1818, "b": 0x9A9C9E]),
        bodySide: Sprite(Array(repeating: "Dm", count: 7) + ["KK", "DD", "mD", "Dm", "mm"], ["D": 0x242222, "m": 0x58262C, "K": 0x161414]),
        nearArm: Sprite(["DmDDm", "mDmDm", "DmDDm", "mDmDm", "DmDDm", "mDmDm", "DmDDm", "cccSs", "SSSSs", "SSSSs", "SSSss", "sssss"],
                        ["D": 0x2A2828, "m": 0x6A2E34, "c": 0x3A3434, "S": 0x9A9C9E, "s": 0x7E8084]),
        farArm: Sprite(["DmD", "mDm", "DmD", "mDm", "DmD", "mDm", "DmD", "ccc", "SSS", "SSS", "SSs", "sss"],
                       ["D": 0x242222, "m": 0x58262C, "c": 0x343030, "S": 0x84868A, "s": 0x6E7074]),
        legs: Sprite(Array(repeating: "PpPPPpPPRr", count: 9) + ["pppppppprr", "BBBBBBBBbb", "BBBBBBBBbb"],
                     ["P": 0x8A4A2A, "p": 0x6A3420, "R": 0x6E3A22, "r": 0x582E1A, "B": 0x3A2418, "b": 0x2E1C12]),
        nose: Sprite(["nN", "nN"], ["n": 0x8A8C90, "N": 0x6E7074]))

    /// 村民（1.14，对照原版）：比宽更高的棕色头，一字眉、绿眼睛、长长的大鼻子；棕色长袍，双手抱在胸前，灰色的鞋
    static let villager = PlayerLook(
        headFront: Sprite(["HHHHHHHH", "SSSSSSSS", "SSSSSSSS", "SSSSSSSS", "SUUUUUUS", "SkGSSGkS", "SSSnnSSS", "SSSnnSSS", "SSMnnMSS", "sSSnnSSs"],
                          ["H": 0x94664E, "S": 0xA8765C, "s": 0x946450, "U": 0x4A3022, "k": 0x1E1E1D, "G": 0x3AA04A, "n": 0x8E5E46, "M": 0x6E4632]),
        headSide: Sprite(["HHHH", "SSSs", "SSSs", "SSSs", "USSs", "SSSs", "SSss", "SSSs", "SSSs", "sSss"],
                         ["H": 0x845A44, "S": 0x96684E, "s": 0x845A44, "U": 0x40281C]),
        bodyFront: Sprite(["RRRccRRR"] + Array(repeating: "RRRrRRRR", count: 10) + ["rrrrrrrr"], ["R": 0x7A5A4A, "r": 0x6A4C3E, "c": 0x5A3E32]),
        bodySide: Sprite(Array(repeating: "Rr", count: 12), ["R": 0x6A4C3E, "r": 0x5A4034]),
        nearArm: Sprite(Array(repeating: "RRRRr", count: 12), ["R": 0x7A5A4A, "r": 0x6A4C3E]),
        farArm: Sprite(Array(repeating: "RRr", count: 12), ["R": 0x6A4C3E, "r": 0x5A4034]),
        legs: Sprite(Array(repeating: "RRRrRRRRrr", count: 10) + ["GGGGGGGGgg", "GGGGGGGGgg"],
                     ["R": 0x7A5A4A, "r": 0x6A4C3E, "G": 0x7A7A7A, "g": 0x5E5E5E]),
        nose: Sprite(["nN", "nN"], ["n": 0x9A6A50, "N": 0x7E5440]),
        crossedArms: Sprite(["AAAAAAAAAA..", "AhhAAAAAhhAA", "AAAAAAAAAAAa", ".aaaaaaaaaa."], ["A": 0x6E4E40, "a": 0x5A3E32, "h": 0xA8765C]))

    /// 用字符图拼一张皮肤：脸的正面和左侧面由参数给出，身体、手臂、腿用调色板里的 T/t（上衣）、S/s（皮肤）、P/p（裤子）、G/g（鞋）
    static func buildSkin(front: [String], side: [String], palette pal: [Character: UInt32], armWidth: Int = 4) -> CGImage {
        var px = [UInt32](repeating: 0, count: 64 * 64)
        func put(_ x: Int, _ y: Int, _ rows: [String]) {
            for (dy, row) in rows.enumerated() { for (dx, ch) in row.enumerated() { if let c = pal[ch] { px[(y + dy) * 64 + x + dx] = c } } }
        }
        put(8, 8, front); put(16, 8, side)
        put(20, 20, Array(repeating: "TTTTTTTT", count: 5) + ["tttttttt"] + Array(repeating: "TTTTTTTT", count: 5) + ["tttttttt"])
        put(28, 20, Array(repeating: "TTTt", count: 11) + ["tttt"])
        let w = armWidth
        let arm = Array(repeating: String(repeating: "T", count: w), count: 8) + Array(repeating: String(repeating: "S", count: w), count: 3) + [String(repeating: "s", count: w)]
        let armSide = Array(repeating: "TTTt", count: 8) + Array(repeating: "SSSs", count: 3) + ["ssss"]
        put(44, 20, arm); put(40, 20, armSide); put(36, 52, arm); put(40, 52, armSide)
        let leg = Array(repeating: "PPPP", count: 9) + ["pppp", "GGGG", "gggg"]
        let legSide = Array(repeating: "PPPp", count: 9) + ["pppp", "GGGg", "gggg"]
        put(4, 20, leg); put(20, 52, leg); put(24, 52, legSide); put(0, 20, legSide)
        let bytes = px.flatMap { c -> [UInt8] in c == 0 ? [0, 0, 0, 0] : [UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF), 255] }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// 从 64×64（或旧版 64×32）皮肤取各个面，外层（帽子、外套、袖子、裤子）叠在基础层上
    init?(skin: CGImage, slim: Bool) {
        let w = skin.width, h = skin.height
        guard w == 64, h == 64 || h == 32,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              true else { return nil }
        ctx.draw(skin, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let raw = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let legacy = h == 32
        func pixel(_ x: Int, _ y: Int) -> (UInt32, UInt8) {
            guard x >= 0, y >= 0, x < w, y < h else { return (0, 0) }
            let i = (y * w + x) * 4
            return ((UInt32(raw[i]) << 16) | (UInt32(raw[i + 1]) << 8) | UInt32(raw[i + 2]), raw[i + 3])
        }
        /// 取一块区域；step 为 2 时隔列取样（把侧面压窄）；k 为明暗
        func face(_ x0: Int, _ y0: Int, _ fw: Int, _ fh: Int, overlay: (Int, Int)? = nil, flip: Bool = false,
                  step: Int = 1, k: Double = 1) -> [[UInt32]] {
            (0..<fh).map { y in
                stride(from: 0, to: fw, by: step).map { xx in
                    let x = flip ? fw - 1 - xx : xx
                    if !legacy, let (ox, oy) = overlay { let (c, a) = pixel(ox + x, oy + y); if a > 127 { return 0xFF00_0000 | shade(c, k) } }
                    let (c, a) = pixel(x0 + x, y0 + y)
                    return a > 0 || legacy ? 0xFF00_0000 | shade(c, k) : 0
                }
            }
        }
        func sprite(_ cols: [[[UInt32]]]) -> Sprite {
            // 把几块同高的区域左右拼起来
            let height = cols.first?.count ?? 0
            let rows = (0..<height).map { y in cols.flatMap { $0[y] } }
            return Sprite(width: rows.first?.count ?? 0, height: height) { x, y in let v = rows[y][x]; return v == 0 ? nil : v & 0xFFFFFF }
        }
        let side = 0.78
        let front = face(8, 8, 8, 8, overlay: (40, 8))
        headFront = sprite([front])
        // 眨眼：眼睛所在的第 4 行换成上一行的颜色
        var closed = front
        closed[4] = front[3]
        headFrontBlink = sprite([closed])
        headSide = sprite([face(16, 8, 8, 8, overlay: (48, 8), step: 2, k: side)])
        bodyFront = sprite([face(20, 20, 8, 12, overlay: (20, 36))])
        bodySide = sprite([face(28, 20, 4, 12, overlay: (28, 36), step: 2, k: side)])
        let armW = slim ? 3 : 4
        if legacy {
            nearArm = sprite([face(44, 20, 4, 12, flip: true), face(40, 20, 4, 12, flip: true, step: 2, k: side)])
            farArm = sprite([face(44, 20, 4, 12, step: 1, k: 0.82).map { Array($0.suffix(3)) }])
            legs = sprite([face(4, 20, 4, 12), face(4, 20, 4, 12, flip: true), face(0, 20, 4, 12, flip: true, step: 2, k: side)])
        } else {
            nearArm = sprite([face(36, 52, armW, 12, overlay: (52, 52)), face(slim ? 39 : 40, 52, 4, 12, overlay: (slim ? 55 : 56, 52), step: 2, k: side)])
            farArm = sprite([face(44, 20, armW, 12, overlay: (44, 36), k: 0.82).map { Array($0.suffix(3)) }])
            legs = sprite([face(4, 20, 4, 12, overlay: (4, 36)), face(20, 52, 4, 12, overlay: (4, 52)), face(24, 52, 4, 12, overlay: (8, 52), step: 2, k: side)])
        }
    }

    /// 默认外观：在代码里画的史蒂夫风格皮肤（青色上衣、蓝裤子、深棕头发），或 Alex 风格（橙发、绿上衣、细手臂）
    static func defaultSkin(alex: Bool = false) -> CGImage {
        var px = [UInt32](repeating: 0, count: 64 * 64)
        func put(_ x: Int, _ y: Int, _ rows: [String], _ pal: [Character: UInt32]) {
            for (dy, row) in rows.enumerated() { for (dx, ch) in row.enumerated() { if let c = pal[ch] { px[(y + dy) * 64 + x + dx] = c } } }
        }
        let pal: [Character: UInt32] = alex
            ? ["H": 0xE3792B, "h": 0xC7601D, "S": 0xF2CBA4, "s": 0xE1B48E, "W": 0xF4F4F4, "B": 0x3E8A3A,
               "n": 0xE1B48E, "M": 0xC98E72, "T": 0x6CA644, "t": 0x578C33, "P": 0x6A4A30, "p": 0x57391F,
               "G": 0x45372A, "g": 0x382C21]
            : ["H": 0x3B2717, "h": 0x2A1B10, "S": 0xB78A6B, "s": 0x9C7257, "W": 0xF4F4F4, "B": 0x4C5DBB,
               "n": 0x8E6249, "M": 0x6B4733, "T": 0x22A3A3, "t": 0x198282, "P": 0x3A3FA0, "p": 0x2C3080,
               "G": 0x5B5B5B, "g": 0x464646]
        if alex {
            put(8, 8, ["HHHHHHHH", "HHHHHHHH", "HSSSSHHH", "SSSSSShH", "SWBSSBWH", "SSSSSSSH", "SSSMMSSS", "sSSSSSSs"], pal)
            put(16, 8, ["HHHHHHHH", "HHHHHHHH", "SSHHHHHH", "SSSHHHHH", "SSSHHHHh", "SSSSHHHh", "SSSSHHHh", "sSSSHHHh"], pal)
        } else {
            put(8, 8, ["HHHHHHHH", "HHHHHHHH", "HSSSSSSH", "SSSSSSSS", "SWBSSBWS", "SSSnnSSS", "SSMMMMSS", "sSSSSSSs"], pal)
            put(16, 8, ["HHHHHHHH", "HHHHHHHH", "SSHHHHHH", "SSSHHHHh", "SSSSHHHh", "SSSSSSHh", "SSSSSSSh", "sSSSSSSs"], pal)
        }
        let shirt = ["TTTSSTTT"] + Array(repeating: "TTTTTTTT", count: 10) + ["tttttttt"]
        put(20, 20, shirt, pal)
        put(28, 20, Array(repeating: "TTTt", count: 11) + ["tttt"], pal)
        let w = alex ? 3 : 4
        let arm = Array(repeating: String(repeating: "T", count: w), count: 4) + Array(repeating: String(repeating: "S", count: w), count: 7) + [String(repeating: "s", count: w)]
        let armSide = Array(repeating: "TTTt", count: 4) + Array(repeating: "SSSs", count: 7) + ["ssss"]
        put(44, 20, arm, pal); put(40, 20, armSide, pal)
        put(36, 52, arm, pal); put(alex ? 39 : 40, 52, armSide, pal)
        let leg = Array(repeating: "PPPP", count: 9) + ["pppp", "GGGG", "gggg"]
        let legSide = Array(repeating: "PPPp", count: 9) + ["pppp", "GGGg", "gggg"]
        put(4, 20, leg, pal); put(20, 52, leg, pal); put(24, 52, legSide, pal); put(0, 20, legSide, pal)
        let bytes = px.flatMap { c -> [UInt8] in c == 0 ? [0, 0, 0, 0] : [UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF), 255] }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// 0…1 之间的缓入缓出
@inline(__always) func ease(_ p: Double) -> Double { let q = max(0, min(1, p)); return q * q * (3 - 2 * q) }

/// 在 [a, b] 时段内从 0 走到 1，之后保持 1
@inline(__always) func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { ease((t - a) / (b - a)) }

extension DotBuffer {
    /// 绕 pivot 旋转后画精灵（最近邻，逆向映射避免空洞）。angle 为向前（画面左方）转动的角度，0 = 不转
    mutating func blitRotated(_ s: Sprite, pivotX: Double, pivotY: Double, origin: (Double, Double), angle: Double) {
        let c = cos(angle), sn = sin(angle)
        let r = Int(Double(max(s.width, s.height)) * 1.5) + 2
        for ty in -r...r {
            for tx in -r...r {
                // 屏幕坐标里的偏移 → 精灵坐标里的偏移
                let ox = Double(tx) * c + Double(ty) * sn, oy = -Double(tx) * sn + Double(ty) * c
                let sx = Int((ox + origin.0).rounded(.down)), sy = Int((oy + origin.1).rounded(.down))
                guard sx >= 0, sy >= 0, sx < s.width, sy < s.height else { continue }
                let v = s.px[sy * s.width + sx]
                if v != 0 { self[Int(pivotX) + tx, Int(pivotY) + ty] = v }
            }
        }
    }
}

// MARK: - 护甲

/// 护甲材质：从暗到亮五个颜色
struct ArmorMaterial {
    let tones: [UInt32]   // 描边、暗、中、主色、高光
    static let diamond = ArmorMaterial(tones: [0x0F5E55, 0x1A9B8A, 0x2BC7AC, 0x4AEDD9, 0xA1FBE8])
    static let netherite = ArmorMaterial(tones: [0x1E1B1E, 0x2B282B, 0x3E3A3E, 0x4D494D, 0x7A6F7A])
    static let turtle = ArmorMaterial(tones: [0x1F4F22, 0x2D7A30, 0x3A9C3D, 0x47BF4A, 0x8FE08A])
    static let gold = ArmorMaterial(tones: [0x7A5A12, 0xB08A1E, 0xD9B02E, 0xF5D74A, 0xFFF39A])
    static let copper = ArmorMaterial(tones: [0x6E3420, 0x9C4E36, 0xC0644A, 0xE0805A, 0xF5A47E])
}

/// 穿在身上的护甲（每件可以单独给）
struct Armor {
    var helmet: ArmorMaterial?
    var chest: ArmorMaterial?
    var legs: ArmorMaterial?
    var boots: ArmorMaterial?
    static func full(_ m: ArmorMaterial) -> Armor { Armor(helmet: m, chest: m, legs: m, boots: m) }
}

extension Sprite {
    /// 在精灵上逐点改色：f 返回 nil 表示保持原样
    func painted(_ f: (Int, Int) -> UInt32?) -> Sprite {
        Sprite(width: width, height: height) { x, y in
            if let c = f(x, y) { return c }
            let v = px[y * width + x]
            return v == 0 ? nil : v & 0xFFFFFF
        }
    }
}

extension PlayerLook {
    /// 穿上护甲：头盔包住头顶和两侧，胸甲盖住身体和肩膀，护腿与靴子盖住腿
    func wearing(_ armor: Armor) -> PlayerLook {
        var l = self
        func tone(_ m: ArmorMaterial, _ x: Int, _ y: Int, edge: Bool, light: Bool = false) -> UInt32 {
            if edge { return m.tones[1] }
            if light && noise(x, y, 81) < 0.45 { return m.tones[4] }
            return noise(x, y, 82) < 0.3 ? m.tones[2] : m.tones[3]
        }
        if let m = armor.helmet {
            let helm: (Int, Int, Int) -> UInt32? = { x, y, w in
                if y <= 1 { return tone(m, x, y, edge: false, light: y == 0) }
                if y == 2 { return tone(m, x, y, edge: x == 0 || x == w - 1) }
                if (3...5).contains(y) && (x == 0 || x == w - 1) { return tone(m, x, y, edge: true) }
                return nil
            }
            l.headFront = headFront.painted { helm($0, $1, 8) }
            l.headFrontBlink = headFrontBlink.painted { helm($0, $1, 8) }
            l.headSide = headSide.painted { x, y in y <= 2 || (y <= 6 && x == headSide.width - 1) ? shade(tone(m, x, y, edge: y == 2), 0.85) : nil }
        }
        if let m = armor.chest {
            l.bodyFront = bodyFront.painted { x, y in y <= 9 ? tone(m, x, y, edge: x == 0 || x == 7 || y == 9, light: x < 3 && y < 4) : nil }
            l.bodySide = bodySide.painted { x, y in y <= 9 ? shade(tone(m, x, y, edge: y == 9), 0.82) : nil }
            l.nearArm = nearArm.painted { x, y in y <= 4 ? tone(m, x, y, edge: y == 4, light: y < 2) : nil }
            l.farArm = farArm.painted { x, y in y <= 4 ? shade(tone(m, x, y, edge: y == 4), 0.85) : nil }
        }
        if armor.legs != nil || armor.boots != nil {
            l.legs = legs.painted { x, y in
                if let m = armor.boots, y >= 9 { return x >= 8 ? shade(tone(m, x, y, edge: false), 0.8) : tone(m, x, y, edge: y == 9) }
                if let m = armor.legs, y <= 7 { return x >= 8 ? shade(tone(m, x, y, edge: false), 0.8) : tone(m, x, y, edge: y == 0 || (y > 2 && (x == 3 || x == 4))) }
                return nil
            }
        }
        return l
    }
}

// MARK: - 物品

/// 拿在手里的东西。剑、锤这类会跟着手臂转动（精灵画成竖直向上，握把在底部）；方块、地图这类不转
struct HeldItem {
    let sprite: Sprite
    var swings = true

    static let diamondSword = HeldItem(sprite: Sprite([
        "..o..", ".oLo.", ".oLo.", ".oMo.", ".oLo.", ".oMo.", ".oLo.", ".oMo.", ".oLo.",
        "tTTTt", "..h..", "..h..", ".tTt.",
    ], ["o": 0x0F5E55, "L": 0xA1FBE8, "M": 0x4AEDD9, "t": 0x1A9B8A, "T": 0x2BC7AC, "h": 0x6B4A2C]))
    static let netheriteSword = HeldItem(sprite: Sprite([
        "..o..", ".oLo.", ".oLo.", ".oMo.", ".oLo.", ".oMo.", ".oLo.", ".oMo.", ".oLo.",
        "tTTTt", "..h..", "..h..", ".tTt.",
    ], ["o": 0x1E1B1E, "L": 0x8A7E8A, "M": 0x4D494D, "t": 0x2B282B, "T": 0x5A4E44, "h": 0x3A2A22]))
    static let mace = HeldItem(sprite: Sprite([
        ".k.k.k.", "kHhHhHk", "kHHhHHk", "dHhHHhd", "kHHHHHk", ".kdHdk.", "..kck..",
        "...b...", "...B...", "...b...", "...B...", "...b...", "...B...", "..kbk..",
    ], ["k": 0x24262A, "d": 0x3A3D42, "H": 0x5A5E66, "h": 0x9EA3AD, "c": 0x7A6A4A, "b": 0x8A93D8, "B": 0x5A63A8]))
    static let trident = HeldItem(sprite: Sprite([
        "l.l.l", "L.L.L", "M.M.M", "MMMMM", ".MLM.", "..M..",
    ] + Array(repeating: "..S..", count: 9).enumerated().flatMap { i, r in i % 3 == 0 ? ["..s.."] + [r] : [r] }
      + ["..G..", "..g..", "..G..", "..S..", "..s.."],
    ["l": 0xD9F2EC, "L": 0x9FE3D6, "M": 0x6FB8A8, "S": 0x4E8B7E, "s": 0x3E7066, "G": 0x5FA394, "g": 0x2E5A52]))
    static let brush = HeldItem(sprite: Sprite([
        ".FFF.", "FFfFF", "FfFfF", ".FFF.", ".cCc.", "..w..", "..W..", "..w..", "..W..",
    ], ["F": 0xE6D3A8, "f": 0xC9B184, "c": 0xB0602E, "C": 0xD9844A, "w": 0x8B5A2B, "W": 0xA36C38]))
    /// 望远镜（1.17）：铜管，前端是紫水晶镜片。看的时候举到眼前
    static let spyglass = HeldItem(sprite: Sprite([
        "aAa", "oCo", "oCo", "ocO", "oCo", "dDd", "dDd",
    ], ["a": 0xB9A6E8, "A": 0x8E6FD6, "o": 0x6E3A1E, "C": 0xE08A3A, "c": 0xF5B46A, "O": 0xB05A2E, "d": 0x4A2414, "D": 0x6A3420]), swings: false)
    /// 弩（1.14，对照原版）：竖着画（瞄准时转成水平）。长长的木托，托上装着一支箭，
    /// 前端是一小截横着的弓（从侧面看弓臂朝向画面里外，只露出一小段），中间有铁扳机
    static let crossbow = HeldItem(sprite: Sprite([
        "..s..", "..b..", "wWWWw", ".SbS.", "..W..", "..b..", "..W..", "..i..", "..W..", "..W..", "..w..", "..w..",
    ], ["W": 0x8A5A2E, "w": 0x5E3A1E, "b": 0xC8A878, "s": 0xC4C8CE, "S": 0x9A9EA4, "i": 0x6E7276]))
    /// 蜂蜜瓶（1.15）
    static let honeyBottle = HeldItem(sprite: Sprite([
        "..cc..", "..gg..", ".gHHg.", "gHhHHg", "gHHHHg", "gHHhHg", ".gggg.",
    ], ["c": 0xB05A3A, "g": 0xC8E4F0, "H": 0xF5A42E, "h": 0xFFD06A]), swings: false)
    /// 追溯指针（1.19）：灰色的圆盘，中间是青色的指针
    static let recoveryCompass = HeldItem(sprite: Sprite([
        "..oooo..", ".oGggGo.", "oGkCkkGo", "oGkCCkGo", "ogkkCkgo", "oGkkkkGo", ".oCCCCo.", "..oooo..",
    ], ["o": 0x1E2226, "G": 0x8A9096, "g": 0x5A6066, "k": 0x0E1A1E, "C": 0x2AD6E8]), swings: false)
    static let explorerMap = HeldItem(sprite: Sprite([
        "oooooooo", "oPPPPPPo", "oPgGPPPo", "oPPGgPbo", "oPPPPbPo", "oPrPPPPo", "oPPPPPPo", "oooooooo",
    ], ["o": 0x8A6A3A, "P": 0xF2E6C2, "g": 0x5DA03F, "G": 0x3E7A2C, "b": 0x4A78EE, "r": 0xD8341F]), swings: false)
}

// MARK: - 姿势与玩家

/// 一帧里玩家的姿势；场景可以自己算（比如 PVP），也可以用 Player.idle 的默认待机动作
struct PlayerPose {
    var armAngle = 0.06        // 后手（右手，拿东西）向前抬起的角度，0 = 下垂
    var itemTilt = 0.0         // 物品在手里额外转的角度
    var itemUp = 0.0           // 不转的物品举到眼前的程度
    var lift = 0               // 跳起的高度
    var dx = 0                 // 左右挪动
    var headDip = 0
    var lookBack = false
    var helmetLift = 0.0       // 摘下的头盔离开头顶多高
    var hurt = 0.0             // 受击变红
    var sitting = false
    var sneaking = false       // 潜行：腿保持直立，上身往前倾
    var blocking = false       // 举盾：副手的盾挡在身前
    var flying = false         // 鞘翅滑翔：身体放平、头朝前、腿在后，鞘翅在背上展开；这时 x、feet 是身体中心
    var walk: Double?          // 走路：步伐的相位（弧度），两条腿和两只手前后交替摆动；nil 为站着
}

/// 场景给玩家的道具
struct PlayerProps {
    var held: HeldItem?
    var armor = Armor()
    /// 摘下再戴回去的那顶头盔（只用来做摘头盔的动作；平时戴着的头盔在 armor 里）
    var removableHelmet: ArmorMaterial?
    /// 肩膀上的东西（比如 1.12 的鹦鹉）
    var shoulder: Sprite?
    /// 副手的东西（比如 1.9 的盾）
    var offhand: Sprite?
    /// 背上的鞘翅（1.9）
    var elytra = false
}

enum Player {
    /// 局部画布里头部正面左边缘的位置（Player.draw 的 x 对应这里）
    static let canvasX = 36

    /// 鞘翅滑翔（与原版一致）：身体放平，头在最前面、保持竖直往前看，腿拖在后面；
    /// 鞘翅从肩膀往后掠开——远处那片在身体上方，近处那片在身体下方，都往后收成尖，前缘颜色更深。x、y 是身体中心
    static func drawFlying(_ b: inout DotBuffer, look: PlayerLook, x: Int, y: Int, t: Double, facingRight: Bool) {
        var s = DotBuffer(cols: 64, rows: 44)
        let ox = 26, oy = 22   // 身体中心
        let flex = sin(t * 2.4) * 1.2
        func rotCCW(_ sp: Sprite) -> Sprite { Sprite(width: sp.height, height: sp.width) { x, y in let v = sp.px[x * sp.width + (sp.width - 1 - y)]; return v == 0 ? nil : v & 0xFFFFFF } }
        /// 一片翅膀（和原版张开的鞘翅一样像蜻蜓翅膀）：根部在肩膀，很细，往后越来越宽，末端圆钝；
        /// dir 为翅膀相对身体往上（-1）或往下（+1）展开，外缘颜色更深，带几道羽纹
        func wing(sx: Int, sy: Int, length: Int, spread: Double, dir: Double, tone: Double) {
            for k in 0..<length {
                let f = Double(k) / Double(length - 1)
                let center = Double(sy) + dir * spread * f
                var half = 0.6 + 4.4 * min(1, f / 0.7)
                if f > 0.82 { half *= 1 - (f - 0.82) / 0.18 * 0.55 }
                let lo = Int((center - half).rounded()), hi = Int((center + half).rounded())
                for dy in lo...max(lo, hi) {
                    let outer = dir < 0 ? dy == lo : dy == hi
                    var c: UInt32 = outer ? 0x4A5868 : (k % 4 == 0 && f > 0.15 ? 0x7A8A9E : (Double(dy) < center ? 0xB4C0CC : 0x8A9AAE))
                    if f < 0.12 { c = 0x5E6E80 }
                    s[sx + k, dy] = 0xFF00_0000 | shade(c, tone)
                }
            }
        }
        // 远处的翅膀：在身体上方往后上展开
        wing(sx: ox - 3, sy: oy - 4, length: 26, spread: 8 + flex, dir: -1, tone: 0.8)
        // 腿：拖在身体后面，两条腿一上一下地踢
        func leg(_ cols: ClosedRange<Int>, kick: Double, tone: Double) {
            let sp = Sprite(width: 4, height: 12) { x, y in let v = look.legs.px[y * look.legs.width + cols.lowerBound + x]; return v == 0 ? nil : shade(v & 0xFFFFFF, tone) }
            s.blitRotated(sp, pivotX: Double(ox + 5), pivotY: Double(oy), origin: (2, 0), angle: -.pi / 2 + kick)
        }
        let kick = sin(t * 5.5) * 0.22
        leg(4...7, kick: -kick, tone: 0.8)
        leg(0...3, kick: kick, tone: 1)
        // 身体：放平
        let body = rotCCW(look.bodyFront)
        s.blit(body, x: ox - 6, bottom: oy + 3, w: body.width, h: 7)
        // 近处的手臂贴在身体下侧
        let arm = rotCCW(look.nearArm)
        s.blit(arm, x: ox - 5, bottom: oy + 5, w: arm.width, h: 3)
        // 头：保持竖直，往前看
        s.blit(look.headFront, x: ox - 15, bottom: oy + 2)
        s.blit(look.headSide, x: ox - 7, bottom: oy + 2)
        // 近处的翅膀：在身体下方往后下展开
        wing(sx: ox - 2, sy: oy + 3, length: 24, spread: 5 - flex, dir: 1, tone: 1.0)
        for sy in 0..<s.rows { for sx in 0..<s.cols {
            let v = s.px[sy * s.cols + sx]
            guard v != 0 else { continue }
            let tx = facingRight ? 2 * ox - sx : sx
            b[x + tx - ox, y + sy - oy] = v
        } }
    }

    /// 默认待机：一直在呼吸；手里有东西时不时抬起来看一眼，有可摘的头盔时摘下来再戴回去，什么都没有就偶尔回头看看
    static func idle(_ t: Double, props: PlayerProps, phase: Double = 0) -> PlayerPose {
        var pose = PlayerPose()
        let p = (t + phase).truncatingRemainder(dividingBy: 15)
        pose.armAngle = 0.06 + sin(t * 1.1) * 0.07
        if let held = props.held, (2.0...5.6).contains(p) {
            let k = ramp(p, 2.0, 2.7) * (1 - ramp(p, 4.9, 5.6))
            pose.armAngle = (held.swings ? 1.1 : 1.45) * k
            pose.itemUp = held.swings ? 0 : k
            pose.itemTilt = held.swings ? -0.5 * k : 0
            pose.headDip = k > 0.6 ? 1 : 0
        }
        if props.removableHelmet != nil, (8.0...11.6).contains(p) {
            pose.armAngle = 2.75 * ramp(p, 8.0, 8.5) * (1 - ramp(p, 11.1, 11.6))
            pose.helmetLift = 9 * ramp(p, 8.5, 9.1) * (1 - ramp(p, 10.4, 11.0))
        } else if (props.held == nil && (6.5...7.7).contains(p)) || (props.removableHelmet == nil && (10.0...10.9).contains(p)) {
            pose.lookBack = true
        }
        return pose
    }

    /// 画玩家：脚底在 feet 行（坐着时是屁股所在的行），x 为面朝左时头部正面的左边缘。
    /// facingRight 时整个人左右翻转（x 仍是同一个人站的位置），用于画在左边、面向右边的角色
    static func draw(_ b: inout DotBuffer, look: PlayerLook, props: PlayerProps = PlayerProps(), pose: PlayerPose,
                     x: Int, feet: Int, t: Double, facingRight: Bool = false) {
        let look = look.wearing(props.armor)
        // 先画到一张局部画布上：左边留够地方，长矛、钓竿这类往前伸的东西不会被截掉
        var s = DotBuffer(cols: 84, rows: 64)
        let ax = canvasX, f = 60 - pose.lift
        let breath = sin(t * 2 * .pi / 3.4) > 0.35 ? 1 : 0
        let legsH = pose.sitting ? 10 : 12
        // 潜行（和原版一样）：腿保持直立，上身往前倾，肩膀和头往前、往下移，头保持竖直，手臂跟着肩膀往前
        let tilt = pose.sneaking ? 0.4 : 0.0
        let bodyBottom = f - legsH - breath
        let reach = Int((11 * tilt).rounded()), drop = pose.sneaking ? 2 : 0
        let shoulder = bodyBottom - 11 + drop
        // 鞘翅：从肩膀后面垂到膝盖，往背后展开，微微扇动
        if props.elytra && !pose.flying {
            let spread = 2 + Int((sin(t * 1.8) * 1.2).rounded())
            for dy in 0..<20 {
                let w = 3 + dy / 3 + spread * dy / 20
                for dx in 0..<w {
                    let c: UInt32 = dx == w - 1 ? 0x4A5868 : (dy % 4 == 0 ? 0xB4C0CC : (dx % 3 == 0 ? 0x7A8898 : 0x8A98A8))
                    s[ax + 9 + dx - reach / 2, shoulder - 1 + dy] = 0xFF00_0000 | c
                }
            }
        }
        // 后手：绕肩膀旋转，拿东西也用这只手
        let pivotX = Double(ax - reach) - 1.5, pivotY = Double(shoulder)
        // 走路时手脚的摆幅：近处的腿往前时远处的腿往后，手和同侧的腿相反
        let swing = pose.walk.map { sin($0) * 0.42 } ?? 0
        let walking = pose.walk != nil && !pose.sitting
        if look.crossedArms == nil {
            s.blitRotated(look.farArm, pivotX: pivotX, pivotY: pivotY, origin: (1.5, 0), angle: pose.armAngle + (walking ? swing * 0.7 : 0))
        }
        if pose.sitting {
            // 坐着：大腿从髋部往前（画面左方）伸出去，小腿从膝盖垂下来，和身体连在一起
            let hipY = bodyBottom + 1
            for leg in 0..<2 {
                let c0 = leg == 0 ? 4 : 0, tone = leg == 0 ? 0.82 : 1.0
                for r in 0..<4 { for k in 0..<8 {
                    let v = look.legs.px[min(5, k * 6 / 8) * look.legs.width + c0 + r]
                    if v != 0 { s[ax + 3 - k - leg, hipY + r] = 0xFF00_0000 | shade(v & 0xFFFFFF, tone) }
                } }
                for r in 0..<6 { for c in 0..<4 {
                    let v = look.legs.px[(6 + r) * look.legs.width + c0 + c]
                    if v != 0 { s[ax - 5 + c - leg, hipY + 4 + r] = 0xFF00_0000 | shade(v & 0xFFFFFF, tone) }
                } }
            }
        } else if walking {
            // 走路：两条腿各自绕髋部转动，远处那条（暗一点）先画
            let legs = look.legs
            func leg(_ cols: [Int]) -> Sprite {
                Sprite(width: cols.count, height: legs.height) { x, y in let v = legs.px[y * legs.width + cols[x]]; return v == 0 ? nil : v & 0xFFFFFF }
            }
            let hip = Double(f - legs.height + 1)
            // 右边那条腿连着侧面（第 8、9 列），左边那条只有正面
            let far = leg([4, 5, 6, 7] + (legs.width > 8 ? Array(8..<legs.width) : [])), near = leg([0, 1, 2, 3])
            s.blitRotated(far, pivotX: Double(ax + 6), pivotY: hip, origin: (2, 0), angle: -swing)
            s.blitRotated(near, pivotX: Double(ax + 2), pivotY: hip, origin: (2, 0), angle: swing)
        } else {
            s.blit(look.legs, x: ax, bottom: f)
        }
        // 上身：前倾时逐行往前错开，并略微压低
        func torso(_ sp: Sprite, x: Int) {
            for r in 0..<sp.height {
                let up = sp.height - 1 - r
                let off = Int((Double(up) * tilt).rounded())
                let y = bodyBottom - up + (pose.sneaking ? Int((Double(up) * 0.18).rounded()) : 0)
                for c in 0..<sp.width { let v = sp.px[r * sp.width + c]; if v != 0 { s[x + c - off, y] = v } }
            }
        }
        torso(look.bodyFront, x: ax)
        torso(look.bodySide, x: ax + 8)
        if let arms = look.crossedArms {
            s.blit(arms, x: ax - reach - 1, bottom: shoulder + 7)
        } else if walking {
            s.blitRotated(look.nearArm, pivotX: Double(ax + 10) + Double(look.nearArm.width) / 2, pivotY: Double(shoulder),
                          origin: (Double(look.nearArm.width) / 2, 0), angle: -swing * 0.7)
        } else {
            torso(look.nearArm, x: ax + 10)
        }
        // 头：正面 + 侧面；回头时左右翻过来
        let blink = (t + 1.3).truncatingRemainder(dividingBy: 4.3) < 0.16
        let headBottom = bodyBottom - 12 + pose.headDip + drop
        let front = blink ? look.headFrontBlink : look.headFront
        let hx = ax - reach
        if pose.lookBack {
            s.blit(look.headSide, x: hx, bottom: headBottom, flip: true)
            s.blit(front, x: hx + 4, bottom: headBottom)
        } else {
            s.blit(front, x: hx, bottom: headBottom)
            s.blit(look.headSide, x: hx + 8, bottom: headBottom)
        }
        if let nose = look.nose, !pose.lookBack {
            // 接在脸正中间的鼻子下面，垂到下巴以下
            s.blit(nose, x: hx + 3, bottom: headBottom + nose.height)
        }
        if let m = props.removableHelmet {
            // 可以摘下的头盔：一个包住头顶的壳，跟着手上下
            let lift = Int(pose.helmetLift.rounded())
            let shell = Sprite(width: 14, height: 6) { x, y in
                if y == 5 && (x == 0 || x == 13) { return m.tones[1] }
                if y == 5 { return nil }
                if y == 0 && (x == 0 || x == 13) { return nil }
                return noise(x, y, 91) < 0.25 ? m.tones[4] : (y < 2 ? m.tones[3] : m.tones[2])
            }
            s.blit(shell, x: ax - 1, bottom: headBottom - 3 - lift)
        }
        if let off = props.offhand {
            if pose.blocking {
                s.blit(off, x: ax - reach - off.width + 3, bottom: shoulder + off.height - 2)
            } else {
                s.blit(off, x: ax + 12 - reach, bottom: bodyBottom + 4)
            }
        }
        if let sh = props.shoulder {
            s.blit(sh, x: ax + 7, bottom: shoulder - 1 + (sin(t * 2.3) > 0.7 ? -1 : 0))
        }
        // 手里的东西：剑与锤跟着手臂转，方块和地图举在眼前
        if let held = props.held {
            let hand = (pivotX - sin(pose.armAngle) * 10.5, pivotY + cos(pose.armAngle) * 10.5)
            if held.swings {
                s.blitRotated(held.sprite, pivotX: hand.0, pivotY: hand.1, origin: (Double(held.sprite.width) / 2, Double(held.sprite.height) - 2),
                              angle: pose.armAngle - .pi / 2 + 0.45 + pose.itemTilt)
            } else {
                s.blit(held.sprite, x: Int(hand.0) - held.sprite.width / 2 - Int(pose.itemUp * 3),
                       bottom: Int(hand.1) + held.sprite.height / 2 - Int(pose.itemUp * 3))
            }
        }
        // 受击：整个人泛红
        if pose.hurt > 0.01 {
            for i in s.px.indices where s.px[i] != 0 {
                let c = s.px[i] & 0xFFFFFF
                let r = Double((c >> 16) & 0xFF), g = Double((c >> 8) & 0xFF), bl = Double(c & 0xFF)
                let k = pose.hurt * 0.6
                s.px[i] = 0xFF00_0000 | (UInt32(r + (255 - r) * k) << 16) | (UInt32(g * (1 - k)) << 8) | UInt32(bl * (1 - k))
            }
        }
        if pose.flying {
            drawFlying(&b, look: look, x: x + pose.dx, y: feet, t: t, facingRight: facingRight)
            return
        }
        // 贴到场景里；朝右时以身体中线翻转
        let cx = ax + 5
        for sy in 0..<s.rows {
            for sx in 0..<s.cols {
                let v = s.px[sy * s.cols + sx]
                guard v != 0 else { continue }
                let tx = facingRight ? 2 * cx - sx : sx
                b[x + pose.dx + tx - ax, feet - 60 + sy] = v
            }
        }
    }
}

// MARK: - 26.2 Chaos Cubed：硫磺洞穴与硫磺立方

struct SulfurCaves: DotScene {
    let id = "26.2"
    let background: UInt32 = 0x0D0C09

    private static let wall: [UInt32] = [0x3B3523, 0x433C27, 0x4C4429, 0x35301F, 0x3F3824]
    private static let sulfur: [UInt32] = [0xB89F3E, 0xCFB54B, 0x9E8834, 0xC2A945]
    private static let cinnabar: [UInt32] = [0xA9443C, 0xB8504A, 0x94362F, 0xA03D36]
    private static let cinnabarDeep: [UInt32] = [0x7E2C26, 0x8A3029, 0x6E2621]

    /// 硫磺立方：半透明的米黄色方块，脸在下半部。look 为眼睛的水平偏移（看向玩家为 +1），blink 时闭眼
    static func cube(size n: Int, look: Int, blink: Bool) -> Sprite {
        Sprite(width: n, height: n) { x, y in
            if x == 0 || x == n - 1 || y == 0 || y == n - 1 { return 0xB4A462 }
            let big = n >= 12
            let eyeW = big ? 2 : 1
            let eyeY = big ? (n / 2)...(n / 2 + 2) : (n / 2)...(n / 2 + 1)
            let eyes = big ? [3, n - 5] : [2, n - 3]
            if !blink, eyeY.contains(y), eyes.contains(where: { (($0 + look)..<($0 + look + eyeW)).contains(x) }) { return 0x2A2216 }
            if blink, y == eyeY.upperBound, eyes.contains(where: { (($0 + look)..<($0 + look + eyeW)).contains(x) }) { return 0x6A5A34 }
            if (n / 2 - 1...n / 2).contains(x - look) && y == (big ? n / 2 + 4 : n / 2 + 2) { return 0x4E3D24 }
            if y < n / 3 && x < n / 3 + 1 { return 0xFFF6C8 }
            return noise(x, y, 7) < 0.18 ? 0xE2D18C : 0xF0E2A0
        }
    }

    /// 玩家手里的硫磺块（小方块，带一点立体感）
    static let sulfurBlock = Sprite([
        ".yyyyy.",
        "yYYYYYy",
        "yYyYYYy",
        "yYYYyYy",
        "dYYYYYd",
        "ddyyydd",
        ".ddddd.",
    ], ["y": 0xCFB54B, "Y": 0xE3CB5E, "d": 0x9E8834])

    private func layout(_ b: DotBuffer) -> (ground: Int, poolX: ClosedRange<Int>, poolTop: Int, poolBottom: Int) {
        let ground = Int(Double(b.rows) * 0.6)
        let pool = Int(Double(b.cols) * 0.38)...Int(Double(b.cols) * 0.6)
        return (ground, pool, ground + 3, ground + 15)
    }

    func paintStatic(_ b: inout DotBuffer) {
        let (ground, pool, _, poolBottom) = layout(b)
        let poolCX = Double(pool.lowerBound + pool.upperBound) / 2
        // 洞壁：从洞顶的暗褐到下方的土黄，按有序抖动分档；硫磺池的光在洞壁上铺开
        let wallRamp: [UInt32] = [0x1E180C, 0x2E2514, 0x41351C, 0x574624, 0x6B5A2C]
        let glowRamp: [UInt32] = [0x574624, 0x6E7A33, 0x8DA344, 0xB3C25A]
        for y in 0..<ground {
            for x in 0..<b.cols {
                let depth = Double(y) / Double(ground)
                var c = ditherRamp(wallRamp, 0.15 + depth * 0.8, x, y)
                let dx = (Double(x) - poolCX) / (Double(pool.count) * 1.6), dy = Double(ground - y) / (Double(ground) * 0.75)
                let g = max(0, 1 - (dx * dx + dy * dy).squareRoot())
                if g > 0.08 { c = ditherRamp(glowRamp, g, x, y) }
                // 墙面的方块纹理：稀疏的亮点与暗点
                let n = noise(x, y, 1)
                if n > 0.965 { c = shade(c, 1.25) } else if n < 0.03 { c = shade(c, 0.7) }
                b.set(x, y, c)
            }
        }
        // 远处的岩柱：比洞壁更暗，增加层次
        for (k, cx) in [0.05, 0.47, 0.93].enumerated() {
            let px = Int(Double(b.cols) * cx)
            for y in 0..<ground {
                let w = 7 + Int(4 * sin(Double(y) * 0.07 + Double(k) * 2))
                for dx in 0..<w where noise(px + dx, y, 20 + k) > 0.08 {
                    b.set(px + dx, y, ditherRamp([0x16120A, 0x231C0F, 0x2E2514], Double(y) / Double(ground), px + dx, y))
                }
            }
        }
        // 从洞顶垂下的硫磺钟乳：尖端更亮
        var x = 9
        while x < b.cols {
            let len = 8 + Int(noise(x, 0, 9) * Double(ground) * 0.36)
            let w = 3 + Int(noise(x, 1, 9) * 5)
            for dy in 0..<len {
                let ww = max(1, w - dy * w / len)
                for dx in 0..<ww {
                    b.set(x + dx + (w - ww) / 2, dy, ditherRamp([0x6E5A22, 0x9E8834, 0xCFB54B, 0xEFD769], Double(dy) / Double(len), x + dx, dy))
                }
            }
            x += 11 + Int(noise(x, 2, 9) * 20)
        }
        // 墙上的硫磺晶簇
        for i in 0..<9 {
            let cx = Int(noise(i, 0, 51) * Double(b.cols)), cy = Int(Double(ground) * (0.25 + noise(i, 1, 51) * 0.6))
            for (dx, dy, c) in [(0, -2, 0xFFF08A), (-1, -1, 0xE8D25A), (0, -1, 0xFFF08A), (1, -1, 0xE8D25A), (-1, 0, 0xCFB54B),
                                (0, 0, 0xE8D25A), (1, 0, 0xCFB54B), (2, 0, 0xB89F3E), (-2, 0, 0xB89F3E)] as [(Int, Int, UInt32)] {
                b.set(cx + dx, cy + dy, c)
            }
        }
        // 地面：顶面是亮的辰砂，下面辰砂与硫磺方块交错，越深越暗
        for y in ground..<b.rows {
            let d = y - ground
            for x in 0..<b.cols {
                let c: UInt32
                if d == 0 { c = noise(x, y, 2) < 0.3 ? 0xF08A80 : 0xE0706A }
                else if d < 4 { c = pick([0xD0605A, 0xC4554C, 0xDA6A62], x, y) }
                else if d < 16 { c = pick([0xB04A42, 0xA9443C, 0xBC524A, 0x9C3E36], x, y) }
                else {
                    let blockC = ((x / 16) + (d / 16)) % 3 == 0 ? pick([0xB89F3E, 0xA38C36], x, y, 5) : pick([0x8A3029, 0x7E2C26], x, y, 6)
                    c = dither(x, y, Double(d - 16) / Double(max(1, b.rows - ground - 16)) * 0.85) ? shade(blockC, 0.45) : blockC
                }
                b.set(x, y, c)
            }
        }
        // 硫磺池：地面挖下去一格。水面以上是被池水照亮的洞壁（不留黑缝），池壁是辰砂，池水在动态层
        for y in ground..<poolBottom {
            for x in pool { b.set(x, y, ditherRamp(glowRamp, 0.95 - Double(y - ground) * 0.02, x, y)) }
        }
        for y in ground..<poolBottom + 1 {
            b.set(pool.lowerBound - 1, y, 0xA03D36)
            b.set(pool.upperBound + 1, y, 0xA03D36)
        }
        for x in pool { b.set(x, poolBottom, 0xA03D36) }
        // 地面上的硫磺草丛
        for gx in stride(from: 4, to: b.cols, by: 19) where !pool.contains(gx) && !pool.contains(gx + 7) {
            let h = 3 + Int(noise(gx, 0, 11) * 4)
            for dy in 0..<h { for dx in 0..<(7 - dy) where noise(gx + dx, dy, 12) > 0.25 {
                b.set(gx + dx + dy / 2, ground - 1 - dy, ditherRamp([0xB89F3E, 0xE8D25A, 0xFFF08A], Double(dy) / Double(h), gx + dx, dy))
            } }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let (ground, pool, poolTop, poolBottom) = layout(b)
        // 池水：表面起伏，水体明暗缓慢流动
        for x in pool {
            let surface = poolTop + (sin(Double(x) * 0.45 + t * 2.6) > 0.55 ? -1 : 0)
            for y in surface..<poolBottom {
                let w = sin(Double(x) * 0.28 + Double(y) * 0.55 - t * 1.8)
                let c: UInt32 = y == surface ? 0xC8FFEA : (w > 0.55 ? 0x5BE3B4 : (w < -0.6 ? 0x2AA582 : 0x3BC79A))
                b.set(x, y, c)
            }
        }
        // 气泡：从池底升起，到水面破掉
        for i in 0..<7 {
            let p = (t * (0.32 + Double(i % 3) * 0.08) + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let bx = pool.lowerBound + 3 + Int(noise(i, 0, 21) * Double(pool.count - 6))
            let by = poolBottom - 1 - Int(p * Double(poolBottom - poolTop))
            if p < 0.9 {
                b.set(bx, by, 0xFFF27A)
                if p > 0.4 { b.set(bx + 1, by, 0xFFF27A) }
            } else {
                for (dx, dy) in [(-2, -1), (2, -1), (0, -3), (-1, -2), (1, -2)] { b.set(bx + dx, poolTop + dy, 0xF2EC9C) }
            }
        }
        // 硫磺立方：节奏不一的跳（偶尔连跳两下），小的会在地上滑一段；眼睛看向玩家，会眨眼
        func cubeAt(size n: Int, x: Int, hops: [(start: Double, height: Double)], cycle: Double, slide: (Double, Double, Int)?,
                    lookAway: ClosedRange<Double>?, blinkEvery: Double) {
            let p = t.truncatingRemainder(dividingBy: cycle)
            var lift = 0.0, squash = 0.0, dx = 0.0
            for h in hops {
                let k = (p - h.start) / 0.62
                if (0..<1).contains(k) { lift = 4 * k * (1 - k) * h.height }
                let land = (p - h.start - 0.62) / 0.3
                if (0..<1).contains(land) { squash = max(squash, (1 - land) * 0.22) }
            }
            if let (s0, s1, dist) = slide {
                // 滑出去再滑回来，滑的时候身体压低拉长
                let out = ramp(p, s0, s0 + (s1 - s0) * 0.4), back = ramp(p, s0 + (s1 - s0) * 0.6, s1)
                dx = Double(dist) * (out - back)
                if p > s0 && p < s1 { squash = max(squash, 0.12) }
            }
            // 静止时也有一点果冻似的起伏
            if lift == 0 && squash == 0 { squash = max(0, sin(t * 3.1 + Double(n))) * 0.05 }
            let looking = (lookAway?.contains(p) ?? false) ? -1 : 1
            let blink = (t + Double(n)).truncatingRemainder(dividingBy: blinkEvery) < 0.14
            let sprite = Self.cube(size: n, look: looking, blink: blink)
            let sq = Int((Double(n) * squash).rounded())
            let cx = x + Int(dx.rounded())
            let shadowW = max(2, n - 2 - Int(lift / 3))
            for i in 0..<shadowW { b.set(cx + (n - shadowW) / 2 + i, ground, 0x5A1F1A) }
            b.blit(sprite, x: cx - sq / 2, bottom: ground - 1 - Int(lift.rounded()), w: n + sq, h: n - sq)
        }
        cubeAt(size: 16, x: Int(Double(b.cols) * 0.13), hops: [(0.4, 12), (3.0, 12), (3.75, 7), (6.6, 14)], cycle: 8.4,
               slide: nil, lookAway: nil, blinkEvery: 3.7)
        cubeAt(size: 9, x: Int(Double(b.cols) * 0.25), hops: [(1.1, 9), (2.4, 8), (6.9, 10)], cycle: 7.3,
               slide: (3.6, 5.6, 9), lookAway: 4.4...5.2, blinkEvery: 2.9)
        // 洞里飘着的硫磺微粒
        for i in 0..<36 {
            let speed = 0.015 + noise(i, 1, 31) * 0.03
            let p = (t * speed + noise(i, 2, 31)).truncatingRemainder(dividingBy: 1)
            let px = Int(noise(i, 3, 31) * Double(b.cols)) + Int(sin(t * 0.7 + Double(i)) * 2)
            let py = ground - 2 - Int(p * Double(ground - 4))
            if sin(t * 2 + Double(i)) > -0.3 { b.set(px, py, i % 4 == 0 ? 0xF2E68A : 0xB9A64B) }
        }
        // 玩家手里拿着一块硫磺：硫磺立方对方块很感兴趣
        let props = PlayerProps(held: HeldItem(sprite: Self.sulfurBlock, swings: false))
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props), x: Int(Double(b.cols) * 0.76), feet: ground - 1, t: t)
    }
}

// MARK: - 还没有专属场景的版本：主世界平原

struct Plains: DotScene {
    let id = "plains"
    let background: UInt32 = 0x0B0D12

    func paintStatic(_ b: inout DotBuffer) {
        let ground = Int(Double(b.rows) * 0.6)
        for y in 0..<ground {
            let k = Double(y) / Double(ground)
            let c: UInt32 = k < 0.5 ? 0x6E98EC : (k < 0.8 ? 0x86AAF2 : 0xA5C1F6)
            for x in 0..<b.cols { b.set(x, y, noise(x, y, 1) < 0.04 ? shade(c, 1.06) : c) }
        }
        // 远山
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.03) * 0.5 + 0.5) * 18 + noise(x / 6, 0, 2) * 6)
            for y in (ground - h)..<ground { b.set(x, y, pick([0x5F8C4E, 0x547F45, 0x6A9757], x, y, 3)) }
        }
        // 草方块与泥土
        for y in ground..<b.rows {
            let depth = max(0.4, 1 - Double(y - ground) / Double(b.rows - ground) * 0.6)
            for x in 0..<b.cols {
                let c: UInt32
                if y - ground < 3 || (y - ground < 6 && noise(x, y, 4) < 0.4) { c = pick([0x5DA03F, 0x6DB34A, 0x4F8F35], x, y, 5) }
                else if y - ground < 48 { c = pick([0x8A5A33, 0x6F4627, 0x9B6B3F, 0x7C4F2C], x, y, 6) }
                else { c = pick([0x7F7F7F, 0x6E6E6E, 0x8C8C8C], x, y, 7) }
                b.set(x, y, shade(c, depth))
            }
        }
        // 一棵橡树
        let tx = Int(Double(b.cols) * 0.22)
        b.fill(tx, ground - 40, 4, 40, 0x6B5133)
        for y in (ground - 64)..<(ground - 32) {
            for x in (tx - 18)..<(tx + 22) where noise(x, y, 8) > 0.12 { b.set(x, y, pick([0x3E7A2C, 0x4A8A34, 0x356A26], x, y, 9)) }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let ground = Int(Double(b.rows) * 0.6)
        // 方块云从右往左飘
        for i in 0..<5 {
            let w = 24 + Int(noise(i, 0, 41) * 30)
            let y = 6 + Int(noise(i, 1, 41) * Double(ground) * 0.35)
            let span = Double(b.cols + w)
            let x = Int(span - (t * (2 + noise(i, 2, 41) * 2) + noise(i, 3, 41) * span).truncatingRemainder(dividingBy: span)) - w
            b.fill(x, y, w, 4, 0xF4F7FF)
            b.fill(x + 6, y - 3, max(4, w - 14), 3, 0xF4F7FF)
            for dx in stride(from: 0, to: w, by: 2) { b.set(x + dx, y + 4, 0xD5E1FB) }
        }
        Player.draw(&b, look: cast.player, pose: Player.idle(t, props: PlayerProps()), x: Int(Double(b.cols) * 0.76), feet: ground - 1, t: t)
    }
}

enum DotScenes {
    /// 按游戏版本选场景：同一个大版本（以及它的快照、预发布）都用同一个场景
    static func scene(for version: String) -> DotScene {
        guard let (major, minor) = family(version) else { return Plains() }
        // 1.21 之后每个小版本都是一次独立的更新
        if (major, minor) == (1, 21) {
            switch patch(version) {
            case 4: return GardenAwakens()
            case 5: return SpringToLife()
            case 6...8: return ChaseTheSkies()
            case 9...10: return CopperAge()
            case 11...: return MountsOfMayhem()
            default: return TrickyTrials()
            }
        }
        switch (major, minor) {
        case (1, 0), (1, 1): return TheEnd()
        case (1, 2): return JungleUpdate()
        case (1, 3): return DesertTrade()
        case (1, 4): return PrettyScary()
        case (1, 5): return RedstoneUpdate()
        case (1, 6): return HorseUpdate()
        case (1, 7): return ChangedTheWorld()
        case (1, 8): return PvpArena()
        case (1, 9): return CombatUpdate()
        case (1, 10): return Frostburn()
        case (1, 11): return Exploration()
        case (1, 12): return WorldOfColor()
        case (1, 13): return UpdateAquatic()
        case (1, 14): return VillageAndPillage()
        case (1, 15): return BuzzyBees()
        case (1, 16): return NetherUpdate()
        case (1, 17): return CavesAndCliffsI()
        case (1, 18): return CavesAndCliffsII()
        case (1, 19): return WildUpdate()
        case (1, 20): return TrailsAndTales()
        case (1, 21): return TrickyTrials()
        case (26, 1): return TinyTakeover()
        case (26, 2): return SulfurCaves()
        case (26, 3): return WildernessBound()
        case (26, 4): return IceCaves()
        default: return Plains()
        }
    }
}

// MARK: - 视图

/// 静态层缓存：场景或尺寸变化时重画
@MainActor
final class DotStaticCache {
    private var key = ""
    private var image: CGImage?

    func image(for scene: DotScene, cols: Int, rows: Int, cell: CGFloat, scale: CGFloat) -> CGImage? {
        let k = "\(scene.id)-\(cols)x\(rows)-\(cell)-\(scale)"
        if k == key, let image { return image }
        var buf = DotBuffer(cols: cols, rows: rows)
        scene.paintStatic(&buf)
        image = DotRenderer.render(buf, cell: cell, scale: scale, background: scene.background)
        key = k
        return image
    }
}

enum DotRenderer {
    /// 每个像素铺满整格，没有缝也没有描边；质感来自有序抖动
    static let dotRatio: CGFloat = 1

    /// 画到屏幕前统一提一点饱和度与亮度，让点阵更鲜亮
    static func vivid(_ v: UInt32) -> UInt32 {
        var r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        let sat = 1.28, lift = 1.1
        r = (l + (r - l) * sat) * lift; g = (l + (g - l) * sat) * lift; b = (l + (b - l) * sat) * lift
        func c(_ x: Double) -> UInt32 { UInt32(max(0, min(255, x * 255))) }
        return (c(r) << 16) | (c(g) << 8) | c(b)
    }

    static func render(_ b: DotBuffer, cell: CGFloat, scale: CGFloat, background: UInt32) -> CGImage? {
        let w = Int(CGFloat(b.cols) * cell * scale), h = Int(CGFloat(b.rows) * cell * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color(background))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let c = cell * scale
        ctx.setShouldAntialias(false)
        for y in 0..<b.rows {
            for x in 0..<b.cols {
                let v = b.px[y * b.cols + x]
                guard v != 0 else { continue }
                let vv = vivid(v & 0xFFFFFF)
                // 略微外扩，避免相邻像素之间出现抗锯齿的细缝
                ctx.setFillColor(color(vv))
                ctx.fill(CGRect(x: CGFloat(x) * c, y: CGFloat(h) - CGFloat(y + 1) * c, width: c, height: c).insetBy(dx: -0.25, dy: -0.25))
            }
        }
        return ctx.makeImage()
    }

    static func color(_ v: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// 故障效果：每隔几秒一次很短的爆发，几条横带错位，带青 / 品红的色边
enum Glitch {
    struct Band { let y: Int; let h: Int; let dx: Int }

    static func bands(t: Double, rows: Int) -> [Band] {
        let period = 5.7, burst = 0.32
        let n = Int(t / period)
        let p = t - Double(n) * period
        guard p < burst, rows > 8 else { return [] }
        let frame = Int(p * 30)
        let count = 2 + Int(noise(n, 0, 61) * 3)
        return (0..<count).map { i in
            let y = Int(noise(n, i, 62) * Double(rows - 6))
            let h = 2 + Int(noise(n, i + 7, 63) * 7)
            // 每一帧方向和幅度都在变，看起来是闪的
            let dx = Int((noise(n * 31 + frame, i, 64) - 0.5) * 22)
            return Band(y: y, h: h, dx: dx)
        }
    }
}

struct DotSceneView: View {
    let scene: DotScene
    var cast = SceneCast()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @PState private var cache = DotStaticCache()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                // 每格约 4pt，宽度上大约 250 个点
                let cell = max(3.4, size.width / 250)
                let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
                guard cols > 0, rows > 0 else { return }
                let t = tl.date.timeIntervalSinceReferenceDate
                let frameRect = CGRect(x: 0, y: 0, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
                let staticImage = cache.image(for: scene, cols: cols, rows: rows, cell: cell, scale: displayScale)

                var dyn = DotBuffer(cols: cols, rows: rows)
                scene.paintDynamic(&dyn, t: t, cast: cast)
                // 偶尔闪烁的亮点
                for i in 0..<14 where sin(t * 3 + Double(i) * 1.7) > 0.93 {
                    dyn.set(Int(noise(i, Int(t / 2), 71) * Double(cols)), Int(noise(i, Int(t / 2), 72) * Double(rows) * 0.6), 0xFFFFFF)
                }
                // 同色的像素合成一条路径，减少绘制次数
                var dots: [UInt32: Path] = [:]
                for y in 0..<rows {
                    for x in 0..<cols {
                        let v = dyn.px[y * cols + x]
                        guard v != 0 else { continue }
                        let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                        dots[DotRenderer.vivid(v & 0xFFFFFF), default: Path()].addRect(r.insetBy(dx: -0.2, dy: -0.2))
                    }
                }
                func drawFrame(_ c: inout GraphicsContext) {
                    if let staticImage { c.draw(Image(decorative: staticImage, scale: displayScale), in: frameRect) }
                    for (v, p) in dots { c.fill(p, with: .color(Color(cgColor: DotRenderer.color(v)))) }
                }
                drawFrame(&ctx)
                // 故障带：把几条横带错开重画，两侧加青色和品红的色边
                guard !reduceMotion else { return }
                for band in Glitch.bands(t: t, rows: rows) {
                    let r = CGRect(x: 0, y: CGFloat(band.y) * cell, width: frameRect.width, height: CGFloat(band.h) * cell)
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(r))
                        layer.translateBy(x: CGFloat(band.dx) * cell, y: 0)
                        drawFrame(&layer)
                    }
                    ctx.drawLayer { layer in
                        layer.blendMode = .screen
                        layer.fill(Path(r.offsetBy(dx: CGFloat(band.dx + 2) * cell, dy: 0)), with: .color(Color(red: 0, green: 0.9, blue: 1).opacity(0.22)))
                        layer.fill(Path(r.offsetBy(dx: CGFloat(band.dx - 2) * cell, dy: 0)), with: .color(Color(red: 1, green: 0.1, blue: 0.8).opacity(0.18)))
                    }
                }
            }
        }
        .background(Color(cgColor: DotRenderer.color(scene.background)))
        .accessibilityHidden(true)
    }
}
