import SwiftUI

// MARK: - 1.0 到 1.11 的老版本
//
// 画法与 DotSceneVersions.swift 相同：先查 minecraft.wiki 的渲染图和贴图，按真实尺寸（1 格 = 16 点）画。
// 只有末影龙太大（16 格长）放不进画面，画成远处盘旋的样子。

// MARK: - 1.0 Adventure Update：末地与末影龙

/// 1.0 正式版加入了末地、末影龙、附魔台和酿造台。末地的主岛：黑曜石柱顶上的末影水晶转着圈，
/// 末影龙在远处的天上盘旋，飞近水晶时被一道光束治疗；末影人在柱子间晃悠；玩家拿着附魔过的钻石剑（剑身流过一道紫光）
struct TheEnd: DotScene {
    let id = "1.0"
    let background: UInt32 = 0x0C0814

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.68) }
    private func pillars(_ b: DotBuffer) -> [(x: Int, h: Int)] {
        [(0.08, 62), (0.3, 48), (0.5, 70), (0.92, 54)].map { (Int(Double(b.cols) * $0.0), $0.1) }
    }

    /// 末影龙（侧面，朝右）：黑色的长身子、长脖子、长尾巴，背上一排灰色的骨刺，紫色的眼睛；
    /// 翅膀是深灰的膜，flap 为扇动的相位（-1 向下，1 向上）。远处的龙按 scale 缩小
    static func dragon(_ b: inout DotBuffer, x: Int, y: Int, flap: Double, facingRight: Bool) {
        let body: [UInt32] = [0x1A1A1E, 0x141418, 0x222226, 0x0E0E10]
        func put(_ dx: Int, _ dy: Int, _ c: UInt32) { b.set(x + (facingRight ? dx : -dx), y + dy, c) }
        /// 翅膀：肩膀、翼尖、后缘三点围成的一片膜，骨架是从肩膀到翼尖的灰线，膜上几道细骨
        func wing(tip: (Double, Double), back: (Double, Double), tone: Double) {
            let a = (2.0, -4.0)
            let minX = Int(min(a.0, tip.0, back.0)), maxX = Int(max(a.0, tip.0, back.0))
            let minY = Int(min(a.1, tip.1, back.1)), maxY = Int(max(a.1, tip.1, back.1))
            func side(_ p: (Double, Double), _ q: (Double, Double), _ r: (Double, Double)) -> Double { (q.0 - p.0) * (r.1 - p.1) - (q.1 - p.1) * (r.0 - p.0) }
            for py in minY...maxY { for px in minX...maxX {
                let pt = (Double(px), Double(py))
                let d1 = side(a, tip, pt), d2 = side(tip, back, pt), d3 = side(back, a, pt)
                let inside = (d1 >= 0 && d2 >= 0 && d3 >= 0) || (d1 <= 0 && d2 <= 0 && d3 <= 0)
                if inside { put(px, py, shade(noise(px, py, 2) < 0.15 ? 0x3A3A46 : 0x2E2E38, tone)) }
            } }
            for k in 0...30 {
                let f = Double(k) / 30
                put(Int(a.0 + (tip.0 - a.0) * f), Int(a.1 + (tip.1 - a.1) * f), shade(0x6A6A72, tone))
                for rib in [0.45, 0.75] where k % 2 == 0 {
                    let s0 = (a.0 + (tip.0 - a.0) * rib, a.1 + (tip.1 - a.1) * rib)
                    let e = (s0.0 + (back.0 - s0.0) * f * 0.9, s0.1 + (back.1 - s0.1) * f * 0.9)
                    put(Int(e.0), Int(e.1), shade(0x4A4A54, tone))
                }
            }
        }
        // 远处那片翅膀（暗一点）
        let up = 0.3 + 0.7 * flap
        wing(tip: (0, -6 - 26 * up), back: (-26, -4), tone: 0.65)
        // 尾巴：往后渐细，末端微微摆动，背上一排骨刺
        for k in 0..<40 {
            let tx = -16 - k, ty = Int((sin(Double(k) * 0.16 + flap) * 2).rounded())
            let w = k < 10 ? 3 : (k < 26 ? 2 : 1)
            for dy in -w..<w { put(tx, ty + dy, pick(body, k, dy, 1)) }
            if k % 4 == 0 { put(tx, ty - w - 1, 0x6A6A70) }
        }
        // 身子
        for dx in -16...14 { for dy in -6...5 where Double(dx * dx) / 240 + Double(dy * dy) / 34 < 1 { put(dx, dy, pick(body, dx, dy, 2)) } }
        for dx in stride(from: -14, through: 12, by: 4) { put(dx, -7, 0x6A6A70); put(dx, -8, 0x5A5A60) }
        // 脖子往前上方，头是长方的，下巴一道缝，紫色的眼睛
        for k in 0..<14 { for dy in -2...2 { put(14 + k, -3 - k / 3 + dy, pick(body, k, dy, 3)) } }
        for dx in 0..<14 { for dy in -4...2 { put(28 + dx, -9 + dy, dx > 6 && dy == 1 ? 0x0A0A0C : pick(body, dx, dy, 4)) } }
        for k in stride(from: 15, to: 28, by: 4) { put(k, -6 - (k - 14) / 3, 0x6A6A70) }
        put(31, -14, 0x6A6A70); put(34, -14, 0x6A6A70)
        put(32, -11, 0xD06AF0); put(33, -11, 0xE8A8FF)
        // 腿缩在身下
        for (lx, ly) in [(-8, 6), (-8, 7), (-7, 8), (8, 6), (8, 7), (9, 8)] { put(lx, ly, 0x141418) }
        // 近处的翅膀
        wing(tip: (-6, -6 - 34 * up), back: (-34, -1), tone: 1)
    }

    /// 末影水晶（8×8，转着的玻璃框里一块粉色的核心）
    static func crystal(_ b: inout DotBuffer, x: Int, y: Int, t: Double) {
        let k = Int(t * 6) % 4
        for dy in 0..<8 { for dx in 0..<8 {
            let edge = dx == 0 || dy == 0 || dx == 7 || dy == 7
            let core = (2...5).contains(dx) && (2...5).contains(dy)
            if edge && (dx + dy + k) % 3 == 0 { b.set(x + dx, y + dy, 0xE8F0FF) }
            else if core { b.set(x + dx, y + dy, (dx + dy + k) % 2 == 0 ? 0xE85AD8 : 0xB83AB0) }
            else if edge { b.set(x + dx, y + dy, 0xA8B8E0) }
        } }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 末地的天：深紫黑，带一点点杂色
        for y in 0..<g { for x in 0..<b.cols {
            let n = noise(x / 2, y / 2, 90)
            b.set(x, y, n < 0.08 ? 0x2A1E3A : (n < 0.3 ? 0x16101E : 0x0E0A16))
        } }
        // 远处的小浮岛
        for (cx, cy, w) in [(0.66, 0.3, 26), (0.2, 0.18, 16)] {
            let x0 = Int(Double(b.cols) * cx), y0 = Int(Double(g) * cy)
            for dy in 0..<min(6, w / 4) { for dx in (dy * 2)..<(w - dy * 2) { b.set(x0 + dx, y0 + dy, dy == 0 ? 0xC8C88E : 0x8A8A60) } }
        }
        // 黑曜石柱
        for (x, h) in pillars(b) {
            for y in (g - h)..<g { for dx in 0..<14 {
                let c = pick([0x14101C, 0x241A30, 0x0E0A14, 0x2E2040], x + dx, y, 91)
                b.set(x + dx, y, dx == 0 ? 0x3A2A4E : (dx == 13 ? 0x0A0810 : c))
            } }
            // 柱顶的基岩
            b.fill(x + 3, g - h - 2, 8, 2, 0x4A4A4A)
        }
        // 主岛：末地石
        Paint.strata(&b, from: g, top: [0xDCDEA0, 0xE8E8B0, 0xC8C88E, 0xD4D49A], topRows: 20,
                     mid: [0xC8C88E, 0xB8B880, 0xD0D096], midRows: 16, deep: [0xA8A876, 0x98986A], seed: 92)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 水晶
        for (x, h) in pillars(b) { Self.crystal(&b, x: x + 3, y: g - h - 11 + Int((sin(t * 2 + Double(x)) * 1.5).rounded()), t: t) }
        // 末影龙：在远处的天上来回盘旋（14 秒一圈），飞到第三根柱子上方时水晶射出治疗光束
        let p = t.truncatingRemainder(dividingBy: 14) / 14
        let right = p < 0.5
        let q = right ? p * 2 : (p - 0.5) * 2
        let dx = right ? -40 + q * Double(b.cols + 80) : Double(b.cols + 40) - q * Double(b.cols + 80)
        let dy = Double(g) * 0.34 + sin(q * .pi * 2) * 10
        let flap = sin(t * 3.2)
        Self.dragon(&b, x: Int(dx), y: Int(dy), flap: flap, facingRight: right)
        let (cx, ch) = pillars(b)[2]
        if abs(dx - Double(cx)) < 40 {
            let sx = Double(cx + 7), sy = Double(g - ch - 7)
            for k in 0..<60 {
                let f = Double(k) / 60
                let x = Int(sx + (dx - sx) * f), y = Int(sy + (dy - sy) * f)
                if (k + Int(t * 20)) % 3 != 0 { b.set(x, y, k % 2 == 0 ? 0xF0C8FF : 0xD06AF0) }
            }
        }
        // 末影人：在柱子之间慢慢走，偶尔瞬移（紫色粒子）
        let ep = t.truncatingRemainder(dividingBy: 10)
        let ex = Int(Double(b.cols) * (ep < 5 ? 0.18 : 0.4)) + Int(sin(t * 0.5) * 6)
        let enderman = Sprite(width: 8, height: 46) { x, y in
            if y < 8 { return (y == 4 && (x == 1 || x == 2 || x == 5 || x == 6)) ? (x == 2 || x == 5 ? 0xE8A8FF : 0xC86AE0) : 0x141414 }
            if y < 20 { return (2...5).contains(x) ? 0x0E0E0E : ((x == 0 || x == 7) ? 0x161616 : nil) }
            if y < 30 && (x == 0 || x == 7) { return 0x161616 }
            if (x == 2 || x == 5) && y >= 20 { return 0x121212 }
            return nil
        }
        b.blit(enderman, x: ex, bottom: g - 1)
        if (4.6...5.4).contains(ep) || ep > 9.6 || ep < 0.4 {
            for i in 0..<14 { b.set(ex - 4 + Int(noise(i, Int(t * 8), 93) * 16), g - 4 - Int(noise(i, Int(t * 8), 94) * 46), 0xC86AE0) }
        }
        // 附魔钻石剑：剑身上流过一道紫光
        let band = Int(t * 8) % 18
        let base = HeldItem.diamondSword.sprite
        let glint = Sprite(width: base.width, height: base.height) { x, y in
            let v = base.px[y * base.width + x]
            guard v != 0 else { return nil }
            return abs((x + y) - band) < 2 ? 0xC88AF8 : v & 0xFFFFFF
        }
        let props = PlayerProps(held: HeldItem(sprite: glint))
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 2), x: Int(Double(b.cols) * 0.76), feet: g - 1, t: t)
    }
}

// MARK: - 1.2：丛林与豹猫

/// 1.2 加入了丛林（高大的丛林木、藤蔓、可可豆）和豹猫，用生鱼可以把豹猫驯服成猫。
/// 丛林里：豹猫从灌木后面探出头，压低身子一点点挪到拿着生鳕鱼、一动不动的玩家跟前，冒出爱心，变成一只虎斑猫
struct JungleUpdate: DotScene {
    let id = "1.2"
    let background: UInt32 = 0x1E3A1A

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 豹猫（朝右，22×11，约 0.7 格高）：黄色带棕色斑点，绿眼睛，细长的尾巴；crouch 时压低身子；cat 时换成虎斑猫的颜色
    static func ocelot(crouch: Bool, step: Int, cat: Bool) -> Sprite {
        let fur: UInt32 = cat ? 0xA8A8A8 : 0xF0C860, spot: UInt32 = cat ? 0x5A5A5A : 0xB07A3A, belly: UInt32 = cat ? 0xD8D8D8 : 0xF8E0A0
        let low = crouch ? 2 : 0
        return Sprite(width: 22, height: 12) { x, y in
            let yy = y - low
            // 尾巴：从屁股往后上翘
            if x <= 4 && yy >= 1 && yy <= 4 && (4 - x) == yy - 1 { return x % 2 == 0 ? fur : spot }
            // 身子 12×4
            if (4...15).contains(x) && (4...7).contains(yy) {
                if yy == 7 { return belly }
                return noise(x, yy, cat ? 96 : 95) < 0.3 ? spot : fur
            }
            // 头 5×5，耳朵竖着
            if (15...19).contains(x) && (2...6).contains(yy) {
                if yy == 4 && x == 18 { return 0x3A9A3A }
                if yy == 6 && x == 19 { return 0x6A4A3A }
                return fur
            }
            if (x == 16 || x == 18) && yy == 1 { return spot }
            if x == 20 && (5...6).contains(yy) { return belly }
            // 腿
            for (i, lx) in [5, 7, 13, 15].enumerated() where x == lx {
                let up = i % 2 == step ? 1 : 0
                if (8...(11 - up)).contains(yy) || (8...(11 - up)).contains(y) && y >= 8 + low { return y == 11 - up ? belly : fur }
            }
            return nil
        }
    }

    static let rawCod = HeldItem(sprite: Sprite([
        "..ff....", ".fFFFF..", "fFkFFFFt", ".FFFFFtt", "..ff..t.",
    ], ["f": 0xC8A880, "F": 0xB09070, "k": 0x1E1E1D, "t": 0x8A7058]), swings: false)

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x3E7AA8, 0x5A9AC0, 0x86BCD8, 0xB4D8E4])
        // 远处密密的树冠
        for x in 0..<b.cols {
            let h = Int(Double(g) * 0.55 + sin(Double(x) * 0.06) * 8 + noise(x / 5, 0, 97) * 10)
            for y in (g - h)..<g { b.set(x, y, dither(x, y, 0.5) ? 0x2E5A22 : 0x26501C) }
        }
        // 高大的丛林木：2×2 的树干，藤蔓垂下来，树干上挂着可可豆
        for (k, cx) in [0.08, 0.42, 0.97].enumerated() {
            let x0 = Int(Double(b.cols) * cx) - 8
            for y in 0..<g { for dx in 0..<16 {
                let c = pick([0x56441E, 0x6E5A2A, 0x4A3A18, 0x625020], dx / 2, y / 2, 98 + k)
                b.set(x0 + dx, y, dx == 0 ? 0x3A2E12 : c)
            } }
            for dx in [-2, 17] { for y in 0..<(g - 10 - k * 6) where noise(x0 + dx, y / 3, 99) > 0.25 { b.set(x0 + dx, y, pick([0x3E8E26, 0x2E7A1E], dx, y, 100)) } }
            for (i, cy) in [g - 40, g - 58].enumerated() where k != 1 || i == 0 {
                b.fill(x0 + 16, cy, 4, 6, 0xB0602E); b.fill(x0 + 16, cy, 4, 1, 0x8A6A2A); b.set(x0 + 17, cy + 2, 0xD08040)
            }
        }
        // 顶上的树叶
        for x in 0..<b.cols {
            let h = 16 + Int(sin(Double(x) * 0.11) * 4 + noise(x / 3, 1, 101) * 6)
            for y in 0..<h { b.set(x, y, pick([0x2E7A1E, 0x3E8E26, 0x50A030, 0x267018], x, y, 102)) }
            if noise(x, 2, 103) > 0.86 { for y in h..<(h + 8 + Int(noise(x, 3, 103) * 26)) { b.set(x, y, pick([0x3E8E26, 0x2E7A1E], x, y, 104)) } }
        }
        // 地面：草和灌木
        Paint.strata(&b, from: g, top: [0x4F8F35, 0x5DA03F, 0x3E7A2C], topRows: 4,
                     mid: [0x6F4627, 0x8A5A33, 0x5E3C22], midRows: 30, deep: [0x6E6E6E, 0x7F7F7F], seed: 105)
        for (cx, w) in [(0.18, 26), (0.58, 18)] {
            let x0 = Int(Double(b.cols) * cx)
            for dy in 0..<12 { for dx in 0..<w where Double((dx - w / 2) * (dx - w / 2)) / Double(w * w / 4) + Double(dy * dy) / 144 < 1 {
                b.set(x0 + dx, g - 1 - dy, pick([0x3E8E26, 0x50A030, 0x2E7A1E], dx, dy, 106))
            } }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.falling(&b, t: t, count: 10, colors: [0x50A030, 0x3E8E26], top: 20, bottom: g, speed: 0.03, seed: 107)
        // 鹦鹉一样的小飞虫……这里只有几只蝴蝶似的光点
        let px = Int(Double(b.cols) * 0.76)
        // 时间线（16 秒一轮）：探头 → 压低身子挪过去 → 爱心 → 变成猫，坐在玩家旁边 → 跑回灌木
        let p = t.truncatingRemainder(dividingBy: 16)
        let hide = Double(b.cols) * 0.2, near = Double(px - 24)
        var ox = hide, crouch = true, cat = false, flip = false, step = 2
        switch p {
        case ..<2: ox = hide
        case ..<7: ox = hide + (near - hide) * (p - 2) / 5; step = Int(t * 3) % 2
        case ..<9: ox = near
        case ..<13: ox = near; cat = true; crouch = false
        default: ox = near - (near - hide) * ease((p - 13) / 3); cat = true; crouch = false; flip = true; step = Int(t * 6) % 2
        }
        b.blit(Self.ocelot(crouch: crouch, step: step, cat: cat), x: Int(ox), bottom: g - 1, flip: flip)
        // 灌木挡住一半（探头的时候）
        if p < 2 {
            let x0 = Int(Double(b.cols) * 0.18)
            for dy in 0..<10 { for dx in 0..<16 where Double((dx - 13) * (dx - 13)) / 169 + Double(dy * dy) / 100 < 1 { b.set(x0 + dx, g - 1 - dy, pick([0x3E8E26, 0x50A030], dx, dy, 106)) } }
        }
        // 爱心
        if (7.4...10).contains(p) {
            for i in 0..<3 {
                let f = ((p - 7.4) * 0.8 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let hx = Int(ox) + 14 + i * 3, hy = g - 14 - Int(f * 14)
                b.blit(Sprite([".r.r.", "rRrRr", "rRRRr", ".rRr.", "..r.."], ["r": 0xC81E2E, "R": 0xF0384A]), x: hx, bottom: hy)
            }
        }
        let props = PlayerProps(held: Self.rawCod)
        var pose = Player.idle(t, props: props, phase: 4)
        if (1.5...9).contains(p) { pose.armAngle = 0.7; pose.lookBack = false; pose.headDip = 1 }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.3：沙漠神殿与绿宝石交易

/// 1.3 加入了沙漠神殿、丛林神殿、绿宝石和村民交易、末影箱、绊线。
/// 沙漠神殿前：玩家递出一颗绿宝石，村民接过去，换回一本附魔书，头上冒出绿色的开心粒子
struct DesertTrade: DotScene {
    let id = "1.3"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    static let emerald = Sprite([
        "..ggg..", ".gLGGg.", "gLGGGGg", "gGGGGDg", ".gGGDg.", "..ggg..",
    ], ["g": 0x0A7A2E, "L": 0xA8F8C8, "G": 0x18D058, "D": 0x0E9A3A])

    static let book = Sprite([
        "bbbbbbb", "bPPPPPb", "bPpPpPb", "bPPPPPb", "bbbbbbb",
    ], ["b": 0x8A3A2A, "P": 0xB85AC8, "p": 0xE8A8F0])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6, 0xD8E0E8])
        // 沙漠神殿：砂岩的台阶状主体，两座塔，塔门上是橙色陶瓦拼的图案
        let sand: [UInt32] = [0xE0D2A0, 0xD8C890, 0xE8DCAE, 0xCFC088]
        let x0 = Int(Double(b.cols) * 0.04), w = 120
        for step in 0..<4 {
            let inset = step * 10, top = g - 16 - step * 8
            for y in top..<(top + 8) { for x in (x0 + 26 + inset)..<(x0 + w - 26 - inset) {
                b.set(x, y, y == top ? 0xF0E6C0 : pick(sand, x / 4, y / 4, 110))
            } }
        }
        b.fill(x0 + 26, g - 16, w - 52, 16, 0xD8C890)
        for tower in [x0, x0 + w - 28] {
            for y in (g - 54)..<g { for x in tower..<(tower + 28) {
                var c = pick(sand, x / 4, y / 4, 111)
                if (y - (g - 54)) % 16 == 0 { c = 0xC8B880 }
                b.set(x, y, c)
            } }
            b.fill(tower - 2, g - 56, 32, 3, 0xF0E6C0)
            // 塔上的陶瓦图案
            let pat = Sprite(["..oo..", ".oOOo.", "oOwwOo", ".oOOo.", "..oo..", "..oo..", ".oooo."], ["o": 0xB0602E, "O": 0xD9844A, "w": 0x2E6EA8])
            b.blit(pat, x: tower + 11, bottom: g - 34)
            b.fill(tower + 10, g - 18, 8, 18, 0x4A3A22)
        }
        // 沙地
        Paint.strata(&b, from: g, top: [0xDBCFA3, 0xE3D7AE, 0xCFC294], topRows: 16,
                     mid: [0xD8C78E, 0xC9B67A], midRows: 16, deep: [0xB5A26A, 0xA69360], seed: 112)
        for x in [Int(Double(b.cols) * 0.62), Int(Double(b.cols) * 0.98)] {
            b.fill(x, g - 16, 4, 16, 0x3E7A2C); for y in stride(from: g - 15, to: g, by: 3) { b.set(x + 1, y, 0x2E5A22) }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        let px = Int(Double(b.cols) * 0.76), vx = Int(Double(b.cols) * 0.56)
        // 时间线（8 秒一轮）
        let p = t.truncatingRemainder(dividingBy: 8)
        var vpose = PlayerPose()
        vpose.headDip = (2.6...3.6).contains(p) ? 1 : 0
        Player.draw(&b, look: .villager, pose: vpose, x: vx, feet: g - 1, t: t + 1.7, facingRight: true)
        // 绿宝石从玩家手里飞到村民手里，书飞回来
        let handP = (Double(px - 4), Double(g - 18)), handV = (Double(vx + 12), Double(g - 18))
        if (1.4...2.6).contains(p) {
            let f = ease((p - 1.4) / 1.2)
            b.blit(Self.emerald, x: Int(handP.0 + (handV.0 - handP.0) * f), bottom: Int(handP.1 - sin(f * .pi) * 8))
        }
        if (3.6...4.8).contains(p) {
            let f = ease((p - 3.6) / 1.2)
            b.blit(Self.book, x: Int(handV.0 + (handP.0 - handV.0) * f), bottom: Int(handV.1 - sin(f * .pi) * 8))
        }
        if (2.6...4.4).contains(p) {
            for i in 0..<6 {
                let f = ((p - 2.6) + Double(i) * 0.3).truncatingRemainder(dividingBy: 1)
                b.set(vx + Int(noise(i, 0, 113) * 12) - 1, g - 34 - Int(f * 10), i % 2 == 0 ? 0x3AE05A : 0x9AF8A8)
            }
        }
        let held: HeldItem? = p < 1.4 ? HeldItem(sprite: Self.emerald, swings: false) : (p > 4.8 && p < 7.4 ? HeldItem(sprite: Self.book, swings: false) : nil)
        let props = PlayerProps(held: held)
        var pose = Player.idle(t, props: props, phase: 0)
        if p < 1.6 || (4.6...6.2).contains(p) { pose.armAngle = 0.9; pose.itemUp = 0.4 }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.4 Pretty Scary Update：凋灵、蝙蝠和烟花

/// 1.4 “相当恐怖的更新”加入了凋灵、女巫、蝙蝠、南瓜派、信标和烟花火箭（1.4.6）。
/// 万圣节的夜里：凋灵飘在左边，三个脑袋轮流朝地面吐凋灵之首；蝙蝠扑腾着乱飞，地上摆着南瓜灯；
/// 玩家放烟花，火箭拖着火星升空，炸开一圈彩色的火花
struct PrettyScary: DotScene {
    let id = "1.4"
    let background: UInt32 = 0x0E1028

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 凋灵（正面，30×36）：中间一个大头、两边两个小头，下面是脊椎和肋骨，尾巴细长；黑灰色，眼睛是浅灰的
    static func wither(t: Double) -> Sprite {
        let dark: [UInt32] = [0x1E1E1E, 0x2A2A2A, 0x141414, 0x343434]
        func head(_ x: Int, _ y: Int, _ x0: Int, _ y0: Int, _ s: Int) -> UInt32? {
            guard (x0..<(x0 + s)).contains(x) && (y0..<(y0 + s)).contains(y) else { return nil }
            let lx = x - x0, ly = y - y0
            if ly == s / 2 - 1 && (lx == 1 || lx == s - 2) { return 0xC8C8C8 }
            if ly == s - 2 && (1..<(s - 1)).contains(lx) && lx % 2 == 0 { return 0x8A8A8A }
            return pick(dark, x, y, 114)
        }
        let sway = Int((sin(t * 2) * 1).rounded())
        return Sprite(width: 30, height: 38) { x, y in
            if let c = head(x, y, 11, 0, 8) { return c }
            if let c = head(x, y, 2, 3 + sway, 6) { return c }
            if let c = head(x, y, 22, 3 - sway, 6) { return c }
            if (2...27).contains(x) && (9...11).contains(y) { return pick(dark, x, y, 115) }   // 肩
            if (13...16).contains(x) && (12...26).contains(y) { return pick(dark, x, y, 116) }  // 脊椎
            if (14...25).contains(y) && y % 3 == 0 && (8...21).contains(x) { return 0x2A2A2A }   // 肋骨
            let tx = 14 + Int(sin(Double(y) * 0.3 + t * 2) * 2)
            if (27...37).contains(y) && (tx...(tx + 1)).contains(x) { return 0x1E1E1E }        // 尾巴
            return nil
        }
    }

    static func bat(flap: Bool) -> Sprite {
        flap ? Sprite(["w.....w", "ww.b.ww", ".wbbbw.", "..bkb..", "...b..."], ["w": 0x2A2018, "b": 0x4A3A2E, "k": 0x1E1E1D])
             : Sprite(["..b.b..", ".wbbbw.", "wwbkbww", "w..b..w"], ["w": 0x2A2018, "b": 0x4A3A2E, "k": 0x1E1E1D])
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x0A0A20, 0x10123A, 0x1A1C4E, 0x2A2A5E])
        // 方形的月亮
        let mx = Int(Double(b.cols) * 0.62), my = 14
        b.fill(mx, my, 16, 16, 0xE8ECF4); b.fill(mx + 3, my + 4, 4, 3, 0xC8CEDA); b.fill(mx + 9, my + 9, 3, 3, 0xC8CEDA)
        for i in 0..<40 { b.set(Int(noise(i, 0, 117) * Double(b.cols)), Int(noise(i, 1, 117) * Double(g) * 0.5), 0xC8CCE8) }
        // 远处光秃秃的树
        for (cx, h) in [(0.04, 50), (0.5, 38), (0.97, 46)] {
            let x = Int(Double(b.cols) * cx)
            b.fill(x, g - h, 3, h, 0x2A2030)
            for (dx, dy, len) in [(-1, 14, 8), (3, 20, 9), (-1, 28, 6), (3, 8, 5)] where dy < h {
                for k in 0..<len { b.set(x + (dx < 0 ? -k : dx + k), g - h + dy - k / 2, 0x2A2030) }
            }
        }
        // 灵魂沙堆（凋灵就是从这里召唤出来的）
        let sx = Int(Double(b.cols) * 0.14)
        b.fill(sx, g - 4, 16, 4, 0x4A3A2E); for x in stride(from: sx, to: sx + 16, by: 3) { b.set(x + 1, g - 3, 0x3A2A22) }
        // 地面
        Paint.strata(&b, from: g, top: [0x3E6A2C, 0x325A24, 0x4A7A34], topRows: 4,
                     mid: [0x4A3222, 0x3E2A1C, 0x54382A], midRows: 30, deep: [0x3E3E3E, 0x4A4A4A], seed: 118)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 南瓜灯：一明一暗
        for (k, cx) in [0.34, 0.46, 0.98].enumerated() {
            let x = Int(Double(b.cols) * cx) - 4
            b.fill(x, g - 9, 9, 8, 0xD8781E); b.fill(x + 4, g - 10, 1, 1, 0x4A6A2A)
            let lit: UInt32 = sin(t * 5 + Double(k) * 2) > -0.3 ? 0xFFE04A : 0xF0A02A
            b.set(x + 2, g - 7, lit); b.set(x + 6, g - 7, lit); b.fill(x + 2, g - 4, 5, 1, lit); b.set(x + 4, g - 5, lit)
        }
        // 凋灵：慢慢上下飘，周围有黑色的粒子；每 3 秒吐一颗凋灵之首砸向地面
        // 原版的凋灵模型渲染时放大一倍，约 3.5 格高；这里按 1.6 倍画
        let wx = Int(Double(b.cols) * 0.08), wy = g - 14 + Int((sin(t * 0.9) * 4).rounded())
        b.blit(Self.wither(t: t), x: wx, bottom: wy, w: 48, h: 61)
        for i in 0..<14 { b.set(wx + Int(noise(i, Int(t * 3), 119) * 54) - 2, wy - Int(noise(i, Int(t * 3), 120) * 64), 0x1A1A1A) }
        let sp = t.truncatingRemainder(dividingBy: 3)
        if sp < 1.2 {
            let f = sp / 1.2
            let sx = wx + 24 + Int(f * 40), sy = wy - 50 + Int(f * f * Double(g - wy + 48))
            b.fill(sx, sy, 4, 4, 0x1E1E1E); b.set(sx + 1, sy + 1, 0xC8C8C8)
        } else if sp < 1.6 {
            let f = (sp - 1.2) / 0.4
            for i in 0..<8 { b.set(wx + 64 + Int(cos(Double(i)) * f * 10), g - 2 - Int(abs(sin(Double(i))) * f * 6), i % 2 == 0 ? 0x3A3A3A : 0x8A8A8A) }
        }
        // 蝙蝠乱飞
        for i in 0..<5 {
            let x = Int(Double(b.cols) * (0.2 + noise(i, 0, 121) * 0.6) + sin(t * (1.1 + Double(i) * 0.3) + Double(i)) * 24)
            let y = Int(Double(g) * (0.2 + noise(i, 1, 121) * 0.4) + cos(t * (1.7 + Double(i) * 0.2)) * 8)
            b.blit(Self.bat(flap: Int(t * 10 + Double(i)) % 2 == 0), x: x, bottom: y)
        }
        // 烟花：4 秒一发，火箭拖着火星升空，在天上炸开
        let px = Int(Double(b.cols) * 0.76)
        let fp = t.truncatingRemainder(dividingBy: 4), n = Int(t / 4)
        let palettes: [[UInt32]] = [[0xFF4A6A, 0xFFB0C0], [0x4AD8FF, 0xC8F4FF], [0xFFD84A, 0xFFF4B0], [0x8AFF5A, 0xD8FFC0]]
        let pal = palettes[n % palettes.count]
        let rx = px - 14 + Int(noise(n, 0, 122) * 10), burstY = Int(Double(g) * (0.22 + noise(n, 1, 122) * 0.15))
        if fp < 1.2 {
            let y = g - 20 - Int((Double(g - 20 - burstY)) * ease(fp / 1.2))
            b.fill(rx, y, 2, 4, 0xC8343A); b.set(rx, y + 1, 0xF0F0F0)
            for k in 1..<8 where dither(rx, y + 4 + k, 1 - Double(k) / 8) { b.set(rx + (k % 2), y + 4 + k, 0xFFD06A) }
        } else if fp < 3 {
            let f = (fp - 1.2) / 1.8
            for i in 0..<28 {
                let a = Double(i) / 28 * 2 * .pi
                let r = 4 + f * 22
                let x = rx + Int(cos(a) * r), y = burstY + Int(sin(a) * r + f * f * 8)
                if sin(t * 30 + Double(i)) > (f - 0.6) * 2 { b.set(x, y, i % 3 == 0 ? pal[1] : pal[0]) }
            }
        }
        var pose = Player.idle(t, props: PlayerProps(), phase: 1)
        if fp < 0.6 { pose.armAngle = 0.9 * (1 - fp / 0.6) }
        Player.draw(&b, look: cast.player, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.5 Redstone Update：漏斗、比较器和红石灯

/// 1.5 红石更新加入了漏斗、红石比较器、阳光探测器、投掷器、陷阱箱和下界石英。
/// 地下的工作间：物品一个个掉进一串漏斗，漏斗把它们送进箱子；比较器读出箱子里的东西，
/// 红石粉一格格亮起来，点亮一排红石灯；玩家拿着下界石英看
struct RedstoneUpdate: DotScene {
    let id = "1.5"
    let background: UInt32 = 0x1A1A1E

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    static let quartz = HeldItem(sprite: Sprite([
        "..w..", ".wQq.", "wQQQq", ".qQq.", "..q..",
    ], ["w": 0xFFFFFF, "Q": 0xE8E0D8, "q": 0xB8ACA0]), swings: false)

    /// 漏斗（16×16，侧面）：上面宽口，下面一截细嘴
    static let hopper = Sprite(width: 16, height: 16) { x, y in
        if y < 10 {
            if y == 0 || x == 0 || x == 15 { return 0x3A3A3E }
            if y < 3 { return (2...13).contains(x) ? 0x1E1E22 : 0x4A4A4E }
            let inset = (y - 3) / 2
            return (inset...(15 - inset)).contains(x) ? (x == inset || x == 15 - inset ? 0x2E2E32 : 0x4A4A4E) : nil
        }
        return (6...9).contains(x) ? (x == 6 ? 0x3A3A3E : 0x4A4A4E) : nil
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 石砖墙
        for y in 0..<g { for x in 0..<b.cols {
            let row = y / 8
            let mortar = y % 8 == 7 || (x + (row % 2) * 8) % 16 == 15
            let c = mortar ? 0x3A3A3E : pick([0x6E6E72, 0x7A7A7E, 0x626266, 0x84848A], x / 16 + row * 7, row, 123)
            b.set(x, y, dither(x, y, 0.25) ? shade(c, 0.8) : c)
        } }
        // 下界石英块的柱子
        for cx in [0.03, 0.98] {
            let x0 = Int(Double(b.cols) * cx) - 6
            for y in 0..<g { for dx in 0..<12 { b.set(x0 + dx, y, dx == 0 || dx == 11 ? 0xC8C0B4 : (dx % 4 == 1 ? 0xE0D8CC : 0xEAE4DA)) } }
        }
        // 一串漏斗（三个）通向箱子
        let hx = Int(Double(b.cols) * 0.1)
        for i in 0..<3 { b.blit(Self.hopper, x: hx + i * 16, bottom: g - 1 - 32 + i * 16) }
        // 箱子
        let cx = hx + 46
        b.fill(cx, g - 14, 16, 14, 0x9A6A2E); b.fill(cx, g - 14, 16, 1, 0x6A4A22); b.fill(cx, g - 9, 16, 1, 0x6A4A22)
        b.fill(cx + 7, g - 11, 2, 4, 0xB8B8B8)
        // 地面：石头
        Paint.strata(&b, from: g, top: [0x8A8A8E, 0x7A7A7E, 0x949498], topRows: 3,
                     mid: [0x6E6E72, 0x7A7A7E, 0x626266], midRows: 20, deep: [0x4A4A4E, 0x3E3E42], seed: 124)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        let hx = Int(Double(b.cols) * 0.1), cx = hx + 46
        // 物品掉进漏斗，一格格往下传（每秒一个）
        let colors: [UInt32] = [0xE8E0D8, 0xD8341F, 0x4AEDD9, 0xF5D74A, 0x5DA03F]
        for k in 0..<4 {
            let q = (t * 0.5 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            let c = colors[(Int(t * 0.5 + Double(k) / 4) + k) % colors.count]
            // 路径：从上面掉进第一个漏斗，经过三个漏斗的嘴，进箱子
            let pts: [(Double, Double)] = [(Double(hx + 6), Double(g - 60)), (Double(hx + 6), Double(g - 40)), (Double(hx + 22), Double(g - 24)),
                                            (Double(hx + 38), Double(g - 8)), (Double(cx + 6), Double(g - 10))]
            let s = q * Double(pts.count - 1), i = min(pts.count - 2, Int(s)), f = s - Double(i)
            let x = pts[i].0 + (pts[i + 1].0 - pts[i].0) * f, y = pts[i].1 + (pts[i + 1].1 - pts[i].1) * f
            b.fill(Int(x), Int(y), 4, 4, c); b.set(Int(x), Int(y), shade(c, 1.2))
        }
        // 比较器：箱子满一点就亮；信号沿着红石粉往右传，点亮红石灯
        let signal = (sin(t * 0.8) * 0.5 + 0.5)
        let compX = cx + 18
        b.fill(compX, g - 3, 14, 3, 0xB8B8B8)
        for (dx, on) in [(2, signal > 0.2), (10, signal > 0.2), (6, signal > 0.6)] {
            b.fill(compX + dx, g - 7, 2, 4, 0x8A6A3A); b.fill(compX + dx, g - 8, 2, 2, on ? 0xFF3A2A : 0x6A1A1A)
        }
        let dustStart = compX + 15, lamps = [0.38, 0.5, 0.62]
        let reach = Int(Double(Int(Double(b.cols) * 0.66) - dustStart) * signal)
        for x in dustStart..<Int(Double(b.cols) * 0.66) {
            let lit = x - dustStart < reach
            b.set(x, g - 1, lit ? (x % 3 == 0 ? 0xFF4A2A : 0xD8241A) : 0x5A1010)
        }
        for (i, lx) in lamps.enumerated() {
            let x = Int(Double(b.cols) * lx)
            let on = x - dustStart < reach
            for dy in 0..<14 { for dx in 0..<14 {
                let edge = dx == 0 || dy == 0 || dx == 13 || dy == 13
                let c: UInt32 = on ? (edge ? 0x9A5A2A : ((dx + dy + i) % 5 == 0 ? 0xFFF0B0 : 0xF8C860)) : (edge ? 0x5A3418 : ((dx + dy) % 5 == 0 ? 0x8A5A30 : 0x6A4224))
                b.set(x + dx, g - 15 - dy, c)
            } }
            if on { for k in 0..<6 where dither(x + k * 3, g - 20, 0.5) { b.set(x - 2 + k * 3, g - 17 - Int(noise(k, Int(t * 4), 125) * 4), 0xFFE08A) } }
        }
        let props = PlayerProps(held: Self.quartz)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 6), x: Int(Double(b.cols) * 0.8), feet: g - 1, t: t)
    }
}

// MARK: - 1.6 Horse Update：马与驴

/// 1.6 马匹更新加入了马、驴、骡、拴绳、干草块、地毯和马铠。
/// 草原上：一头驴被拴绳拴在栅栏上，另一匹栗色的马低头吃草；玩家骑着一匹披着钻石马铠的白马，马时不时扬一下头
struct HorseUpdate: DotScene {
    let id = "1.6"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 马（朝右，按原版模型 1 像素 = 1 点）：身子 22 长 10 高，四条腿 4 宽 11 高（远侧的腿暗一点、错开一点），
    /// 粗脖子往前斜着长出来，鬃毛沿着脖子后沿；头是一个往前下方斜的长方块，嘴在最前面；尾巴从屁股垂下来。
    /// graze 时脖子往前下方伸、嘴碰到地；ears 为驴的长耳朵，muzzle 为驴和骡子发白的嘴；armor 为马铠的两种颜色；
    /// saddle 时背上一副鞍；step 为迈步
    static func horse(coat: [UInt32], mane: UInt32, graze: Bool, step: Int, ears: Bool = false, muzzle: UInt32? = nil,
                      armor: [UInt32]? = nil, saddle: Bool = false, toss: Double = 0) -> Sprite {
        let hoof: UInt32 = 0x3A2E26
        /// 一个斜放的长方块：从 (ox, oy) 沿 angle 方向（0 = 竖直向上，正值往前倾）伸出 len，宽 w；返回 (沿长度的位置, 横向位置)
        func box(_ x: Int, _ y: Int, _ ox: Double, _ oy: Double, _ angle: Double, _ len: Double, _ w: Double) -> (Double, Double)? {
            let dx = Double(x) + 0.5 - ox, dy = Double(y) + 0.5 - oy
            let u = dx * sin(angle) - dy * cos(angle), v = dx * cos(angle) + dy * sin(angle)
            return u >= 0 && u <= len && abs(v) <= w / 2 ? (u, v) : nil
        }
        let neckAngle = graze ? 2.05 : 0.55 - toss, headAngle = graze ? 2.9 : 2.0 - toss * 0.5
        let neckBase = (23.0, 16.0), neckLen = graze ? 12.0 : 13.0
        let neckTop = (neckBase.0 + sin(neckAngle) * neckLen, neckBase.1 - cos(neckAngle) * neckLen)
        return Sprite(width: 40, height: 34) { x, y in
            func coatAt(_ x: Int, _ y: Int, _ k: Double = 1) -> UInt32 { shade(pick(coat, x / 2, y / 2, 126), k) }
            // 耳朵：在头顶靠脖子的地方，驴的耳朵又长又往后斜
            if box(x, y, neckTop.0 - 1, neckTop.1 + 1, neckAngle - 0.35, ears ? 7 : 3, 2) != nil { return coatAt(x, y, 0.85) }
            // 头：往前下方斜的长方块，最前面是嘴，靠上一点是眼睛
            if let (u, v) = box(x, y, neckTop.0 - 2, neckTop.1 + 2, headAngle, 11, 6) {
                if let a = armor, u < 6 { return v < -1.5 ? a[1] : a[0] }
                if u > 8 { return muzzle ?? coatAt(x, y, 0.7) }
                if (2...3).contains(Int(u)) && v < -0.5 && v > -2 { return 0x1E1E1D }
                return coatAt(x, y, v > 1.8 ? 0.85 : 1)
            }
            // 脖子：粗，鬃毛沿着后沿
            if let (_, v) = box(x, y, neckBase.0, neckBase.1, neckAngle, neckLen + 1.5, 7) {
                if v < -1.8 { return mane }
                if let a = armor { return v > 2 ? a[1] : a[0] }
                return coatAt(x, y)
            }
            // 身子
            if (3...24).contains(x) && (12...21).contains(y) {
                if saddle && (9...16).contains(x) && (11...13).contains(y) { return y == 13 ? 0x5A3A22 : 0x7A4E2E }
                if let a = armor, y <= 15 && x >= 14 { return y == 12 ? a[1] : a[0] }
                return y == 21 ? coatAt(x, y, 0.82) : coatAt(x, y)
            }
            if saddle && (9...16).contains(x) && y == 11 { return 0x8A5A34 }
            if saddle && x == 12 && (14...19).contains(y) { return 0x4A3A2A }   // 脚蹬的带子
            // 尾巴
            if (0...2).contains(x) && (13...27).contains(y) && !(x == 0 && y < 16) { return x == 2 && y > 24 ? nil : mane }
            // 腿：近侧两条亮，远侧两条暗、往里错开两点
            for (lx, far, i) in [(6, true, 0), (20, true, 1), (4, false, 1), (18, false, 0)] where (lx...(lx + 3)).contains(x) {
                let up = i == step ? 1 : 0
                if (22...(33 - up)).contains(y) {
                    if y >= 32 - up { return hoof }
                    return coatAt(x, y, far ? 0.72 : (x == lx + 3 ? 0.88 : 1))
                }
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6])
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.02 + 1) * 0.5 + 0.5) * 16 + noise(x / 6, 0, 127) * 5)
            for y in (g - h)..<g { b.set(x, y, pick([0x6A9757, 0x5F8C4E, 0x76A060], x, y, 128)) }
        }
        // 栅栏
        let fx = Int(Double(b.cols) * 0.03)
        for k in 0..<4 {
            b.fill(fx + k * 16 + 6, g - 16, 4, 16, 0x8A6238)
        }
        b.fill(fx + 6, g - 13, 52, 2, 0x8A6238); b.fill(fx + 6, g - 7, 52, 2, 0x8A6238)
        // 干草块：两块叠起来
        for (dx, dy) in [(0, 0), (16, 0), (8, 16)] {
            let x0 = Int(Double(b.cols) * 0.42) + dx, y0 = g - 16 - dy
            for y in 0..<16 { for x in 0..<16 {
                var c = pick([0xC8A82A, 0xB89820, 0xD8B83A], x, y / 3, 129)
                if y == 3 || y == 12 { c = 0x9A3A22 }
                b.set(x0 + x, y0 + y, c)
            } }
        }
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35], topRows: 4,
                     mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30, deep: [0x7F7F7F, 0x6E6E6E], seed: 130)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 4)
        // 驴：拴在栅栏上，拴绳是一条下垂的线
        let dx0 = Int(Double(b.cols) * 0.06)
        let donkey: [UInt32] = [0x7A6A5E, 0x6A5C50, 0x8A7A6C]
        b.blit(Self.horse(coat: donkey, mane: 0x3A2E26, graze: false, step: 2, ears: true, muzzle: 0xC8C0B0,
                          toss: sin(t * 0.5) > 0.8 ? 0.15 : 0), x: dx0, bottom: g - 1)
        let post = (Double(Int(Double(b.cols) * 0.03) + 54), Double(g - 14)), neck = (Double(dx0 + 30), Double(g - 22))
        for k in 0...20 {
            let f = Double(k) / 20
            b.set(Int(post.0 + (neck.0 - post.0) * f), Int(post.1 + (neck.1 - post.1) * f + sin(f * .pi) * 4), 0xB8A070)
        }
        // 吃草的栗色马
        let graze = sin(t * 0.4) > -0.2
        b.blit(Self.horse(coat: [0x8A5A2E, 0x7A4E26, 0x9A6A3A], mane: 0x3A2414, graze: graze, step: 2), x: Int(Double(b.cols) * 0.25), bottom: g - 1)
        // 玩家骑着的白马：披着钻石马铠，朝左，时不时扬头
        let px = Int(Double(b.cols) * 0.7)
        let toss = max(0, sin(t * 0.7) - 0.8) * 2
        let bob = sin(t * 2.4) > 0.6 ? 1 : 0
        b.blit(Self.horse(coat: [0xE8E8E8, 0xD8D8D8, 0xF4F4F4, 0xC8C8C8], mane: 0x9A9A9A, graze: false, step: 2,
                          armor: [0x4AEDD9, 0x1A9B8A], saddle: true, toss: toss), x: px - 8, bottom: g - 1 - bob, flip: true)
        var pose = Player.idle(t, props: PlayerProps(), phase: 8)
        pose.sitting = true
        Player.draw(&b, look: cast.player, pose: pose, x: px + 15, feet: g - 12 - bob, t: t)
    }
}

// MARK: - 1.7 The Update that Changed the World：恶地钓鱼

/// 1.7 “改变世界的更新”重做了地形生成，加入了恶地、黑森林、巨型针叶林等十几种群系，还有染色玻璃、新的花，
/// 并重做了钓鱼（能钓到河豚、热带鱼和宝藏）。恶地的水塘边：玩家甩竿钓鱼，浮漂一沉，拉上来一条河豚
struct ChangedTheWorld: DotScene {
    let id = "1.7"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 钓鱼竿：竖着画（竿梢朝上），跟着手转；比剑长得多
    static let fishingRod = HeldItem(sprite: Sprite(
        [".s.", ".s."] + (0..<22).map { $0 % 3 == 0 ? ".w." : ".W." } + ["wWw", ".w."],
        ["w": 0x6B4A2C, "W": 0x8A6238, "s": 0x4A4A4A]))

    /// 竿梢在场景里的位置：按 Player.draw 里手的位置和物品的转法算（物品转角 = armAngle - π/2 + 0.45 + itemTilt）
    static func rodTip(x: Int, feet: Int, pose: PlayerPose) -> (Double, Double) {
        let h = Double(fishingRod.sprite.height)
        let ax = Double(Player.canvasX)
        let hand = (ax - 1.5 - sin(pose.armAngle) * 10.5, 37 + cos(pose.armAngle) * 10.5)
        let angle = pose.armAngle - .pi / 2 + 0.45 + pose.itemTilt
        return (Double(x + pose.dx) - ax + hand.0.rounded(.down) + (h - 2) * sin(angle),
                Double(feet - 60) + hand.1.rounded(.down) - (h - 2) * cos(angle))
    }

    static let pufferfish = Sprite([
        "..y.y.y..", ".yYYYYYy.", "yYkYYYYYb", "yYYYYYYYb", ".wWWWWWw.", "..y.y.y..",
    ], ["y": 0xE8A81E, "Y": 0xF5C42E, "k": 0x1E1E1D, "b": 0x8AC8E8, "w": 0xF0E0B0, "W": 0xF8ECC8])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6, 0xE8D8C0])
        // 恶地的台地：一层层陶瓦（橙、白、黄、红、棕、浅灰）
        let bands: [UInt32] = [0xB8622E, 0xD07A3A, 0xE8D8C8, 0xA8502A, 0xD8A84A, 0x9A4A2E, 0xC08A6A, 0xB8622E, 0x8A5A42, 0xD07A3A]
        for x in 0..<b.cols {
            let mesa = x < Int(Double(b.cols) * 0.36) || x > Int(Double(b.cols) * 0.82)
            let h = mesa ? Int(Double(g) * 0.62 + noise(x / 12, 0, 131) * 6) : Int(Double(g) * 0.22 + sin(Double(x) * 0.05) * 4)
            for y in (g - h)..<g {
                let c = bands[((y + 3) / 4) % bands.count]
                b.set(x, y, dither(x, y, 0.15) ? shade(c, 0.9) : c)
            }
            // 台地顶上的一层草和泥
            b.set(x, g - h, 0x8A9A3A)
        }
        // 金合欢树（1.7）
        let ax = Int(Double(b.cols) * 0.6)
        for k in 0..<22 { b.fill(ax + k / 4, g - 22 - k, 3, 1, 0x6A5A4A) }
        for dy in 0..<4 { b.fill(ax - 8 + dy, g - 46 + dy, 26 - dy * 2, 1, dy == 0 ? 0x7A9A2E : 0x5E7E22) }
        // 地面：红沙
        Paint.strata(&b, from: g, top: [0xC86A2E, 0xD07A3A, 0xB85E26], topRows: 6,
                     mid: [0xB8622E, 0xA8502A, 0xD07A3A], midRows: 24, deep: [0x9A4A2E, 0x8A5A42], seed: 132)
        // 水塘
        let w0 = Int(Double(b.cols) * 0.18), w1 = Int(Double(b.cols) * 0.62)
        for x in w0..<w1 { for y in g..<(g + 8) {
            let edge = Double(min(x - w0, w1 - x)) / 8
            if Double(y - g) < 8 * min(1, edge) { b.set(x, y, y == g ? 0x5A8AE0 : pick([0x3A64C8, 0x3260BA, 0x4470D0], x, y, 133)) }
        } }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        // 水面的波光
        for i in 0..<10 {
            let x = Int(Double(b.cols) * 0.2) + Int(noise(i, 0, 134) * Double(b.cols) * 0.4) + Int(sin(t + Double(i)) * 3)
            if sin(t * 2 + Double(i)) > 0.3 { b.fill(x, g + 1 + i % 3, 3, 1, 0x9CC8F8) }
        }
        // 时间线（9 秒一轮）：甩竿 → 浮漂在水上漂 → 一沉，冒水泡 → 拉竿，河豚飞上来
        let p = t.truncatingRemainder(dividingBy: 9)
        let px = Int(Double(b.cols) * 0.76)
        let props = PlayerProps(held: Self.fishingRod)
        var pose = Player.idle(t, props: props, phase: 0)
        // 平时竿子斜着伸向水塘；甩竿时往后扬再甩出去，拉竿时往上一提
        pose.armAngle = 0.8
        pose.itemTilt = -0.35
        pose.headDip = 0; pose.lookBack = false
        if p < 0.6 { let k = sin(p / 0.6 * .pi); pose.armAngle = 0.8 + 1.0 * k; pose.itemTilt = -0.35 + 0.9 * k }
        if (6...6.5).contains(p) { let k = sin((p - 6) / 0.5 * .pi); pose.armAngle = 0.8 + 0.7 * k; pose.itemTilt = -0.35 + 0.6 * k }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
        let tip = Self.rodTip(x: px, feet: g - 1, pose: pose)
        let bobX = Double(b.cols) * 0.46
        let bite = (4.6...6).contains(p)
        let bobY = Double(g) + (bite ? 2 : (sin(t * 2) > 0.4 ? 1 : 0)) - 2
        if (0.6...6.1).contains(p) {
            // 鱼线：从竿尖垂到浮漂
            let f0 = min(1, (p - 0.6) / 0.6)
            let endX = tip.0 + (bobX - tip.0) * f0, endY = tip.1 + (bobY - tip.1) * f0 - sin(f0 * .pi) * 16
            for k in 0...40 {
                let f = Double(k) / 40
                let x = tip.0 + (endX - tip.0) * f, y = tip.1 + (endY - tip.1) * f + sin(f * .pi) * 6 * f0
                if k % 2 == 0 { b.set(Int(x), Int(y), 0xE8E8E8) }
            }
            b.fill(Int(endX) - 1, Int(endY) - 2, 3, 2, 0xD8341F); b.fill(Int(endX) - 1, Int(endY), 3, 1, 0xF0F0F0)
            if bite { for i in 0..<5 { b.set(Int(bobX) - 4 + i * 2, g - 1 - Int(abs(sin(t * 8 + Double(i))) * 3), 0xC8E4FF) } }
        }
        if (6.1...7.3).contains(p) {
            let f = (p - 6.1) / 1.2
            let x = bobX + (Double(px - 4) - bobX) * f, y = Double(g) - sin(f * .pi) * 30 - 10 * f
            b.blit(Self.pufferfish, x: Int(x), bottom: Int(y))
        }
        if (7.3...9).contains(p) { b.blit(Self.pufferfish, x: px + 10, bottom: g - 1) }
    }
}

// MARK: - 1.10 Frostburn Update：冰刺之原的北极熊

/// 1.10 霜火更新加入了北极熊、尸壳、流浪者、岩浆块和化石。冰刺之原：高高的浮冰刺，北极熊妈妈带着小熊；
/// 玩家靠近一点，熊妈妈就站起来吼一声护着小熊，小熊在旁边打滚
struct Frostburn: DotScene {
    let id = "1.10"
    let background: UInt32 = 0x8FB3FF

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 轮廓上的点压暗一点（白色的生物站在雪地上也看得清）
    static func edged(_ s: Sprite) -> Sprite {
        Sprite(width: s.width, height: s.height) { x, y in
            let v = s.px[y * s.width + x]
            guard v != 0 else { return nil }
            func empty(_ x: Int, _ y: Int) -> Bool { x < 0 || y < 0 || x >= s.width || y >= s.height || s.px[y * s.width + x] == 0 }
            let edge = empty(x - 1, y) || empty(x + 1, y) || empty(x, y - 1) || empty(x, y + 1)
            return edge ? shade(v & 0xFFFFFF, 0.8) : v & 0xFFFFFF
        }
    }

    /// 北极熊（朝右，30×22，约 1.4 格高）：白色的大身子、小耳朵、黑鼻子；standing 时用后腿站起来（16×36）
    static func bear(standing: Bool, mouth: Bool, step: Int, scale: Int = 1) -> Sprite {
        let fur: [UInt32] = [0xF4F4F0, 0xE8E8E2, 0xFFFFFF, 0xDCDCD4]
        if standing {
            return Sprite(width: 18, height: 38) { x, y in
                if (5...12).contains(x) && (1...8).contains(y) {
                    if y == 1 && (x == 6 || x == 11) { return 0xDCDCD4 }
                    if y == 4 && x == 10 { return 0x1E1E1D }
                    return pick(fur, x, y, 135)
                }
                if (13...16).contains(x) && (4...8).contains(y) {
                    if x == 16 && y == 4 { return 0x1E1E1D }
                    if mouth && y == 8 { return 0x8A3A3A }
                    return y >= 7 ? 0xE0E0DA : pick(fur, x, y, 134)
                }
                if (3...13).contains(x) && (9...28).contains(y) { return x >= 11 ? 0xE0E0D8 : pick(fur, x / 2, y / 2, 136) }
                if (13...17).contains(x) && (10...14).contains(y) { return y == 14 ? 0x3A3A3A : pick(fur, x, y, 137) }   // 举起的前爪
                if ((4...7).contains(x) || (10...13).contains(x)) && (29...37).contains(y) { return y == 37 ? 0x3A3A3A : pick(fur, x, y, 138) }
                return nil
            }
        }
        return Sprite(width: 30, height: 22) { x, y in
            if (2...21).contains(x) && (3...14).contains(y) { return y == 14 ? 0xDCDCD4 : pick(fur, x / 2, y / 2, 139) }
            if (20...28).contains(x) && (5...12).contains(y) {
                if y == 7 && x == 25 { return 0x1E1E1D }
                if x >= 27 && (9...10).contains(y) { return x == 28 && y == 9 ? 0x1E1E1D : 0xE0E0DA }
                return pick(fur, x, y, 140)
            }
            if (x == 21 || x == 24) && y == 4 { return 0xDCDCD4 }
            for (i, lx) in [3, 8, 15, 19].enumerated() where (lx...(lx + 3)).contains(x) {
                let up = i % 2 == step ? 1 : 0
                if (15...(21 - up)).contains(y) { return y == 21 - up ? 0x3A3A3A : pick(fur, x, y, 141) }
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x6A8ED8, 0x8FB3FF, 0xB4CCF8, 0xD8E4FA])
        // 浮冰刺：细高的柱子，有的顶上收尖
        for i in 0..<12 {
            let x = Int(noise(i, 0, 142) * Double(b.cols)), h = 20 + Int(noise(i, 1, 142) * Double(g) * 0.7)
            let w = 6 + Int(noise(i, 2, 142) * 6)
            let far = i % 2 == 1
            for y in (g - h)..<g {
                let taper = max(1, min(w, (y - (g - h)) / 3 + 1))
                for dx in 0..<taper {
                    var c: UInt32 = dx == 0 ? 0xD8E8FC : (dx == taper - 1 ? 0x6A90D8 : pick([0x9CC0F0, 0x8AB0EA, 0xA8C8F4], x + dx, y, 143))
                    if far { c = dither(x + dx, y, 0.5) ? 0xB4CCF8 : c }
                    b.set(x + dx + (w - taper) / 2, y, c)
                }
            }
        }
        // 雪地
        Paint.strata(&b, from: g, top: [0xF4F8FF, 0xE6EEFA, 0xFFFFFF], topRows: 6,
                     mid: [0x8A5A33, 0x6F4627], midRows: 26, deep: [0x7F7F7F, 0x6E6E6E], seed: 144)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.falling(&b, t: t, count: 40, colors: [0xFFFFFF, 0xE6EEFA], top: 0, bottom: g, speed: 0.04, seed: 145)
        // 时间线（10 秒一轮）：玩家往前凑 → 熊妈妈站起来吼 → 玩家退回去 → 熊妈妈趴下
        let p = t.truncatingRemainder(dividingBy: 10)
        let standing = (3.4...6.4).contains(p)
        let roar = standing && sin(t * 9) > 0
        let mx = Int(Double(b.cols) * 0.3)
        if standing { b.blit(Self.edged(Self.bear(standing: true, mouth: roar, step: 0)), x: mx + 8, bottom: g - 1) }
        else { b.blit(Self.edged(Self.bear(standing: false, mouth: false, step: sin(t * 0.8) > 0.9 ? Int(t * 4) % 2 : 2)), x: mx, bottom: g - 1) }
        if roar { for i in 0..<4 { b.set(mx + 28 + i * 2, g - 30 + Int(sin(t * 20 + Double(i)) * 2), 0xFFFFFF) } }
        // 小熊（一半大）：在妈妈身后打滚、蹦跶
        let cub = Self.edged(Self.bear(standing: false, mouth: false, step: Int(t * 5) % 2))
        let cx = Int(Double(b.cols) * 0.12) + Int(sin(t * 0.9) * 10)
        b.blit(cub, x: cx, bottom: g - 1 - (sin(t * 4) > 0.7 ? 2 : 0), w: 15, h: 11, flip: sin(t * 0.9 + 1.6) < 0)
        // 玩家
        var pose = Player.idle(t, props: PlayerProps(), phase: 5)
        let near = ramp(p, 1.5, 3.2) * (1 - ramp(p, 5.6, 7.2))
        pose.dx = -Int(18 * near)
        // 往前凑和退回去的时候迈步；退的时候是倒着走
        if (1.5...3.2).contains(p) || (5.6...7.2).contains(p) { pose.walk = t * 9; pose.lookBack = false }
        if standing { pose.lookBack = false; pose.headDip = 0 }
        Player.draw(&b, look: cast.player, pose: pose, x: Int(Double(b.cols) * 0.76), feet: g - 1, t: t)
    }
}

// MARK: - 1.11 Exploration Update：林地府邸与不死图腾

/// 1.11 探险更新加入了林地府邸、唤魔者、恼鬼、卫道士、羊驼、不死图腾、潜影盒和探险家地图。
/// 府邸前：唤魔者举手施法，一串尖牙沿着地面咬向玩家，两只恼鬼拿着铁剑绕着飞；玩家被咬中，
/// 手里的不死图腾碎开，金绿色的粒子炸开，图腾在面前转着升起来
struct Exploration: DotScene {
    let id = "1.11"
    let background: UInt32 = 0x3A4A6A

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 唤魔者：和村民一样的大鼻子、灰色的脸，黑色的长袍中间一道金边，双手抱在胸前
    static let evoker = PlayerLook(
        headFront: Sprite(["SSSSSSSS", "SSSSSSSS", "SSSSSSSS", "BBBBBBBB", "SkGSSGkS", "SSSnnSSS", "SSSnnSSS", "SSMnnMSS", "sSSnnSSs", "sSSSSSSs"],
                          ["S": 0x9A9C9E, "s": 0x868A8E, "B": 0x3A3A3C, "k": 0x1E1E1D, "G": 0x8A8A8A, "n": 0x7E8084, "M": 0x5A5C60]),
        headSide: Sprite(["SSSs", "SSSs", "SSSs", "BSSs", "SSSs", "SSss", "SSSs", "SSSs", "SSSs", "ssss"], ["S": 0x84868A, "s": 0x707276, "B": 0x343436]),
        bodyFront: Sprite(Array(repeating: "RRRggRRR", count: 11) + ["rrrggrrr"], ["R": 0x1E1E22, "r": 0x141418, "g": 0xC8A030]),
        bodySide: Sprite(Array(repeating: "Rr", count: 12), ["R": 0x18181C, "r": 0x101014]),
        nearArm: Sprite(Array(repeating: "RRRRr", count: 12), ["R": 0x1E1E22, "r": 0x141418]),
        farArm: Sprite(Array(repeating: "RRr", count: 12), ["R": 0x18181C, "r": 0x101014]),
        legs: Sprite(Array(repeating: "RRRgRRRRrr", count: 10) + ["GGGGGGGGgg", "GGGGGGGGgg"],
                     ["R": 0x1E1E22, "r": 0x141418, "g": 0xC8A030, "G": 0x3A3A3C]),
        nose: Sprite(["nN", "nN"], ["n": 0x8A8C90, "N": 0x6E7074]),
        crossedArms: Sprite(["AAAAAAAAAA..", "AhhAAAAAhhAA", "AAAAAAAAAAAa", ".aaaaaaaaaa."], ["A": 0x2A2A2E, "a": 0x1E1E22, "h": 0x9A9C9E]))

    static let totem = Sprite([
        "...oooo...", "..oYYYYo..", "..oGYYGo..", "..oYYYYo..", "oooYyyYooo", "oYYYYYYYYo", "ooooYYoooo", "...oYYo...",
        "...oyyo...", "...oYYo...", "....oo....",
    ], ["o": 0xA86A1E, "Y": 0xF0D060, "y": 0xD8A83A, "G": 0x3AD860])

    /// 尖牙（10×12）：从地里冒出来的一对灰色的夹子，闭合时咬住；h 为露出地面的高度
    static func fangs(_ b: inout DotBuffer, x: Int, ground g: Int, h: Int, bite: Bool) {
        guard h > 0 else { return }
        for dy in 0..<h {
            let y = g - 1 - dy
            let gap = bite ? 0 : max(0, 3 - dy / 3)
            for dx in 0..<4 { b.set(x + dx - gap, y, dx == 0 ? 0x5A5A50 : 0x8A8A7A); b.set(x + 6 + dx + gap, y, dx == 3 ? 0x5A5A50 : 0x8A8A7A) }
            if dy == h - 1 { for dx in stride(from: 0, to: 10, by: 2) { b.set(x + dx + (dx < 5 ? -gap : gap), y - 1, 0xF0F0E0) } }
        }
    }

    static let vex = Sprite([
        "....bbb", "...bkbk", "w..bbbb", "ww.bBb.", ".wwbb..", "..ww...", "s..b...", ".s.....",
    ], ["b": 0xA8B4C8, "B": 0x8A98B0, "k": 0x3A4A6A, "w": 0xD8E4F4, "s": 0xD8D8D8])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x2A3050, 0x3A4A6A, 0x5A6A88, 0x8A94A8])
        // 黑森林的大蘑菇和树冠剪影
        for x in 0..<b.cols {
            let h = Int(Double(g) * 0.3 + noise(x / 8, 0, 146) * 12)
            for y in (g - h)..<g { b.set(x, y, dither(x, y, 0.5) ? 0x1E3018 : 0x223A1C) }
        }
        // 林地府邸：深色橡木的墙，圆石的地基，白桦的窗框，深色的屋顶
        let x0 = Int(Double(b.cols) * 0.02), w = 96, top = g - 66
        for y in top..<g { for x in x0..<(x0 + w) {
            var c = pick([0x4A3220, 0x3E2A1A, 0x543A24], (x - x0) / 4, (y - top) / 4, 147)
            if (x - x0) % 16 == 0 { c = 0x2E1E12 }
            if y > g - 10 { c = pick([0x7A7A7A, 0x6A6A6A, 0x8A8A8A], x / 3, y / 3, 148) }
            b.set(x, y, c)
        } }
        for k in 0..<5 { for y in top - 10 + k * 2..<(top - 8 + k * 2) { b.fill(x0 - 4 + k * 2, y, w + 8 - k * 4, 1, 0x3A2416) } }
        b.fill(x0 - 4, top - 2, w + 8, 2, 0x2A1A10)
        for row in 0..<2 { for col in 0..<4 {
            let wx = x0 + 8 + col * 22, wy = top + 8 + row * 24
            b.fill(wx, wy, 12, 14, 0xD8D0B8); b.fill(wx + 1, wy + 1, 10, 12, 0x6A88A8); b.fill(wx + 5, wy + 1, 1, 12, 0xD8D0B8)
            if (row + col) % 3 == 0 { b.fill(wx + 1, wy + 1, 4, 12, 0xF0C060) }
        } }
        b.fill(x0 + 40, g - 22, 16, 22, 0x2A1A10)
        Paint.strata(&b, from: g, top: [0x4F8F35, 0x3E7A2C, 0x5DA03F], topRows: 4,
                     mid: [0x6F4627, 0x8A5A33], midRows: 30, deep: [0x6E6E6E, 0x7F7F7F], seed: 149)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        let px = Int(Double(b.cols) * 0.78), ex = Int(Double(b.cols) * 0.46)
        // 时间线（10 秒一轮）：施法 → 尖牙一路咬过去 → 玩家被咬中、图腾生效 → 恢复
        let p = t.truncatingRemainder(dividingBy: 10)
        let casting = (0.8...2.6).contains(p)
        Player.draw(&b, look: Self.evoker, pose: PlayerPose(), x: ex, feet: g - 1, t: t, facingRight: true)
        if casting {
            for i in 0..<8 {
                let f = ((p - 0.8) * 1.5 + Double(i) / 8).truncatingRemainder(dividingBy: 1)
                b.set(ex + 2 + Int(sin(Double(i) * 2 + t * 3) * 7), g - 34 - Int(f * 14), i % 2 == 0 ? 0xB0B0C8 : 0x8A8AA8)
            }
        }
        // 尖牙：从唤魔者脚下一路排到玩家
        let from = ex + 16, to = px - 6
        for k in 0..<7 {
            let at = 2.0 + Double(k) * 0.18
            let q = p - at
            guard q > 0 && q < 0.9 else { continue }
            let h = q < 0.25 ? Int(q / 0.25 * 10) : (q < 0.6 ? 10 : Int((0.9 - q) / 0.3 * 10))
            Self.fangs(&b, x: from + (to - from) * k / 6, ground: g, h: h, bite: q > 0.3)
        }
        // 恼鬼：拿着铁剑绕着飞
        for i in 0..<2 {
            let a = t * 1.4 + Double(i) * .pi
            let vx = ex + 14 + Int(cos(a) * 30), vy = g - 46 + Int(sin(a * 1.3) * 10)
            b.blit(Self.vex, x: vx, bottom: vy, flip: sin(a) > 0)
        }
        // 玩家：被咬中 → 图腾生效
        let hit = (3.1...5.5).contains(p)
        var pose = Player.idle(t, props: PlayerProps(), phase: 3)
        if hit { pose.hurt = max(0, 1 - (p - 3.1) / 0.6); pose.lift = p < 3.4 ? 2 : 0 }
        let props = PlayerProps(held: p < 3.1 || p > 6.5 ? HeldItem(sprite: Self.totem, swings: false) : nil)
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
        if hit {
            let f = (p - 3.1) / 2.4
            // 金绿色的粒子炸开
            for i in 0..<36 {
                let a = Double(i) / 36 * 2 * .pi + noise(i, 0, 150)
                let r = 4 + f * 30 * (0.5 + noise(i, 1, 150))
                let x = px + 4 + Int(cos(a) * r), y = g - 18 + Int(sin(a) * r * 0.8 + f * f * 10)
                if sin(t * 20 + Double(i)) > f * 1.6 - 0.8 { b.set(x, y, [0xF0D060, 0x3AD860, 0xF8F0A0, 0x8AE85A][i % 4]) }
            }
            // 图腾在面前升起，放大一倍，左右翻转像在转
            let s = f < 0.7 ? 2 : 1
            let spin = Int(t * 6) % 2 == 0
            if f < 0.85 { b.blit(Self.totem, x: px - 6 - (s - 1) * 5, bottom: g - 26 - Int(f * 20), w: Self.totem.width * s, h: Self.totem.height * s, flip: spin) }
        }
    }
}
