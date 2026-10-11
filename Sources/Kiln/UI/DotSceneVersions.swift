import SwiftUI

// MARK: - 各版本的横版场景
//
// 共同的模板：这个版本新增的地形做背景，新生物在左边，登录的玩家在右边（斜 45°，用他自己的皮肤），
// 拿着或穿着这个版本新增的东西。每个场景在站位、道具、动作上各有变化，但读起来是同一套。
// 除了登录的玩家，场景里其他的人一律用作者 NelsonPence 的皮肤（cast.author）。
//
// 画新东西的流程（必须照做）：
// 1. 先查原版长什么样：在 minecraft.wiki 找到生物 / 物品 / 方块的渲染图和贴图，对着参考画，不凭印象。
// 2. 按游戏里的真实尺寸：一个方块 16 个点，玩家 32 个点高（猪灵和玩家一样高，嗅探兽约 28×64，旋风人约 28 高）。
// 3. 轮廓、标志性特征和颜色都从参考图里取，画完和参考图并排对比一遍再提交。

enum Paint {
    /// 天空：从上到下按有序抖动分档
    static func sky(_ b: inout DotBuffer, until ground: Int, _ tones: [UInt32]) {
        for y in 0..<ground { for x in 0..<b.cols { b.set(x, y, ditherRamp(tones, Double(y) / Double(max(1, ground)), x, y)) } }
    }

    /// 方块云：从右往左飘
    static func clouds(_ b: inout DotBuffer, t: Double, maxY: Int, count: Int = 5, color: UInt32 = 0xF7F9FF, shadow: UInt32 = 0xD5E1FB, seed: Int = 41) {
        for i in 0..<count {
            let w = 22 + Int(noise(i, 0, seed) * 30)
            let y = 4 + Int(noise(i, 1, seed) * Double(max(1, maxY - 8)))
            let span = Double(b.cols + w)
            let x = Int(span - (t * (1.6 + noise(i, 2, seed) * 1.8) + noise(i, 3, seed) * span).truncatingRemainder(dividingBy: span)) - w
            b.fill(x, y, w, 4, color)
            b.fill(x + 5, y - 3, max(4, w - 12), 3, color)
            for dx in stride(from: 0, to: w, by: 2) { b.set(x + dx, y + 4, shadow) }
        }
    }

    /// 地面以下的分层：表层、中层、深层，越深越暗（有序抖动压暗）
    static func strata(_ b: inout DotBuffer, from ground: Int, top: [UInt32], topRows: Int, mid: [UInt32], midRows: Int, deep: [UInt32], seed: Int = 0) {
        for y in ground..<b.rows {
            let d = y - ground
            for x in 0..<b.cols {
                let c = d < topRows ? pick(top, x, y, seed) : (d < topRows + midRows ? pick(mid, x, y, seed + 1) : pick(deep, x, y, seed + 2))
                let dark = Double(d) / Double(max(1, b.rows - ground)) * 0.8
                b.set(x, y, dither(x, y, dark) ? shade(c, 0.55) : c)
            }
        }
    }

    /// 飘落的东西（花瓣、树叶、雪）：慢慢往下飘，左右摆动
    static func falling(_ b: inout DotBuffer, t: Double, count: Int, colors: [UInt32], top: Int, bottom: Int, speed: Double = 0.06, seed: Int = 0) {
        for i in 0..<count {
            let sp = speed * (0.6 + noise(i, 1, seed) * 0.8)
            let p = (t * sp + noise(i, 2, seed)).truncatingRemainder(dividingBy: 1)
            let x = Int(noise(i, 3, seed) * Double(b.cols)) + Int(sin(t * 1.3 + Double(i)) * 4) - Int(p * 14)
            let y = top + Int(p * Double(bottom - top))
            let c = colors[i % colors.count]
            b.set(x, y, c)
            if i % 3 == 0 { b.set(x + 1, y, shade(c, 0.85)) }
        }
    }

    /// 往上飘的东西（火星、孢子）
    static func rising(_ b: inout DotBuffer, t: Double, count: Int, colors: [UInt32], top: Int, bottom: Int, speed: Double = 0.05, seed: Int = 0) {
        for i in 0..<count {
            let sp = speed * (0.6 + noise(i, 1, seed) * 0.8)
            let p = (t * sp + noise(i, 2, seed)).truncatingRemainder(dividingBy: 1)
            let x = Int(noise(i, 3, seed) * Double(b.cols)) + Int(sin(t * 0.9 + Double(i)) * 3)
            let y = bottom - Int(p * Double(bottom - top))
            if sin(t * 2.4 + Double(i) * 1.3) > -0.4 { b.set(x, y, colors[i % colors.count]) }
        }
    }

    /// 一块 16×16 的方块：平涂加一圈明暗边，像游戏里的方块正面
    static func block(_ b: inout DotBuffer, x: Int, y: Int, _ c: UInt32, size: Int = 16, seed: Int = 0) {
        for dy in 0..<size {
            for dx in 0..<size {
                var v = c
                if dy == 0 || dx == 0 { v = shade(c, 1.12) } else if dy == size - 1 || dx == size - 1 { v = shade(c, 0.8) }
                else if noise(x + dx, y + dy, seed) < 0.08 { v = shade(c, 0.94) }
                b.set(x + dx, y + dy, v)
            }
        }
    }

    /// 火焰：两三层颜色，随时间跳动
    static func flame(_ b: inout DotBuffer, x: Int, bottom: Int, width: Int, height: Int, t: Double, palette: [UInt32] = [0xFF5A1F, 0xFF9A2E, 0xFFD54A, 0xFFF6B0]) {
        for dx in 0..<width {
            let center = 1 - abs(Double(dx) - Double(width - 1) / 2) / (Double(width) / 2)
            let h = Int(Double(height) * (0.45 + 0.55 * center) * (0.75 + 0.25 * sin(t * 9 + Double(dx) * 1.7)))
            for dy in 0..<max(1, h) {
                let k = Double(dy) / Double(max(1, h))
                b.set(x + dx, bottom - dy, ditherRamp(palette.reversed(), 1 - k * 0.9 - (1 - center) * 0.3, x + dx, bottom - dy))
            }
        }
    }
}

// MARK: - 1.8 Bountiful Update：斗兽场里的 PVP

/// 1.8 以 PVP 出名：玩家（右）和作者（左）穿着钻石甲、拿着钻石剑在斗兽场里对打，跳劈、格挡连击、击退、暴击粒子
struct PvpArena: DotScene {
    let id = "1.8"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6])
        // 斗兽场的看台：两层拱廊，石砖墙
        let wallTop = Int(Double(b.rows) * 0.16)
        let brick: [UInt32] = [0x7D7D7D, 0x888888, 0x727272, 0x8F8F8F]
        for y in wallTop..<g {
            for x in 0..<b.cols {
                let row = (y - wallTop) / 4
                let mortar = (y - wallTop) % 4 == 3 || (x + (row % 2) * 4) % 8 == 7
                b.set(x, y, mortar ? 0x5E5E5E : pick(brick, x / 8, row, 3))
            }
        }
        // 墙顶的垛口
        for x in stride(from: 0, to: b.cols, by: 12) { b.fill(x, wallTop - 4, 7, 4, 0x8A8A8A) }
        // 拱门洞口：上层小、下层大，里面是暗处（观众在动态层）
        func arches(top: Int, bottom: Int, width: Int, gap: Int) {
            var x = gap / 2
            while x + width < b.cols {
                let r = Double(width) / 2, cx = Double(x) + r
                for y in top..<bottom {
                    for dx in 0..<width {
                        let px = Double(x + dx) + 0.5
                        let inside = Double(y) >= Double(top) + r || pow(px - cx, 2) + pow(Double(top) + r - Double(y), 2) <= r * r
                        if inside { b.set(x + dx, y, ditherRamp([0x1C1A20, 0x2A2730, 0x36323C], Double(y - top) / Double(bottom - top), x + dx, y)) }
                    }
                }
                x += width + gap
            }
        }
        let mid = wallTop + (g - wallTop) * 45 / 100
        arches(top: wallTop + 4, bottom: mid - 3, width: 12, gap: 10)
        for x in 0..<b.cols { b.set(x, mid - 2, 0x5A5A5A); b.set(x, mid - 1, 0x9A9A9A) }
        arches(top: mid + 3, bottom: g - 7, width: 16, gap: 12)
        // 场地边上的矮墙
        for y in (g - 6)..<g { for x in 0..<b.cols { b.set(x, y, y == g - 6 ? 0xA8A8A8 : pick(brick, x / 6, y, 5)) } }
        // 旗帜（1.8 新增）：挂在墙顶，红蓝相间，带图案
        for (i, x) in stride(from: 8, to: b.cols - 8, by: 46).enumerated() {
            let base: UInt32 = i % 2 == 0 ? 0xB02E26 : 0x3C44AA
            b.fill(x - 1, wallTop - 1, 9, 1, 0x6B5133)
            for y in 0..<16 {
                for dx in 0..<7 {
                    var c = base
                    if i % 2 == 0 && (dx == 3 || y == 6) { c = 0xF0F0F0 }
                    if i % 2 == 1 && abs(dx - 3) == abs(y - 7) % 4 { c = 0xF9D84A }
                    if y == 15 && dx % 2 == 1 { continue }
                    b.set(x + dx, wallTop + y, c)
                }
            }
        }
        // 沙地
        Paint.strata(&b, from: g, top: [0xDBCFA3, 0xE3D7AE, 0xCFC294, 0xD6C99B], topRows: 16,
                     mid: [0xD8C78E, 0xC9B67A, 0xD1BF85], midRows: 16, deep: [0xB5A26A, 0xA69360], seed: 7)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        let wallTop = Int(Double(b.rows) * 0.16), mid = wallTop + (g - wallTop) * 45 / 100
        Paint.clouds(&b, t: t, maxY: wallTop - 4, count: 3)
        // 看台上的观众：拱门里一排脑袋，此起彼伏
        let skins: [UInt32] = [0xB78A6B, 0xE1B48E, 0x8E6249, 0xF2CBA4]
        let hair: [UInt32] = [0x3B2717, 0xE3792B, 0x1E1E1D, 0xD9B648]
        for (row, y0) in [(0, mid - 7), (1, g - 12)] {
            for i in stride(from: 0, to: b.cols, by: 5) where noise(i, row, 77) > 0.35 {
                let hop = sin(t * (3 + noise(i, row, 78) * 4) + Double(i)) > 0.6 ? 1 : 0
                let c = pick(skins, i, row, 79), h = pick(hair, i, row, 80)
                b.fill(i, y0 - hop, 3, 2, c)
                b.fill(i, y0 - 1 - hop, 3, 1, h)
            }
        }
        // 墙上的火把
        for x in stride(from: 30, to: b.cols, by: 46) {
            b.fill(x, mid + 8, 1, 5, 0x6B5133)
            Paint.flame(&b, x: x - 1, bottom: mid + 7, width: 3, height: 4, t: t + Double(x))
        }

        // 战斗时间线（5.2 秒一轮）
        let cycle = 5.2
        let p = t.truncatingRemainder(dividingBy: cycle)
        func swing(_ q: Double) -> Double { q < 0.35 ? 0.3 + 1.6 * (q / 0.35) : 1.9 - 1.6 * ((q - 0.35) / 0.65) }
        func blockHit(_ phase: Double) -> Double { 0.45 + abs(sin(t * 9 + phase)) * 0.9 }

        var me = PlayerPose(), foe = PlayerPose()
        me.dx = Int((sin(t * 1.9) * 2).rounded())
        foe.dx = Int((sin(t * 1.9 + .pi) * 2).rounded())
        me.armAngle = 0.5; foe.armAngle = 0.5
        // 玩家跳劈
        if (0.4...1.15).contains(p) {
            let k = (p - 0.4) / 0.75
            me.lift = Int((4 * k * (1 - k) * 10).rounded())
            if (0.75...1.05).contains(p) { me.armAngle = swing((p - 0.75) / 0.3); me.itemTilt = 0 }
        }
        // 作者被打中：泛红、被击退
        if (0.95...2.3).contains(p) {
            foe.hurt = max(0, 1 - (p - 0.95) / 0.3)
            foe.dx -= Int((6 * ramp(p, 0.95, 1.3) * (1 - ramp(p, 1.6, 2.3))).rounded())
            if p < 1.3 { foe.lift = Int((sin((p - 0.95) / 0.35 * .pi) * 3).rounded()) }
        }
        // 作者反击
        if (2.8...3.5).contains(p) {
            let k = (p - 2.8) / 0.7
            foe.lift = Int((4 * k * (1 - k) * 8).rounded())
            if (3.05...3.35).contains(p) { foe.armAngle = swing((p - 3.05) / 0.3); foe.itemTilt = 0 }
        }
        if (3.25...4.5).contains(p) {
            me.hurt = max(0, 1 - (p - 3.25) / 0.3)
            me.dx += Int((6 * ramp(p, 3.25, 3.6) * (1 - ramp(p, 3.9, 4.5))).rounded())
            if p < 3.6 { me.lift = Int((sin((p - 3.25) / 0.35 * .pi) * 3).rounded()) }
        }
        // 两边都在格挡连击（1.8 的标志）
        if (1.6...2.6).contains(p) || (3.9...4.9).contains(p) { me.armAngle = blockHit(0); foe.armAngle = blockHit(1.3) }
        // 不在挥砍时，剑尖水平指向对方（略微上扬）
        let meSwinging = (0.75...1.05).contains(p), foeSwinging = (3.05...3.35).contains(p)
        if !meSwinging { me.itemTilt = -0.45 - me.armAngle + .pi / 2 - 1.35 }
        if !foeSwinging { foe.itemTilt = -0.45 - foe.armAngle + .pi / 2 - 1.35 }

        let props = PlayerProps(held: .diamondSword, armor: .full(.diamond))
        let meX = Int(Double(b.cols) * 0.585), foeX = Int(Double(b.cols) * 0.4)
        Player.draw(&b, look: cast.author, props: props, pose: foe, x: foeX, feet: g - 1, t: t + 0.7, facingRight: true)
        Player.draw(&b, look: cast.player, props: props, pose: me, x: meX, feet: g - 1, t: t)

        // 暴击粒子：被打中时从身上炸开的暗蓝色小星
        func crits(at x: Int, _ y: Int, since q: Double) {
            guard q >= 0, q < 0.6 else { return }
            for i in 0..<9 {
                let a = Double(i) / 9 * 2 * .pi + 0.4
                let r = 3 + q * 26
                let px = x + Int(cos(a) * r), py = y + Int(sin(a) * r * 0.7) - Int(q * 6)
                let c: UInt32 = i % 2 == 0 ? 0x7C8FD0 : 0x4E5A8A
                b.set(px, py, c); b.set(px + 1, py, c); b.set(px - 1, py, c); b.set(px, py + 1, c); b.set(px, py - 1, c)
            }
        }
        crits(at: foeX + 8 + foe.dx, g - 22, since: p - 0.95)
        crits(at: meX + 2 + me.dx, g - 22, since: p - 3.25)
    }
}

// MARK: - 1.12 World of Color：彩色混凝土与鹦鹉

/// 1.12 加入了 16 色混凝土、带釉陶瓦和鹦鹉。鹦鹉在左边飞，一只停在玩家肩膀上（1.12 的新特性）；玩家站在一级彩色台阶上
struct WorldOfColor: DotScene {
    let id = "1.12"
    let background: UInt32 = 0x86AAF2

    static let concrete: [UInt32] = [0xCF3A2A, 0xE06A12, 0xF1AF15, 0x5E9A1E, 0x157788, 0x2C2E8F, 0x64209C, 0xA9309F, 0xD5658E, 0x24A0C4, 0xCFD5D6]

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 鹦鹉（侧面朝右，约 14 点高）：红白冠羽、黑色脸斑、深色喙、黄蓝翅膀、长尾；两帧翅膀
    static func parrot(_ body: UInt32, wing: UInt32, wing2: UInt32, flap: Bool) -> Sprite {
        let rows = flap ? [
            "...wR.......", "....Rw......", "..RRRRR.....", ".RRRRwK.....", ".RRRRKKB....", "..RRRRKb.Y..",
            "..RRRRR.YYZ.", "...RRRYYZZ..", "...RRRR.....", "....RRR.....", "....RZZ.....", "....g.g.....",
            ".....RZ.....", "......Z.....",
        ] : [
            "...wR.......", "....Rw......", "..RRRRR.....", ".RRRRwK.....", ".RRRRKKB....", "..RRRRKb....",
            "..RRRYYR....", "...RYYZZ....", "...RYZZR....", "....RZZR....", "....RRR.....", "....g.g.....",
            ".....RZ.....", "......Z.....",
        ]
        return Sprite(rows.map { String($0.reversed()) },
                      ["R": body, "w": 0xF4F4F4, "K": 0x1E1E1D, "B": 0x3A3D42, "b": 0x5A5E66, "Y": wing, "Z": wing2, "g": 0x6E6A66])
    }
    static let shoulderParrot = Sprite(["..wR..", "..RRw.", "RRRRK.", "RRRKKB", "RYYRb.", ".RZZR.", "..RR..", "..g.g."].map { String($0.reversed()) },
                                       ["R": 0xE53B2C, "w": 0xF4F4F4, "K": 0x1E1E1D, "B": 0x3A3D42, "b": 0x5A5E66, "Y": 0xF1C232, "Z": 0x2E5BD9, "g": 0x6E6A66])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6, 0xC2D6FA])
        // 远处的彩色方块建筑：一级级的台阶和塔
        var x = 2
        var i = 0
        while x < b.cols {
            let h = 1 + Int(noise(i, 0, 3) * 4)
            let w = 1 + Int(noise(i, 1, 3) * 2)
            for bx in 0..<w {
                for by in 0..<h {
                    let c = Self.concrete[(i * 3 + by + bx) % Self.concrete.count]
                    Paint.block(&b, x: x + bx * 16, y: g - 16 * (by + 1), shade(c, 0.78 + 0.05 * Double(by)), seed: i)
                }
            }
            x += w * 16 + 6 + Int(noise(i, 2, 3) * 18)
            i += 1
        }
        // 带釉陶瓦：图案方块，点缀在建筑上
        for k in 0..<4 {
            let bx = Int(noise(k, 7, 3) * Double(b.cols - 16)), by = g - 16 * (1 + k % 2)
            for dy in 0..<16 { for dx in 0..<16 {
                let d = abs(dx - 8) + abs(dy - 8)
                b.set(bx + dx, by + dy, d % 6 < 2 ? 0xF7F2E8 : (d % 6 < 4 ? Self.concrete[k * 2 % Self.concrete.count] : 0x2C2E8F))
            } }
        }
        // 草地
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35], topRows: 3, mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30,
                     deep: [0x7F7F7F, 0x6E6E6E, 0x8C8C8C], seed: 11)
        // 玩家脚下的一级彩色台阶
        let sx = Int(Double(b.cols) * 0.72)
        for k in 0..<2 { Paint.block(&b, x: sx + k * 16, y: g - 16, Self.concrete[[8, 9][k]], seed: 70 + k) }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 2, count: 4)
        // 三只鹦鹉在左边绕圈飞
        let colors: [(UInt32, UInt32, UInt32)] = [(0xE53B2C, 0xF1C232, 0x2E5BD9), (0x3DB24A, 0xF1C232, 0x2E5BD9), (0x2E9BD9, 0xF1C232, 0x1E3E9A)]
        for (i, c) in colors.enumerated() {
            let a = t * (0.7 + Double(i) * 0.15) + Double(i) * 2.1
            let cx = Double(b.cols) * (0.16 + Double(i) * 0.09) + cos(a) * 14
            let cy = Double(g) * (0.38 + Double(i) * 0.1) + sin(a * 1.3) * 7
            let flap = sin(t * 14 + Double(i)) > 0
            b.blit(Self.parrot(c.0, wing: c.1, wing2: c.2, flap: flap), x: Int(cx), bottom: Int(cy), flip: cos(a) > 0)
        }
        let props = PlayerProps(shoulder: Self.shoulderParrot)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 3),
                    x: Int(Double(b.cols) * 0.72) + 8, feet: g - 17, t: t)
    }
}

// MARK: - 1.13 Update Aquatic：海滩、珊瑚礁、海龟与海豚

/// 1.13 重做了海洋：珊瑚、海带、海龟、海豚、三叉戟。左边海水里有珊瑚礁和摇摆的海带，海龟在沙滩上慢慢爬，
/// 海豚偶尔跃出水面；玩家站在右边的沙滩上，拿着三叉戟，戴着海龟壳（时不时摘下来再戴回去）
struct UpdateAquatic: DotScene {
    let id = "1.13"
    let background: UInt32 = 0x86AAF2

    private func layout(_ b: DotBuffer) -> (ground: Int, water: Int, shore: Int) {
        let g = Int(Double(b.rows) * 0.62)
        return (g, g - 3, Int(Double(b.cols) * 0.5))
    }

    /// 海底的高度：越往左越深
    private func seabed(_ x: Int, _ b: DotBuffer) -> Int {
        let (g, _, shore) = layout(b)
        if x >= shore { return g }
        let k = Double(shore - x) / Double(shore)
        return g + Int(min(1, k * 1.6) * 34) + Int(sin(Double(x) * 0.11) * 2)
    }

    /// 海龟（侧面朝右，约 22×8）：亮绿的壳上有深色的格纹，头和鳍是浅绿
    static let turtle = Sprite([
        ".......dSSSSd.........",
        "....dSSsSlSSsSSd......",
        "..dSslSSSSsSSlSSd..hh.",
        ".dSSSSsSSlSSSSSsSd.hHH",
        "dddddddddddddddddd.hkH",
        "..ff..........ffhhhHHh",
        ".ff.............ff....",
        "ff................ff..",
    ], ["d": 0x2A7A33, "S": 0x3BAA45, "s": 0x2E8A3A, "l": 0x55C25A, "h": 0x4FAE52, "H": 0x6CC46A, "k": 0x1E1E1D, "f": 0x4FAE52])

    static let dolphin = Sprite([
        "......FF........", ".....FFG........", "..GGGGGGGGGGG...", ".GGGGGGGGGGGGG.T",
        "GGkGGGGGGGGGGGTT", "BBWWWWWWWWGGG..T", "..WWWWWW.F......", ".........F......",
    ], ["G": 0x9FB3C8, "F": 0x8299B0, "W": 0xD5DEE8, "B": 0x7A8FA6, "k": 0x1E2A3A, "T": 0x8299B0])

    func paintStatic(_ b: inout DotBuffer) {
        let (g, water, _) = layout(b)
        Paint.sky(&b, until: water, [0x4F7FE0, 0x6F98EC, 0x8FB3FF, 0xB6CDFB])
        // 沙滩与海底
        for x in 0..<b.cols {
            let top = seabed(x, b)
            for y in top..<b.rows {
                let d = y - top
                let c = d < 10 ? pick([0xE8DCAE, 0xDBCFA3, 0xF0E4B8], x, y, 2) : pick([0xD8C78E, 0xC9B67A], x, y, 3)
                b.set(x, y, dither(x, y, Double(y - g) / Double(b.rows - g) * 0.7) ? shade(c, 0.6) : c)
            }
        }
        // 珊瑚：五种颜色的小丛
        let corals: [UInt32] = [0xD9579B, 0x3D5BD9, 0xD8341F, 0xF1C232, 0xA34ED9]
        for i in 0..<14 {
            let x = Int(noise(i, 0, 31) * Double(layout(b).shore - 12)) + 4
            let top = seabed(x, b)
            guard top > water + 6 else { continue }
            let c = corals[i % corals.count], h = 3 + Int(noise(i, 1, 31) * 6)
            for dy in 0..<h { for dx in -2...2 where noise(x + dx, dy, 32 + i) > 0.35 || dx == 0 {
                b.set(x + dx, top - 1 - dy, dy == h - 1 ? shade(c, 1.2) : c)
            } }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let (g, water, shore) = layout(b)
        Paint.clouds(&b, t: t, maxY: water / 2, count: 4)
        // 海带：从海底长出来，左右摇摆
        for i in 0..<9 {
            let x0 = Int(noise(i, 0, 41) * Double(shore - 20)) + 6
            let top = seabed(x0, b)
            let h = min(top - water - 3, 10 + Int(noise(i, 1, 41) * 18))
            guard h > 4 else { continue }
            for dy in 0..<h {
                let sway = Int((sin(t * 1.4 + Double(i) + Double(dy) * 0.18) * Double(dy) * 0.12).rounded())
                b.set(x0 + sway, top - 1 - dy, dy % 4 == 0 ? 0x6FAE3A : 0x4E8C2A)
            }
        }
        // 海水：在静态的海底与珊瑚上叠一层蓝，水面一排浪花在动
        for x in 0..<shore + 14 {
            let bottom = seabed(x, b)
            let surface = water + (sin(Double(x) * 0.4 + t * 2.2) > 0.6 ? -1 : 0)
            guard bottom > surface else { continue }
            for y in surface..<bottom {
                let w = sin(Double(x) * 0.18 + Double(y) * 0.4 - t * 1.5)
                if y == surface { b.set(x, y, 0xD9F1FF) }
                else if dither(x, y, 0.55 + w * 0.15) { b.set(x, y, y - surface < 6 ? 0x3F86E0 : 0x2E64C8) }
            }
        }
        // 海豚：每隔几秒从水里跃出一道弧
        let dp = t.truncatingRemainder(dividingBy: 7.5) / 1.6
        if dp < 1 {
            let x = Int(Double(b.cols) * (0.08 + dp * 0.22)), y = water - Int(4 * dp * (1 - dp) * 22)
            b.blit(Self.dolphin, x: x, bottom: y, flip: true)
        }
        // 气泡
        for i in 0..<8 {
            let p = (t * 0.25 + noise(i, 0, 51)).truncatingRemainder(dividingBy: 1)
            let x = Int(noise(i, 1, 51) * Double(shore - 10)) + 4
            let y = seabed(x, b) - Int(p * Double(seabed(x, b) - water))
            if y > water { b.set(x, y, 0xCFEFFF) }
        }
        // 海龟在沙滩上慢慢来回爬
        let tp = (t / 18).truncatingRemainder(dividingBy: 1)
        let dir = tp < 0.5
        let walk = Double(shore) + 4 + 30 * (dir ? tp * 2 : (1 - tp) * 2)
        b.blit(Self.turtle, x: Int(walk), bottom: g - 1 + (sin(t * 6) > 0.5 ? 0 : 0), flip: !dir)
        // 玩家：三叉戟，戴着海龟壳
        let props = PlayerProps(held: .trident, removableHelmet: .turtle)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 6), x: Int(Double(b.cols) * 0.8), feet: g - 1, t: t)
    }
}

// MARK: - 1.16 Nether Update：绯红森林里的猪灵

/// 1.16 重做了下界：绯红 / 诡异森林、猪灵、下界合金。背景是熔岩瀑布与暗红的下界岩，巨型绯红菌和垂泪藤，
/// 左边的猪灵拿着金剑，玩家穿下界合金甲、拿下界合金剑，站在中间偏右的菌岩小坡上
struct NetherUpdate: DotScene {
    let id = "1.16"
    let background: UInt32 = 0x2A0A0A

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.63) }
    private func lavaX(_ b: DotBuffer) -> [Int] { [Int(Double(b.cols) * 0.3), Int(Double(b.cols) * 0.86)] }

    /// 猪灵（斜对着右边的玩家，和玩家一样 32 点高）：宽大的粉色头，浅色大鼻子和鼻孔，獠牙，下垂的耳朵；
    /// 棕色皮甲配金扣，粉色手臂，棕色裤子。前面那只手（右侧）单独画，可以拿东西
    static func piglinBody(headDip: Int) -> Sprite {
        Sprite(width: 20, height: 32) { x, y in
            let P: UInt32 = 0xD9967C, p: UInt32 = 0xC27E64, side: UInt32 = 0xA86A52
            // 头：侧面 x3…6，正面 x7…16，耳朵挂在两边
            let hy = y - headDip
            if (0..<8).contains(hy) {
                if (3...6).contains(x) { return hy < 2 ? p : side }
                if (7...16).contains(x) {
                    let fx = x - 7
                    if hy == 3 && (fx == 1 || fx == 8) { return 0x2A1C14 }
                    if (4...6).contains(hy) && (3...6).contains(fx) { return hy == 5 && (fx == 3 || fx == 6) ? 0x8A4A3A : 0xF0B7A0 }
                    if hy == 6 && (fx == 1 || fx == 8) { return 0xF2E6C8 }
                    return hy < 2 ? 0xE5A68C : (noise(x, hy, 5) < 0.15 ? p : P)
                }
                if x == 2 && (2...5).contains(hy) { return 0xB4705A }
                if (17...18).contains(x) && (2...6).contains(hy) && !(x == 18 && hy == 2) { return 0xC27E64 }
            }
            // 身体：皮甲，腰带上的金扣
            if (8..<20).contains(y) {
                if (8...15).contains(x) {
                    if y == 14 { return (11...12).contains(x) ? 0xF5C84A : 0x4A2C18 }
                    if y == 13 && (11...12).contains(x) { return 0xF5C84A }
                    return noise(x, y, 6) < 0.2 ? 0x5E3820 : 0x7A4A2A
                }
                if (6...7).contains(x) { return 0x5E3820 }
                // 后面那只手（画面左侧）：粉色，袖口是皮甲
                if (2...5).contains(x) { return y < 10 ? 0x6A4026 : (x == 2 ? side : p) }
            }
            // 腿
            if (20..<32).contains(y) {
                if (8...15).contains(x) { return y >= 29 ? 0x3E2716 : (x == 11 || x == 12 ? 0x57361F : 0x6E4428) }
                if (6...7).contains(x) { return y >= 29 ? 0x2E1C10 : 0x4E3018 }
            }
            return nil
        }
    }
    static let piglinArm = Sprite(["LLL", "LLL"] + Array(repeating: "PPp", count: 9) + ["ppp"], ["L": 0x6A4026, "P": 0xD9967C, "p": 0xC27E64])
    static let goldIngot = Sprite(["..YYYY.", ".YyYYYY", "YYYYYYo", "ooooooo"], ["Y": 0xF5D74A, "y": 0xFFF39A, "o": 0xB08A1E])
    static let dirtItem = Sprite([".dDdD.", "dDdDdD", "DdDDdD", "dDdDDd", "DDdDdD", ".dDDd."], ["d": 0x6F4627, "D": 0x8A5A33])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 背景：下界岩的暗红，越往上越暗
        for y in 0..<g { for x in 0..<b.cols {
            var c = ditherRamp([0x1E0606, 0x2E0A0A, 0x431212, 0x5A1A18], Double(y) / Double(g), x, y)
            if noise(x / 3, y / 3, 5) > 0.93 { c = shade(c, 1.3) }
            b.set(x, y, c)
        } }
        // 熔岩瀑布两侧的光
        for lx in lavaX(b) { for y in 0..<g { for x in (lx - 20)..<(lx + 26) {
            let d = 1 - abs(Double(x - lx - 3)) / 23
            if d > 0, dither(x, y, d * 0.6) { b.set(x, y, 0x7A2A14) }
        } } }
        // 巨型绯红菌：菌柄 + 菌盖（疣块）+ 菌光体
        for (k, cx) in [0.1, 0.5, 0.95].enumerated() {
            let x = Int(Double(b.cols) * cx), h = Int(Double(g) * (0.45 + 0.1 * Double(k % 2)))
            b.fill(x, g - h, 5, h, 0x7B2E45)
            for y in (g - h)..<g where noise(x, y, 61) < 0.3 { b.set(x + 1, y, 0x5C2235) }
            let capTop = g - h - 14
            for y in capTop..<(g - h + 3) { for dx in -14...18 {
                let w = 14 - (g - h + 3 - y) / 2
                guard abs(dx - 2) <= w + 2 else { continue }
                b.set(x + dx, y, noise(x + dx, y, 62) < 0.08 ? 0xFFAE45 : pick([0xA31D1D, 0x8B1414, 0xB82A22], x + dx, y, 63))
            } }
            // 垂泪藤
            for v in 0..<5 { let vx = x - 10 + v * 6; let len = 6 + Int(noise(vx, 0, 64) * 14)
                for dy in 0..<len { b.set(vx, g - h + 3 + dy, dy == len - 1 ? 0xD9483A : 0xA3241D) } }
        }
        // 地面：绯红菌岩 + 下界岩；玩家脚下一个小坡
        let mound = Int(Double(b.cols) * 0.62)
        for x in 0..<b.cols {
            let bump = max(0, 5 - abs(x - mound - 8) / 3)
            for y in (g - bump)..<b.rows {
                let d = y - (g - bump)
                let c = d < 3 ? pick([0x8F1F1F, 0xB02A2A, 0x7A1818], x, y, 66) : pick([0x6E2626, 0x5A1E1E, 0x7A2C2C, 0x4E1A1A], x, y, 67)
                b.set(x, y, dither(x, y, Double(y - g) / Double(b.rows - g) * 0.8) ? shade(c, 0.55) : c)
            }
            if noise(x, 0, 68) > 0.6 && !(mound - 2...mound + 18).contains(x) { b.set(x, g - bump - 1, 0xC23A2E); if noise(x, 1, 68) > 0.5 { b.set(x, g - bump - 2, 0xD9483A) } }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 熔岩瀑布：往下流动的条纹
        for lx in lavaX(b) { for y in 0..<g { for x in lx..<(lx + 7) {
            let v = sin(Double(y) * 0.5 - t * 6 + Double(x) * 0.9)
            b.set(x, y, v > 0.6 ? 0xFFE08A : (v > -0.2 ? 0xFF9A2E : 0xE0561C))
        } } }
        // 绯红孢子与火星往上飘
        Paint.rising(&b, t: t, count: 40, colors: [0xD9483A, 0xFF7A3A, 0xFFB45A], top: 4, bottom: g - 2, speed: 0.05, seed: 3)
        // 以物换物（9 秒一轮）：玩家扔出金锭 → 猪灵接住，举到眼前看一看 → 扔出来一块泥土
        let cycle = 9.0, p = t.truncatingRemainder(dividingBy: cycle)
        let pgX = Int(Double(b.cols) * 0.22), meX = Int(Double(b.cols) * 0.62) + 4, meFeet = g - 6
        let inspecting = (1.2...3.8).contains(p)
        let headDip = inspecting && sin(t * 5) > 0 ? 1 : 0
        let bob = sin(t * 2.2) > 0.5 ? 1 : 0
        b.blit(Self.piglinBody(headDip: headDip), x: pgX, bottom: g - 1 - bob)
        // 猪灵前面那只手：接金锭时伸出去，看的时候举到脸前，扔泥土时往前一甩
        var pigArm = 0.1 + sin(t * 1.4) * 0.06
        if (0.7...1.2).contains(p) { pigArm = 0.9 }
        if inspecting { pigArm = 1.5 }
        if (3.8...4.3).contains(p) { pigArm = 1.5 + (p - 3.8) / 0.5 * 0.6 }
        let shoulderX = Double(pgX + 17), shoulderY = Double(g - 1 - bob - 23)
        // 朝右：手往画面右边抬
        b.blitRotated(Self.piglinArm, pivotX: shoulderX, pivotY: shoulderY, origin: (1.5, 0), angle: -pigArm)
        let pigHand = (shoulderX + sin(pigArm) * 10.5, shoulderY + cos(pigArm) * 10.5)
        if inspecting || (0.95...1.2).contains(p) {
            b.blit(Self.goldIngot, x: Int(pigHand.0) - 3, bottom: Int(pigHand.1) + 2 - (inspecting ? 2 : 0))
        }
        // 金锭从玩家手里飞到猪灵手里
        if (0.35...1.0).contains(p) {
            let k = (p - 0.35) / 0.65
            let x0 = Double(meX - 4), y0 = Double(meFeet - 18), x1 = pigHand.0, y1 = pigHand.1
            b.blit(Self.goldIngot, x: Int(x0 + (x1 - x0) * k) - 3, bottom: Int(y0 + (y1 - y0) * k - 4 * k * (1 - k) * 18))
        }
        // 扔出来的泥土：一道弧线落在两人之间，弹一下，躺几秒后消失
        if (4.1...8.4).contains(p) {
            let k = min(1, (p - 4.1) / 0.8)
            let x0 = pigHand.0, x1 = Double(b.cols) * 0.42
            var y = Double(g - 7) - 4 * k * (1 - k) * 16
            if k >= 1 { let q = (p - 4.9); if q < 0.4 { y -= 4 * (q / 0.4) * (1 - q / 0.4) * 3 } }
            let blinkOut = p > 7.6 && sin(t * 20) > 0
            if !blinkOut { b.blit(Self.dirtItem, x: Int(x0 + (x1 - x0) * k), bottom: Int(y) + 6) }
        }
        // 玩家：下界合金甲与剑，头盔时不时摘下来；开头那一下是把金锭扔出去
        let props = PlayerProps(held: .netheriteSword, armor: Armor(chest: .netherite, legs: .netherite, boots: .netherite), removableHelmet: .netherite)
        var pose = Player.idle(t, props: props, phase: 1)
        if p < 0.6 { pose.armAngle = 1.4 * sin(p / 0.6 * .pi); pose.itemTilt = 0 }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: meX, feet: meFeet, t: t)
    }
}

// MARK: - 1.20 Trails & Tales：樱花林与嗅探兽

/// 1.20 加入了樱花林、嗅探兽、考古（刷子与可疑的沙子）。左边的嗅探兽低头嗅地、刨土；
/// 玩家跪在可疑的沙子前用刷子刷，扬起沙尘；樱花瓣一直在飘
struct TrailsAndTales: DotScene {
    let id = "1.20"
    let background: UInt32 = 0x9EC1F7

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 嗅探兽（朝右，约 30×54）：方方正正的大身子，背上和两侧披着深绿的苔藓，下面是红褐色的毛，
    /// 前面是黄色的大鼻子。head 为鼻子往下伸的格数（嗅地、刨土）
    static func sniffer(head: Int) -> Sprite {
        Sprite(width: 56, height: 32) { x, y in
            let moss: [UInt32] = [0x1F6B4E, 0x2E8A60, 0x23784F, 0x3AA374]
            let fur: [UInt32] = [0x8A3A2A, 0xA44A32, 0x7A3222]
            // 腿
            if y >= 27 && ([5, 6, 7, 8, 18, 19, 20, 21, 31, 32, 33, 34].contains(x)) { return y == 31 ? 0x2A1E18 : 0x3A2A22 }
            // 身体：苔藓盖在上面，下沿参差不齐地垂下来
            if (1...43).contains(x) && (2...26).contains(y) {
                let fringe = 13 + Int(noise(x, 0, 5) * 4)
                if y < fringe { return y == 2 ? 0x3AA374 : pick(moss, x, y, 6) }
                let bottomFringe = 24 + Int(noise(x, 1, 5) * 3)
                if y <= bottomFringe { return pick(fur, x, y, 7) }
                return nil
            }
            if x == 0 && (4...20).contains(y) { return 0x154F3A }
            // 头：红褐色的上半部，黄色的鼻子。低头时整个头一起往下，脖子把头和身体连着，不会分开
            let hy = y - head
            if (40...45).contains(x) && (10...(18 + head)).contains(y) { return pick(fur, x, y, 10) }
            if (42...49).contains(x) && (10...18).contains(hy) { return hy == 13 && x == 47 ? 0x1E1E1D : pick(fur, x, hy, 8) }
            if (44...55).contains(x) && (17...26).contains(hy) {
                if hy == 20 && (x == 47 || x == 48 || x == 52 || x == 53) { return 0x5A3A12 }
                if hy == 17 || x == 55 { return 0xC49422 }
                return noise(x, hy, 9) < 0.2 ? 0xF5CF55 : 0xE8B93A
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x7FA6F2, 0x9EC1F7, 0xC2D6FA, 0xE6C9E8])
        // 远山
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.025 + 1) * 0.5 + 0.5) * 22 + noise(x / 7, 0, 2) * 6)
            for y in (g - 10 - h)..<g { b.set(x, y, ditherRamp([0x8FA8C8, 0x7E9A7A, 0x6A8F5E], Double(y - (g - 10 - h)) / Double(h + 10), x, y)) }
        }
        // 樱花树
        for (k, cx) in [0.06, 0.44, 0.93].enumerated() {
            let x = Int(Double(b.cols) * cx), h = 34 + k * 6
            b.fill(x, g - h, 4, h, 0x5E3A3A)
            for y in (g - h)..<g where noise(x, y, 5) < 0.3 { b.set(x + 1, y, 0x4A2C2E) }
            for dy in -18...6 { for dx in -24...26 {
                let r = Double(dx * dx) / 600 + Double(dy * dy) / 140
                guard r < 1, noise(x + dx, dy, 6 + k) > 0.1 else { continue }
                b.set(x + dx, g - h + dy, ditherRamp([0xE58FB8, 0xF5B3D2, 0xFAD0E3], 1 - r + noise(x + dx, dy, 7) * 0.2, x + dx, dy))
            } }
        }
        // 草地上铺着粉色花瓣
        Paint.strata(&b, from: g, top: [0x6DB34A, 0x5DA03F, 0x7AC255], topRows: 3, mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30,
                     deep: [0x7F7F7F, 0x6E6E6E], seed: 9)
        for x in 0..<b.cols where noise(x, 0, 13) > 0.62 { b.set(x, g - 1, pick([0xF5B3D2, 0xFAD0E3, 0xE58FB8], x, 0, 14)) }
        // 可疑的沙子（玩家面前）
        let sx = Int(Double(b.cols) * 0.66)
        for dy in 0..<14 { for dx in 0..<14 { b.set(sx + dx, g + 1 + dy - 14, noise(dx, dy, 15) < 0.12 ? 0xB59A5A : pick([0xE3D7AE, 0xD6C99B], dx, dy, 16)) } }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        Paint.falling(&b, t: t, count: 46, colors: [0xF5B3D2, 0xFAD0E3, 0xE58FB8], top: 0, bottom: g, speed: 0.05, seed: 21)
        // 嗅探兽：低头嗅、刨土，土粒往后溅
        let sp = t.truncatingRemainder(dividingBy: 5)
        let dig = sp > 2.2 && sp < 4
        let head = dig ? (sin(t * 10) > 0 ? 5 : 4) : (sp < 1 ? 0 : (sin(t * 4) > 0 ? 1 : 0))
        let sxn = Int(Double(b.cols) * 0.06)
        b.blit(Self.sniffer(head: head), x: sxn, bottom: g - 1 + (dig ? 4 : 0) - (dig ? 4 : 0))
        if dig { for i in 0..<7 {
            let q = (t * 3 + Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
            b.set(sxn + 50 - Int(q * 18), g - 2 - Int(4 * q * (1 - q) * 10), i % 2 == 0 ? 0x6F4627 : 0x8A5A33)
        } }
        // 玩家：在可疑的沙子前刷沙，沙尘扬起
        var pose = PlayerPose()
        let brushing = (t.truncatingRemainder(dividingBy: 8)) < 5.5
        pose.armAngle = brushing ? 1.05 + sin(t * 8) * 0.22 : Player.idle(t, props: PlayerProps(held: .brush)).armAngle
        pose.itemTilt = brushing ? -1.2 : 0
        pose.headDip = brushing ? 1 : 0
        let px = Int(Double(b.cols) * 0.66) + 20
        Player.draw(&b, look: cast.player, props: PlayerProps(held: .brush), pose: pose, x: px, feet: g - 1, t: t)
        if brushing { for i in 0..<6 {
            let q = (t * 1.8 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
            b.set(px - 10 + Int(sin(Double(i) * 2.1) * 4), g - 15 - Int(q * 10), 0xEAD9A6)
        } }
    }
}

// MARK: - 1.21 Tricky Trials：试炼密室里的旋风人

/// 1.21 加入了试炼密室（凝灰岩砖、铜灯）、试炼刷怪笼、旋风人和重锤。左边的旋风人浮在空中打转，时不时射出风弹；
/// 玩家拿着重锤，偶尔跳起来砸地，落地时扬起一圈尘土
struct TrickyTrials: DotScene {
    let id = "1.21"
    let background: UInt32 = 0x3A3D3E

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 凝灰岩砖墙：一格一格的砖，中间夹着铜块与铜格栅
        for y in 0..<g { for x in 0..<b.cols {
            let row = y / 8
            let mortar = y % 8 == 7 || (x + (row % 2) * 8) % 16 == 15
            var c = mortar ? 0x3E4142 : pick([0x5F6162, 0x6C6F70, 0x56595A, 0x646768], x / 4, y / 4, 3)
            c = dither(x, y, 0.45 - Double(y) / Double(g) * 0.45) ? shade(c, 0.7) : c
            b.set(x, y, c)
        } }
        // 铜的横梁与铜格栅（部分氧化成青绿色）
        let beam = Int(Double(g) * 0.3)
        for y in beam..<(beam + 5) { for x in 0..<b.cols {
            let ox = noise(x / 6, 0, 9) > 0.6
            b.set(x, y, y == beam ? (ox ? 0x8FD6B8 : 0xF0A070) : (ox ? pick([0x4FA88A, 0x5DB89A], x, y, 10) : pick([0xC46A3A, 0xB05A2E, 0xD07A48], x, y, 11)))
        } }
        for gx in stride(from: 10, to: b.cols, by: 60) { for y in (beam + 9)..<(beam + 25) { for x in gx..<(gx + 16) {
            b.set(x, y, (x - gx) % 4 == 0 || (y - beam - 9) % 4 == 0 ? 0xB05A2E : 0x2A2C2D)
        } } }
        // 地面：磨制凝灰岩
        Paint.strata(&b, from: g, top: [0x7A7D7E, 0x6C6F70, 0x84878A], topRows: 2, mid: [0x5F6162, 0x56595A, 0x646768], midRows: 16,
                     deep: [0x4F5152, 0x46484A], seed: 12)
        for x in stride(from: 0, to: b.cols, by: 16) { for y in g..<(g + 18) { b.set(x, y, 0x46484A) } }
        // 试炼刷怪笼：笼子方块，火焰在动态层
        let sx = Int(Double(b.cols) * 0.4)
        // 试炼刷怪笼：深蓝色的笼子，四角是橙色的铜
        for dy in 0..<16 { for dx in 0..<16 {
            let edge = dx == 0 || dx == 15 || dy == 0 || dy == 15
            let corner = (dx < 2 || dx > 13) && (dy < 2 || dy > 13)
            let bar = (dx % 4 == 1 || dy % 4 == 1) && noise(dx, dy, 13) > 0.25
            if corner { b.set(sx + dx, g - 16 + dy, 0xE07A3A) }
            else if edge { b.set(sx + dx, g - 16 + dy, 0x1E2E3E) }
            else if bar { b.set(sx + dx, g - 16 + dy, pick([0x2C4458, 0x3E5A72], dx, dy, 14)) }
            else { b.set(sx + dx, g - 16 + dy, 0x12181E) }
        } }
    }

    /// 旋风人（约 28 点高）：淡紫蓝色的方头，白色的眼睛；下面是条纹的 V 形核心，外面一圈圈白色半透明的风环，越往下越窄、一直在转
    static func breeze(_ b: inout DotBuffer, x cx: Int, top: Int, t: Double) {
        // 风环：从上往下 4 圈，宽度随转动变化，点是隔一个画一个（半透明）
        let widths = [20, 16, 12, 7]
        for (i, w0) in widths.enumerated() {
            let a = t * 4.2 + Double(i) * 0.9
            let w = Int(Double(w0) * (0.78 + 0.22 * abs(cos(a))))
            let y = top + 6 + i * 5 + Int(sin(a) * 1)
            let x0 = cx - w / 2 + Int(sin(a * 0.5) * 2)
            for dx in 0..<w {
                for (dy, on) in [(0, true), (3, true)] where on && (dx + dy + Int(t * 20)) % 2 == 0 {
                    b.set(x0 + dx, y + dy, dy == 0 ? 0xFFFFFF : 0xD6ECF5)
                }
            }
            for dy in 0...3 { b.set(x0, y + dy, 0xEAF6FB); b.set(x0 + w - 1, y + dy, 0xEAF6FB) }
        }
        // 条纹的 V 形核心
        let core = [6, 6, 5, 4, 4, 3, 2, 2, 1]
        for (i, w) in core.enumerated() {
            let c: UInt32 = [0xFFFFFF, 0xB9CDF0, 0x8F86D8][i % 3]
            for dx in 0..<w { b.set(cx - w / 2 + dx, top + 8 + i, c) }
        }
        // 方头
        for y in 0..<8 { for x in 0..<8 {
            var c: UInt32 = y < 2 ? (noise(x, y, 3) < 0.4 ? 0xB4A8E8 : 0xA397DD) : (noise(x, y, 4) < 0.25 ? 0x4E519E : 0x6A6CC4)
            if y == 4 && (x == 1 || x == 2 || x == 5 || x == 6) { c = 0xEAF6FF }
            if y == 5 && (x == 1 || x == 2 || x == 5 || x == 6) { c = 0x2A2E5A }
            b.set(cx - 4 + x, top + y, c)
        } }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        let beam = Int(Double(g) * 0.3)
        // 铜灯：一亮一暗
        for (i, lx) in stride(from: 40, to: b.cols, by: 70).enumerated() {
            let on = sin(t * 0.9 + Double(i) * 1.7) > -0.2
            b.fill(lx, beam + 5, 6, 6, on ? 0xF9C66A : 0x8A5A2E)
            if on { b.fill(lx + 1, beam + 6, 4, 4, 0xFFF0B0) }
        }
        // 试炼刷怪笼里的火（不祥时变成蓝色）
        let sx = Int(Double(b.cols) * 0.4)
        let ominous = t.truncatingRemainder(dividingBy: 12) > 8
        Paint.flame(&b, x: sx + 3, bottom: g - 3, width: 10, height: 10, t: t,
                    palette: ominous ? [0x1E5AD9, 0x3E8AF0, 0x8FD0FF, 0xE6F8FF] : [0xFF5A1F, 0xFF9A2E, 0xFFD54A, 0xFFF6B0])
        // 旋风人：浮在空中上下晃，风环一直在转
        let bx = Double(b.cols) * 0.18, by = Double(g) - 34 + sin(t * 2) * 3
        Self.breeze(&b, x: Int(bx), top: Int(by), t: t)
        // 风弹：每隔几秒朝玩家飞过去
        let wp = t.truncatingRemainder(dividingBy: 4.5) / 1.4
        if wp < 1 {
            let wx = Int(bx + 10 + wp * Double(b.cols) * 0.5), wy = Int(by + 12 + sin(wp * 3) * 2)
            for k in 0..<6 { let a = t * 12 + Double(k); b.set(wx + Int(cos(a) * 2), wy + Int(sin(a) * 2), k % 2 == 0 ? 0xD9F4FA : 0x9FD8E8) }
        }
        // 玩家：拿着重锤，偶尔跳起来砸地
        let props = PlayerProps(held: .mace)
        var pose = Player.idle(t, props: props, phase: 4)
        let sp = t.truncatingRemainder(dividingBy: 9) - 6.2
        if (0...1.1).contains(sp) {
            let k = sp / 0.9
            if k < 1 { pose.lift = Int((4 * k * (1 - k) * 18).rounded()); pose.armAngle = k < 0.5 ? 2.4 : 2.4 - (k - 0.5) * 4; pose.itemTilt = 0 }
        }
        let px = Int(Double(b.cols) * 0.74)
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
        if (0.9...1.5).contains(sp) {
            // 落地的冲击：一圈尘土往两边散开
            let q = (sp - 0.9) / 0.6
            for i in 0..<10 { let d = Int(q * 26) + i; b.set(px - 8 - d, g - 1 - (i % 3), 0xA8ABAD); b.set(px + 14 + d, g - 1 - (i % 3), 0xA8ABAD) }
        }
    }
}

// MARK: - 26.3 Wilderness Bound：斑驳森林里的营地

/// 26.3 加入了斑驳森林（红、橙、黄三色杨树和落叶）、废弃营地、草垫床、坐垫和探险家地图。
/// 傍晚的营地：篝火冒烟，狐狸睡在草垫床上；玩家坐在坐垫上看探险家地图
struct WildernessBound: DotScene {
    let id = "26.3"
    let background: UInt32 = 0x2A2340

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }
    private func fireX(_ b: DotBuffer) -> Int { Int(Double(b.cols) * 0.46) }

    /// 睡着的狐狸（蜷成一团，朝左）：橙色身子、深一点的背、白色的下巴和尾巴尖、黑色耳尖和爪子
    static let fox = Sprite([
        "..k..k............",
        "..OO.OO...........",
        ".OOOOOOO..oooooo..",
        "WOOcOOOOOooOOOOOo.",
        "WWOOOOOOOOOOOOOOOo",
        ".WWOOOOOOOOOOOOTTW",
        "..kWWOOOOOOOOTTTWW",
        "...kk.....kk..TWW.",
    ], ["O": 0xE37C2B, "o": 0xA85A20, "W": 0xF4F0E8, "k": 0x1E1E1D, "c": 0x4A2A12, "T": 0xE37C2B])

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 傍晚的天：上面是深紫，下面泛橙
        Paint.sky(&b, until: g, [0x1E1A3A, 0x2A2350, 0x4A3468, 0x8A4A5E, 0xD9784A])
        // 杨树：细高的浅色树干，三种颜色的树冠，树干上长着层架菇
        let leaves: [[UInt32]] = [[0xB8322A, 0xD9483A, 0xE86A4A], [0xD9702A, 0xEA8A3A, 0xF5A64A], [0xD9B02E, 0xEACB4A, 0xF5DE6A]]
        for (k, cx) in [0.04, 0.17, 0.3, 0.6, 0.72, 0.86, 0.97].enumerated() {
            let x = Int(Double(b.cols) * cx), h = Int(Double(g) * (0.55 + 0.25 * noise(k, 0, 3)))
            let far = k % 2 == 1
            b.fill(x, g - h, 3, h, far ? 0x6E6458 : 0x9A8A73)
            for y in stride(from: g - h, to: g, by: 3) where noise(x, y, 4) < 0.4 { b.set(x + 1, y, 0x5E5448) }
            if noise(k, 1, 3) > 0.4 { b.fill(x + 3, g - h / 3, 4, 1, 0xC98B4A); b.fill(x + 3, g - h / 3 + 1, 3, 1, 0xA86E36) }
            let pal = leaves[k % 3]
            for dy in -26...6 { for dx in -9...11 {
                let r = Double(dx * dx) / 90 + Double(dy * dy) / 420
                guard r < 1, noise(x + dx, dy, 5 + k) > 0.15 else { continue }
                let c = ditherRamp(pal, 1 - r, x + dx, dy)
                b.set(x + dx, g - h + dy, far ? shade(c, 0.7) : c)
            } }
        }
        // 地面：落叶层 + 泥土
        Paint.strata(&b, from: g, top: [0x8A5A2A, 0xB06A2E, 0x6E4A2A, 0xC4802E], topRows: 3, mid: [0x6F4627, 0x8A5A33, 0x5E3C22], midRows: 30,
                     deep: [0x4E3A2A, 0x42301F], seed: 15)
        for x in 0..<b.cols where noise(x, 0, 16) > 0.55 { b.set(x, g - 1, pick([0xD9483A, 0xEA8A3A, 0xEACB4A], x, 0, 17)) }
        // 帐篷（废弃营地）
        let tx = Int(Double(b.cols) * 0.22)
        for dy in 0..<22 { let w = dy * 13 / 10; for dx in -w...w {
            b.set(tx + dx, g - 22 + dy, dx == 0 ? 0x5A4A36 : (abs(dx) == w ? 0xA8946A : (dx < 0 ? 0xD9C8A0 : 0xC2B086)))
        } }
        for dy in 8..<22 { let w = (dy - 8) * 5 / 10; for dx in -w...w { b.set(tx + dx, g - 22 + dy, 0x2E2418) } }
        // 草垫床（狐狸睡在上面）
        b.fill(Int(Double(b.cols) * 0.04), g - 4, 22, 4, 0xD8B54A)
        for x in 0..<22 where x % 3 == 0 { b.set(Int(Double(b.cols) * 0.04) + x, g - 4, 0xF0D06A) }
        // 篝火的木头和火光照亮的地面
        let fx = fireX(b)
        b.fill(fx - 7, g - 3, 15, 3, 0x6B4A2C)
        b.fill(fx - 5, g - 5, 11, 2, 0x8A5A33)
        for x in (fx - 40)..<(fx + 40) { for y in (g - 30)..<g {
            let d = 1 - (pow(Double(x - fx) / 40, 2) + pow(Double(g - y) / 30, 2)).squareRoot()
            if d > 0, b[x, y] != 0, dither(x, y, d * 0.5) { b.set(x, y, shade(b[x, y] & 0xFFFFFF, 1.35)) }
        } }
        // 玩家坐的坐垫
        b.fill(Int(Double(b.cols) * 0.62) - 6, g - 4, 20, 4, 0xB5413A)
        b.fill(Int(Double(b.cols) * 0.62) - 6, g - 4, 20, 1, 0xD9605A)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 星星：只在天空上部，一闪一闪
        for i in 0..<30 where sin(t * 1.7 + Double(i) * 2.3) > 0.1 {
            b.set(Int(noise(i, 0, 91) * Double(b.cols)), Int(noise(i, 1, 91) * Double(g) * 0.35), i % 5 == 0 ? 0xFFF6C8 : 0xD9D4F0)
        }
        // 三色杨树的落叶
        Paint.falling(&b, t: t, count: 40, colors: [0xD9483A, 0xEA8A3A, 0xEACB4A], top: 0, bottom: g, speed: 0.04, seed: 31)
        // 篝火与往上飘的烟
        let fx = fireX(b)
        Paint.flame(&b, x: fx - 5, bottom: g - 6, width: 11, height: 12, t: t)
        for i in 0..<14 {
            let q = (t * 0.18 + Double(i) / 14).truncatingRemainder(dividingBy: 1)
            let x = fx + Int(sin(t * 0.8 + Double(i)) * (2 + q * 6)), y = g - 18 - Int(q * Double(g - 26))
            if dither(x, y, 1 - q) { b.set(x, y, q < 0.5 ? 0x9A93A6 : 0x6E6880) }
        }
        // 狐狸蜷在草垫床上睡觉，呼吸时身子起伏，耳朵偶尔动一下
        let fox = Self.fox
        let breath = sin(t * 1.6) > 0.3 ? 1 : 0
        b.blit(fox, x: Int(Double(b.cols) * 0.04) + 3, bottom: g - 5, w: fox.width, h: fox.height + breath)
        if t.truncatingRemainder(dividingBy: 5) < 0.2 { b.set(Int(Double(b.cols) * 0.04) + 5, g - 13 - breath, 0xE37C2B) }
        // 玩家坐在坐垫上看探险家地图
        let props = PlayerProps(held: .explorerMap)
        var pose = Player.idle(t, props: props, phase: 0)
        pose.sitting = true
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: Int(Double(b.cols) * 0.62), feet: g - 4, t: t)
    }
}

extension DotScenes {
    /// 版本号的前两段：1.8.9 → (1, 8)，26.4-snapshot-3 → (26, 4)，1.21-pre1 → (1, 21)。
    /// 快照、预发布、候选版都用同一个正式版的场景；24w14a 这类周快照没有对应的版本号，用默认场景
    static func family(_ version: String) -> (Int, Int)? {
        let head = version.split(separator: "-").first.map(String.init) ?? version
        let parts = head.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}

// MARK: - 1.19 The Wild Update：远古城市里的监守者

/// 1.19 加入了深暗之域、远古城市、幽匿方块和监守者。远古城市的深板岩砖墙，地上和墙上蔓延着幽匿，魂灯发着青光，
/// 背景是巨大的强化深板岩门框；监守者（比玩家高一大截）就在玩家旁边，触须抖动、胸口的灵魂一跳一跳，时不时探过头来嗅；
/// 玩家蹲着不出声，拿着追溯指针，监守者嗅的时候一动不敢动；黑暗效果让整个画面一阵一阵地变黑
struct WildUpdate: DotScene {
    let id = "1.19"
    let background: UInt32 = 0x05080A

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 监守者（朝右，48 点高，约 3 格，比玩家高一半）：宽厚的身子、相对小的头；深青黑的身体，骨色的肋骨和粗壮的上臂，
    /// 胸口青色的灵魂，头顶两侧的触须。pulse 为胸口灵魂的亮度（0…1），lean 为嗅的时候头往前探的格数
    static func warden(roar: Bool, pulse: Double, tendril: Int, lean: Int = 0) -> Sprite {
        let dark: [UInt32] = [0x0B1418, 0x0E1C22, 0x0A1216, 0x12262E]
        let teal: [UInt32] = [0x0E3B45, 0x12505C, 0x145361]
        let bone: [UInt32] = [0xB8B48E, 0x9E9A78, 0xC9C5A0]
        let soul: UInt32 = pulse > 0.6 ? 0x6FF4FF : (pulse > 0.3 ? 0x2AD6E8 : 0x1A8E9C)
        return Sprite(width: 38, height: 48) { x0, y in
            let x = y <= 17 ? x0 - lean : x0
            // 触须：头顶两侧往外翘
            if (0..<7).contains(y) {
                let lx = 10 - y / 2 - (y % 3 == 0 ? tendril : 0), rx = 26 + y / 2 + (y % 3 == 0 ? tendril : 0)
                if x == lx || x == lx + 1 || x == rx || x == rx - 1 { return y % 2 == 0 ? 0x3FC6D0 : 0x1E8E9A }
            }
            // 头：16 宽 14 高（x 10…25，y 4…17）
            if (10...25).contains(x) && (4...17).contains(y) {
                if y <= 6 { return noise(x, y, 3) < 0.12 ? 0x2AD6E8 : pick(teal, x, y, 4) }
                if (13...22).contains(x) && (roar ? (10...15) : (11...13)).contains(y) { return 0x040709 }
                if x <= 11 { return shade(pick(dark, x, y, 5), 0.8) }
                return noise(x, y, 6) < 0.15 ? pick(teal, x, y, 7) : pick(dark, x, y, 8)
            }
            // 粗壮的胳膊：8 宽，从肩膀一直垂到膝盖（x 1…8 和 29…36，y 18…43），上臂骨色，往下渐暗
            if (18...43).contains(y) && ((1...8).contains(x) || (29...36).contains(x)) {
                let k = Double(y - 18) / 25
                if (x == 1 || x == 36) && y < 30 { return pick(teal, x, y, 18) }
                return dither(x, y, k * 1.25) ? pick(dark, x, y, 9) : (noise(x, y, 10) < 0.22 ? 0x6E7680 : pick(bone, x, y, 11))
            }
            // 宽厚的身体：18 宽（x 10…27，y 18…35），胸口两侧是肋骨，中间是灵魂
            if (9...28).contains(x) && (18...35).contains(y) {
                let ribRow = (y - 20) % 3 == 0 && y < 33
                if ribRow && ((11...15).contains(x) || (22...26).contains(x)) { return pick(bone, x, y, 12) }
                if (16...21).contains(x) && (21...31).contains(y) && noise(x, y, 13) > 0.25 { return soul }
                return pick(dark, x, y, 14)
            }
            // 腿：两条 6 宽（x 11…16、21…26，y 36…47），脚上有骨色条纹
            if (36...47).contains(y) && ((11...16).contains(x) || (21...26).contains(x)) {
                if y >= 44 && (x == 12 || x == 15 || x == 22 || x == 25) { return pick(bone, x, y, 16) }
                return pick(dark, x, y, 17)
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 深板岩砖墙，越往上越黑
        for y in 0..<g { for x in 0..<b.cols {
            let row = y / 6
            let mortar = y % 6 == 5 || (x + (row % 2) * 8) % 16 == 15
            var c = mortar ? 0x1E1E22 : pick([0x3A3A3E, 0x45454B, 0x34343A, 0x4A4A50], x / 4, y / 3, 3)
            c = dither(x, y, 0.75 - Double(y) / Double(g) * 0.55) ? shade(c, 0.45) : c
            b.set(x, y, c)
        } }
        // 强化深板岩门框：骨色的四角，中间是空的黑
        let fx = Int(Double(b.cols) * 0.02), fw = Int(Double(b.cols) * 0.3), ft = Int(Double(g) * 0.12)
        for y in ft..<g { for x in fx..<(fx + fw) {
            let border = x < fx + 6 || x >= fx + fw - 6 || y < ft + 6
            if border {
                let corner = (x < fx + 6 || x >= fx + fw - 6) && (y - ft) % 16 < 3
                b.set(x, y, corner ? pick([0xC9C5A0, 0xB8B48E], x, y, 4) : pick([0x2E2E34, 0x3A3A40], x, y, 5))
            } else {
                b.set(x, y, ditherRamp([0x020304, 0x060B0E, 0x0B1A20], Double(y - ft) / Double(g - ft) * 0.8, x, y))
            }
        } }
        // 幽匿：从地面往墙上蔓延，深青色带青点
        for x in 0..<b.cols {
            let h = Int(noise(x / 5, 0, 6) * 18 + noise(x / 2, 1, 6) * 6)
            for dy in 0..<h { b.set(x, g - 1 - dy, noise(x, dy, 7) < 0.1 ? 0x2AD6E8 : pick([0x0B2A33, 0x0E3B45, 0x08202A], x, dy, 8)) }
        }
        Paint.strata(&b, from: g, top: [0x0E3B45, 0x0B2A33, 0x12505C], topRows: 3, mid: [0x34343A, 0x3A3A3E, 0x2E2E32], midRows: 16,
                     deep: [0x26262A, 0x1E1E22], seed: 19)
        for x in 0..<b.cols where noise(x, 2, 20) > 0.88 { b.set(x, g, 0x2AD6E8) }
        // 幽匿感测体（玩家前面）
        let sx = Int(Double(b.cols) * 0.58)
        for dy in 0..<8 { for dx in 0..<16 { b.set(sx + dx, g - 8 + dy, noise(dx, dy, 21) < 0.12 ? 0x2AD6E8 : pick([0x0E3B45, 0x12505C], dx, dy, 22)) } }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 魂灯：挂在上面，一直发着青光
        for lx in [Int(Double(b.cols) * 0.16), Int(Double(b.cols) * 0.86)] {
            let ly = Int(Double(g) * 0.28)
            b.fill(lx + 2, 0, 1, ly, 0x2E2E34)
            b.fill(lx, ly, 6, 8, 0x3A4A5A)
            b.fill(lx + 1, ly + 1, 4, 6, sin(t * 3 + Double(lx)) > 0 ? 0x6FF4FF : 0x2AD6E8)
            for i in 0..<10 { let a = Double(i) / 10 * 2 * .pi + t * 0.3; let r = 9 + sin(t * 2 + Double(i)) * 2
                if dither(lx, i, 0.5) { b.set(lx + 3 + Int(cos(a) * r), ly + 4 + Int(sin(a) * r), 0x1A6E7A) } }
        }
        // 往上飘的灵魂粒子
        Paint.rising(&b, t: t, count: 18, colors: [0x2AD6E8, 0x6FF4FF, 0x1A8E9C], top: 4, bottom: g - 4, speed: 0.04, seed: 9)
        // 监守者：就在玩家旁边，心跳、触须抖动，每隔几秒探过头来嗅一嗅
        let p = t.truncatingRemainder(dividingBy: 6.5)
        let sniffing = (2.2...4.4).contains(p)
        let lean = sniffing ? Int((2 * ramp(p, 2.2, 2.6) * (1 - ramp(p, 4.0, 4.4))).rounded()) : 0
        let beat = t * (sniffing ? 6.5 : 4.5)
        let pulse = max(0, sin(beat)) * (sin(beat) > 0.9 ? 1 : 0.7)
        let wx = Int(Double(b.cols) * 0.4)
        b.blit(Self.warden(roar: false, pulse: pulse, tendril: sin(t * (sniffing ? 16 : 6)) > 0 ? 1 : 0, lean: lean), x: wx, bottom: g - 1)
        if sniffing {
            // 嗅的时候鼻子前面冒出的小气流
            for i in 0..<4 {
                let q = (t * 2.4 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                b.set(wx + 27 + lean + Int(q * 7), g - 37 + i % 2 * 2 - Int(q * 3), q < 0.5 ? 0x6FF4FF : 0x1A8E9C)
            }
        }
        let roar = false
        // 幽匿感测体的触须：音波或脚步传到时亮起来
        let sx = Int(Double(b.cols) * 0.58)
        let lit = roar || sin(t * 1.3) > 0.85
        for k in 0..<4 { let tx = sx + 3 + k * 3; for dy in 0..<(4 + k % 2 * 2) { b.set(tx, g - 9 - dy, lit ? 0x6FF4FF : 0x0E3B45) } }
        // 玩家：蹲着不出声，看追溯指针；监守者嗅的时候一动不动，手也不敢抬
        let props = PlayerProps(held: .recoveryCompass)
        var pose = Player.idle(t, props: props, phase: 2)
        pose.sneaking = true
        pose.lookBack = false
        if sniffing { pose.armAngle = 0.15; pose.itemUp = 0; pose.headDip = 1 }
        let px = Int(Double(b.cols) * 0.68)
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
        // 黑暗效果：一阵一阵地变黑（有序抖动的黑点），只在玩家身边留一小圈能看见
        let dark = pow(max(0, sin(t * 2 * .pi / 3.6)), 2) * 0.92
        if dark > 0.02 {
            let cx = Double(px + 5), cy = Double(g - 16)
            for y in 0..<b.rows { for x in 0..<b.cols {
                let d = ((Double(x) - cx) * (Double(x) - cx) / 900 + (Double(y) - cy) * (Double(y) - cy) / 500).squareRoot()
                if dither(x, y, dark * min(1, max(0, d - 0.35) * 1.6)) { b.set(x, y, 0x020304) }
            } }
        }
    }
}

// MARK: - 1.9 Combat Update：末地城

/// 1.9 加入了末地城、末地船、潜影贝、鞘翅、盾牌和双持。末地的虚空里漂着末地石小岛，远处是紫珀块的末地城塔楼
/// 和挂着龙首的末地船，末影龙在天边盘旋；左边的潜影贝开合着壳射出潜影弹，玩家背着鞘翅绕着末地城滑翔，潜影弹在后面追
struct CombatUpdate: DotScene {
    let id = "1.9"
    let background: UInt32 = 0x0E0814

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    static let purpur: [UInt32] = [0xA77BA7, 0xB98CB9, 0x9A6E9A, 0xAC80AC]
    static let endStone: [UInt32] = [0xDBDE9E, 0xE8EAB0, 0xC6C98A, 0xD4D796]
    static let shield = Sprite([
        "oooooooo", "oWWwWWWo", "oWnWWnWo", "oWWWwWWo", "owWWWWwo", "oWWnWWWo", "oWWWWnWo", "oWwWWWWo",
        "oWWWwWWo", "oWnWWWWo", "oWWWWwWo", "oooooooo",
    ], ["o": 0x8A8E94, "W": 0x7A5A34, "w": 0x6A4A2A, "n": 0x5A5E66])

    /// 潜影贝（16×16）：紫珀色的壳，open 为壳打开的高度，打开时露出淡黄绿色的头
    static func shulker(open: Int) -> Sprite {
        Sprite(width: 16, height: 16 + open) { x, y in
            let lidBottom = 7
            // 上半个壳
            if y <= lidBottom {
                if y == 0 || x == 0 || x == 15 { return 0x8A5E8A }
                if y == lidBottom && (x < 3 || x > 12) { return 0x7A527A }
                return pick(Self.purpur, x, y, 3)
            }
            // 壳打开的缝里：头
            if y > lidBottom && y <= lidBottom + open {
                if (5...10).contains(x) {
                    let hy = y - lidBottom
                    if hy == 2 && (x == 6 || x == 9) { return 0x1E1E1D }
                    return hy == 1 ? 0xE3EAAA : 0xD7E09A
                }
                return nil
            }
            // 下半个壳
            if x == 0 || x == 15 || y == 15 + open { return 0x8A5E8A }
            return pick(Self.purpur, x, y + 40, 4)
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 虚空：深紫黑
        Paint.sky(&b, until: g, [0x0A0610, 0x120A1C, 0x1A0F28, 0x22132E])
        // 末地城塔楼：一层层往上，每层带末地石砖的窗带，顶上是末地烛
        let tx = Int(Double(b.cols) * 0.44)
        var top = Int(Double(g) * 0.12)
        let floors = 4
        let floorH = (g - top) / floors
        for f in 0..<floors {
            let w = 34 - f * 3, y0 = top + f * floorH
            let x0 = tx - w / 2 + (f % 2) * 2
            for y in y0..<(y0 + floorH) { for x in x0..<(x0 + w) {
                let line = (x - x0) % 8 == 0 || (y - y0) % 8 == 0
                var c = line ? 0x8A5E8A : pick(Self.purpur, x, y, 5)
                if (y - y0) > 3 && (y - y0) < 9 && (x - x0) > 2 && (x - x0) < w - 3 { c = (x - x0) % 6 < 2 ? 0x1A1024 : pick([0xE3E5A8, 0xD8DA9C], x, y, 6) }
                b.set(x, y, c)
            } }
            // 每层的屋檐往外伸
            for x in (x0 - 3)..<(x0 + w + 3) { b.set(x, y0, 0xC79CC7); b.set(x, y0 + 1, 0x9A6E9A) }
        }
        // 顶上的末地烛
        top = Int(Double(g) * 0.12)
        for rx in [tx - 15, tx + 15] { for dy in 0..<7 { b.set(rx, top - 1 - dy, dy == 6 ? 0xFFFFFF : 0xE8E0D8) } }
        // 远处漂着的末地船：船身是紫珀，船头挂着黑色的龙首
        let sx = Int(Double(b.cols) * 0.72), sy = Int(Double(g) * 0.22)
        for dy in 0..<6 { let w = 30 - dy * 2; for dx in 0..<w { b.set(sx + dy + dx, sy + dy, shade(pick(Self.purpur, dx, dy, 7), 0.7)) } }
        b.fill(sx + 13, sy - 14, 2, 14, 0x5E3A5E)
        b.fill(sx + 8, sy - 12, 12, 7, 0x6A3E6A)
        b.fill(sx - 4, sy - 2, 5, 4, 0x1E1E22); b.set(sx - 4, sy - 1, 0xD92AD9)
        // 末地石小岛
        for x in 0..<b.cols {
            let top = g - Int(max(0, sin(Double(x) * 0.02) * 3))
            for y in top..<b.rows {
                let d = y - top
                let c = d == 0 ? 0xF0F2C0 : pick(Self.endStone, x, y, 8)
                // 上面一截是实的末地石，再往下才渐渐融进虚空
                let fade = max(0, Double(d) / Double(b.rows - g) - 0.35) / 0.65
                b.set(x, y, dither(x, y, fade * 0.9) ? 0x1A0F28 : (d > 14 ? shade(c, 0.8) : c))
            }
        }
        // 紫颂植物：一节节方块往上长、往两边分叉，顶上是淡紫色的花方块
        func chorusBlock(_ x: Int, _ y: Int, _ size: Int) {
            for dy in 0..<size { for dx in 0..<size {
                let edge = dx == 0 || dy == 0 || dx == size - 1 || dy == size - 1
                b.set(x + dx, y + dy, edge ? 0x3E2450 : pick([0x5E3A6E, 0x7A4A8A, 0x6A4278], x + dx, y + dy, 9))
            } }
        }
        func chorusFlower(_ x: Int, _ y: Int, _ size: Int) {
            for dy in 0..<size { for dx in 0..<size {
                let edge = dx == 0 || dy == 0 || dx == size - 1 || dy == size - 1
                b.set(x + dx, y + dy, edge ? 0x7A4A8A : (noise(x + dx, y + dy, 10) < 0.35 ? 0xF2E6F5 : 0xC8A2D0))
            } }
        }
        for (k, cx) in [0.03, 0.27, 0.9].enumerated() {
            let n = 5
            var x = Int(Double(b.cols) * cx), y = g - n
            for seg in 0..<(4 + k) {
                chorusBlock(x, y, n); y -= n
                if seg % 2 == 1 {
                    let dir = (seg + k) % 2 == 0 ? 1 : -1
                    chorusBlock(x + dir * n, y + n, n)
                    chorusFlower(x + dir * n * 2, y + n, n)
                }
            }
            chorusFlower(x, y, n)
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 星星
        for i in 0..<36 where sin(t * 1.5 + Double(i) * 2.1) > 0 {
            b.set(Int(noise(i, 0, 81) * Double(b.cols)), Int(noise(i, 1, 81) * Double(g) * 0.7), i % 4 == 0 ? 0xF2E6F5 : 0x9A86B4)
        }
        // 末影龙在远处盘旋
        let dp = (t / 26).truncatingRemainder(dividingBy: 1)
        let dx = Int(Double(b.cols) * (1.1 - dp * 1.3)), dy = Int(Double(g) * 0.1 + sin(t * 0.5) * 4)
        let wing = sin(t * 3) > 0 ? -3 : 2
        b.fill(dx, dy, 14, 3, 0x14141A)
        b.fill(dx - 4, dy + 1, 4, 2, 0x14141A); b.set(dx - 4, dy + 1, 0xD92AD9)
        for k in 0..<7 { b.set(dx + 4 + k, dy + wing * (7 - k) / 7 - 1, 0x2A2A34); b.set(dx + 4 + k, dy + wing * (7 - k) / 7 - 2, 0x3A3A48) }
        b.fill(dx + 14, dy + 1, 8, 1, 0x14141A)
        // 潜影贝：壳一开一合，打开时射出潜影弹
        let cycle = 6.0, p = t.truncatingRemainder(dividingBy: cycle)
        let open = p < 0.5 ? Int(p / 0.5 * 5) : (p < 2.4 ? 5 : (p < 2.9 ? Int((2.9 - p) / 0.5 * 5) : 0))
        let towerTop = Int(Double(g) * 0.12), floorH = (g - towerTop) / 4
        let shx = Int(Double(b.cols) * 0.44) - 17 - 3 - 4
        let shBottom = towerTop + floorH * 2 - 1
        b.blit(Self.shulker(open: open), x: shx, bottom: shBottom)
        // 玩家：背着鞘翅绕着末地城滑翔，朝着飞行的方向；身后拖着几道气流
        let a = t * 0.32
        let cx = Double(b.cols) * 0.5 + cos(a) * Double(b.cols) * 0.36
        let cy = Double(g) * 0.42 + sin(a * 2) * Double(g) * 0.12
        let facingRight = -sin(a) > 0
        for k in 1...3 {
            let tx = Int(cx) + (facingRight ? -1 : 1) * (22 + k * 5), ty = Int(cy) - 4 + k * 3
            for d in 0..<(6 - k) { b.set(tx + (facingRight ? -d : d), ty, 0x6A5A84) }
        }
        // 潜影弹：追着玩家飞
        let bp = (p - 0.8) / 3.6
        if bp > 0 && bp < 1 {
            let bx = Double(shx + 8) + (cx - Double(shx + 8)) * bp, by = Double(shBottom - 8) + (cy - Double(shBottom - 8)) * bp + sin(bp * 14) * 3
            for (ox, oy, c) in [(0, 0, 0xFFFFFF), (1, 0, 0xF5E6A8), (0, 1, 0xF5E6A8), (1, 1, 0xFFFFFF)] as [(Int, Int, UInt32)] { b.set(Int(bx) + ox, Int(by) + oy, c) }
            for k in 1...4 { b.set(Int(bx) - k * 2, Int(by) + Int(sin(bp * 14 - Double(k)) * 1), 0xB9A6D8) }
        }
        var pose = PlayerPose()
        pose.flying = true
        Player.draw(&b, look: cast.player, props: PlayerProps(elytra: true), pose: pose, x: Int(cx), feet: Int(cy), t: t, facingRight: facingRight)
    }
}

// MARK: - 1.17 Caves & Cliffs I：繁茂洞穴

/// 1.17 加入了美西螈、发光鱿鱼、山羊、紫水晶、铜、望远镜，以及繁茂洞穴里的苔藓、杜鹃丛和发光浆果。
/// 洞顶垂下挂着发光浆果的洞穴藤，地上是苔藓和杜鹃丛，墙上一簇紫水晶在闪；左边的水塘里美西螈在游、发光鱿鱼在发光；
/// 玩家站在苔藓台子上，时不时举起望远镜往远处看
struct CavesAndCliffsI: DotScene {
    let id = "1.17"
    let background: UInt32 = 0x101410

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }
    private func pool(_ b: DotBuffer) -> ClosedRange<Int> { Int(Double(b.cols) * 0.05)...Int(Double(b.cols) * 0.42) }

    /// 美西螈（朝右）：粉色身体，深粉色的鳃在头两侧往上翘，尾巴是一片扁鳍
    static let axolotl = Sprite([
        "............g.g.g.", "............ggggg.", "TT....PPPPPPPPPPP.", "TTttPPPPPPPPPPPPPP",
        "TTttPPPPPPPPPPPkPP", "..ttpPPPPPPPPPPPPP", "....pppppppppppp..", ".....l...l....l...",
    ], ["P": 0xF4B4D0, "p": 0xE79AC0, "g": 0xD0558A, "T": 0xE58AB8, "t": 0xD877A8, "k": 0x3A1A3A, "l": 0xE79AC0])
    /// 发光鱿鱼（对照原版，约 16×34）：方方的青色身子，带发光的亮斑和十字形的眼睛；下面一排方块触手，越往下越亮、尖端发白绿光。
    /// sway 让每根触手错开摆动，glow 为亮斑的亮度
    static func glowSquid(t: Double, glow: Bool) -> Sprite {
        Sprite(width: 18, height: 36) { x, y in
            // 身子：x 1…16，y 0…15
            if (1...16).contains(x) && (0...15).contains(y) {
                if y == 0 { return 0x3EB4B0 }
                if (y == 7 && (3...5).contains(x)) || (x == 4 && (6...8).contains(y)) { return 0x0A2A2A }   // 左眼（十字）
                if (y == 7 && (12...14).contains(x)) || (x == 13 && (6...8).contains(y)) { return 0x0A2A2A }  // 右眼
                if [(3, 3), (9, 4), (14, 2), (6, 11), (11, 12), (2, 13), (15, 10)].contains(where: { $0 == (x, y) }) { return glow ? 0x9FF8E0 : 0x4EC0A8 }
                return (x + y * 3) % 7 == 0 ? 0x24928E : 0x1E8484
            }
            // 触手：4 根看得见的方块触手，各自摆动
            for (k, tx) in [2, 6, 10, 14].enumerated() {
                let off = Int((sin(t * 1.8 + Double(k) * 1.3 + Double(y) * 0.15) * Double(y - 16) * 0.08).rounded())
                if (16...35).contains(y) && (tx + off...tx + off + 1).contains(x) {
                    let f = Double(y - 16) / 19
                    if f > 0.85 { return glow ? 0xC8FFE8 : 0x8FF2D2 }
                    return f > 0.6 ? 0x5ECCB0 : (f > 0.3 ? 0x2EA89A : 0x1E8A8A)
                }
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 洞壁：上面是石头，越往下越绿
        for y in 0..<g { for x in 0..<b.cols {
            let k = Double(y) / Double(g)
            var c = ditherRamp([0x2A2E2A, 0x3E443A, 0x4E5A3A, 0x56663A], 0.1 + k * 0.85, x, y)
            if noise(x / 3, y / 3, 3) > 0.9 { c = shade(c, 1.2) }
            b.set(x, y, c)
        } }
        // 紫水晶晶簇（墙上）
        let ax = Int(Double(b.cols) * 0.56), ay = Int(Double(g) * 0.42)
        for (dx, dy, c) in [(0, -6, 0xD9C2FF), (-1, -5, 0xB98AF0), (0, -5, 0xE8D8FF), (1, -5, 0xB98AF0), (-1, -4, 0x9A6AD8), (0, -4, 0xC8A8F8),
                            (1, -4, 0x9A6AD8), (-4, -3, 0xB98AF0), (-3, -2, 0x9A6AD8), (3, -3, 0xB98AF0), (4, -2, 0x9A6AD8), (-2, -1, 0x8E5AC8),
                            (-1, -1, 0x9A6AD8), (0, -1, 0x8E5AC8), (1, -1, 0x9A6AD8), (2, -1, 0x8E5AC8)] as [(Int, Int, UInt32)] { b.set(ax + dx, ay + dy, c) }
        // 地面：苔藓块，下面是石头；左边是一块高出来的苔藓台地，中间挖出水塘（在地面以上，不会被标题挡住）
        let pl = pool(b)
        let terrace = g - 38
        for x in 0..<b.cols {
            let raised = x <= pl.upperBound + 5
            let top = raised ? terrace : g
            for y in top..<b.rows {
                let d = y - top
                let c = d < 4 ? pick([0x6E8E34, 0x5A7A2A, 0x7A9A3A, 0x4A6A22], x, y, 4) : pick([0x6E6E6E, 0x7A7A7A, 0x5E5E5E], x, y, 5)
                b.set(x, y, dither(x, y, max(0, Double(y - g)) / Double(b.rows - g) * 0.8) ? shade(c, 0.55) : c)
            }
            if pl.contains(x) { for y in terrace..<(g - 2) { b.set(x, y, ditherRamp([0x2E6A8A, 0x24587A, 0x1A4466], Double(y - terrace) / 36, x, y)) } }
        }
        // 杜鹃丛：苔绿色的灌木，开花的带粉色小花
        for (k, cx) in [0.5, 0.88].enumerated() {
            let x = Int(Double(b.cols) * cx)
            for dy in 0..<12 { for dx in -9...9 where Double(dx * dx) / 90 + Double((dy - 6) * (dy - 6)) / 40 < 1 {
                var c = pick([0x6E8E34, 0x5A7A2A, 0x86A43E], x + dx, dy, 6)
                if k == 0 && noise(x + dx, dy, 7) > 0.88 { c = 0xD878C8 }
                b.set(x + dx, g - 1 - dy, c)
            } }
            b.fill(x - 1, g - 3, 2, 3, 0x5A4030)
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 洞穴藤：从洞顶垂下，挂着发光的浆果，轻轻摆
        for i in 0..<14 {
            let x0 = Int(noise(i, 0, 61) * Double(b.cols)), len = 8 + Int(noise(i, 1, 61) * Double(g) * 0.45)
            for dy in 0..<len {
                let sway = Int((sin(t * 0.9 + Double(i)) * Double(dy) * 0.06).rounded())
                b.set(x0 + sway, dy, dy % 3 == 0 ? 0x5A8A2A : 0x4A7A22)
                if dy % 6 == 4 && noise(i, dy, 62) > 0.4 {
                    let glow: UInt32 = sin(t * 2 + Double(i + dy)) > 0 ? 0xFFC04A : 0xF59A2A
                    b.set(x0 + sway + 1, dy, glow); b.set(x0 + sway + 1, dy + 1, glow)
                }
            }
        }
        // 孢子花落下的绿色孢子
        Paint.falling(&b, t: t, count: 22, colors: [0x9AD06A, 0x6EA43E], top: 0, bottom: g, speed: 0.03, seed: 63)
        // 紫水晶一闪一闪
        let ax = Int(Double(b.cols) * 0.56), ay = Int(Double(g) * 0.42)
        if sin(t * 3) > 0.7 { b.set(ax, ay - 7, 0xFFFFFF); b.set(ax + 2, ay - 4, 0xF2E6FF) }
        // 水塘：水面起伏，美西螈游来游去，发光鱿鱼的光斑一亮一暗
        let pl = pool(b)
        let terrace = g - 38
        for x in pl { b.set(x, terrace + (sin(Double(x) * 0.5 + t * 2) > 0.6 ? 0 : 1), 0x8FC4E8) }
        let ap = (t / 9).truncatingRemainder(dividingBy: 1)
        let right = ap < 0.5
        let axX = pl.lowerBound + 4 + Int(Double(pl.count - 26) * (right ? ap * 2 : (1 - ap) * 2))
        b.blit(Self.axolotl, x: axX, bottom: g - 26 + Int((sin(t * 2.4) * 1).rounded()), flip: !right)
        b.blit(Self.glowSquid(t: t, glow: sin(t * 1.4) > 0), x: pl.lowerBound + Int(Double(pl.count) * 0.68), bottom: g - 3 - Int((sin(t * 0.8) * 1.5).rounded()))
        // 玩家：站在苔藓台子上，时不时举起望远镜
        let props = PlayerProps(held: .spyglass)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 7), x: Int(Double(b.cols) * 0.72), feet: g - 1, t: t)
    }
}

// MARK: - 1.18 Caves & Cliffs II：高山与山羊

/// 1.18 重做了地形：高耸的尖峭山峰、雪坡、细雪。远处一层层带雪顶的灰色山峰，
/// 左边的山羊低头冲过来把玩家顶飞一下（玩家受击变红、往后退），然后退回去再来
struct CavesAndCliffsII: DotScene {
    let id = "1.18"
    let background: UInt32 = 0x8FB3FF

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 山羊（朝右，约 30×21）：白色的毛，深灰色往后弯的角，下巴有胡子，蹄子是深色的
    static func goat(headDown: Bool) -> Sprite {
        Sprite(width: 32, height: 22) { x, y in
            let W: [UInt32] = [0xE8E6E0, 0xD8D4CC, 0xF2F0EA]
            // 身体
            if (2...23).contains(x) && (7...15).contains(y) { return y == 15 || x == 2 ? 0xC4C0B8 : pick(W, x, y, 3) }
            // 腿与蹄子
            if (16...21).contains(y) && [4, 5, 9, 10, 17, 18, 21, 22].contains(x) { return y >= 20 ? 0x3A3A3A : pick(W, x, y, 4) }
            // 头（低头冲撞时整个往下）
            let hy = headDown ? y - 4 : y
            if (22...30).contains(x) && (4...11).contains(hy) {
                if hy == 7 && x == 28 { return 0x1E1E1D }
                if x >= 29 && hy >= 9 { return 0x4A4A4A }
                return pick(W, x, hy, 5)
            }
            if (24...26).contains(x) && (12...14).contains(hy) { return 0xD8D4CC }   // 胡子
            if (22...24).contains(x) && (0...3).contains(hy) || (23...25).contains(x) && hy == 4 { return hy < 2 ? 0x6E6E6E : 0x4A4A4A }  // 角
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x7FA6F2, 0xA5C1F6, 0xD2E0FA])
        // 三层山峰：越远越淡；尖峭，带雪顶
        for (layer, base) in [(0, 0.55), (1, 0.72), (2, 0.9)].reversed() {
            let haze = 0.55 + 0.15 * Double(layer)
            for x in 0..<b.cols {
                let peaks = abs(sin(Double(x) * (0.045 + 0.01 * Double(layer)) + Double(layer) * 1.7))
                let h = Int(Double(g) * (base - 0.2) * peaks + noise(x / 3, layer, 7) * 6) + Int(Double(g) * 0.18)
                let top = g - h
                for y in max(0, top)..<g {
                    let d = y - top
                    var c = d < 4 + Int(noise(x, 0, 8 + layer) * 6) ? pick([0xF4F8FF, 0xE6EEFA], x, y, 9) : pick([0x7A7A7A, 0x8A8A8A, 0x6E6E6E, 0x949494], x / 2, y / 2, 10 + layer)
                    if layer < 2 { c = dither(x, y, 1 - haze) ? 0xB4C8EA : c }
                    b.set(x, y, c)
                }
            }
        }
        // 近处的雪坡：左边高一点（山羊站的台子）
        for x in 0..<b.cols {
            let ledge = x < Int(Double(b.cols) * 0.3) ? 6 : 0
            for y in (g - ledge)..<b.rows {
                let d = y - (g - ledge)
                let c = d < 5 ? pick([0xF4F8FF, 0xE6EEFA, 0xFFFFFF], x, y, 11) : pick([0x8A8A8A, 0x7A7A7A, 0x949494], x, y, 12)
                b.set(x, y, dither(x, y, Double(y - g) / Double(b.rows - g) * 0.7) ? shade(c, 0.6) : c)
            }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        Paint.falling(&b, t: t, count: 30, colors: [0xFFFFFF, 0xE6EEFA], top: 0, bottom: g, speed: 0.04, seed: 71)
        // 山羊冲撞（7 秒一轮）：站着 → 低头蓄力 → 冲过去 → 把玩家顶开 → 退回去
        let p = t.truncatingRemainder(dividingBy: 7)
        let start = Double(b.cols) * 0.1, hit = Double(b.cols) * 0.62
        var gx = start
        var headDown = false
        if (1.5...2.3).contains(p) { headDown = true }
        if (2.3...2.9).contains(p) { headDown = true; gx = start + (hit - start) * ramp(p, 2.3, 2.9) }
        if (2.9...3.4).contains(p) { gx = hit }
        if (3.4...5.5).contains(p) { gx = hit - (hit - start) * ramp(p, 3.4, 5.5) }
        let onLedge = gx < Double(b.cols) * 0.3 - 20
        let hop = (2.3...2.9).contains(p) ? Int(abs(sin(p * 20)) * 2) : 0
        b.blit(Self.goat(headDown: headDown), x: Int(gx), bottom: g - 1 - (onLedge ? 6 : 0) - hop, flip: (3.4...5.5).contains(p))
        // 玩家：被撞到时变红、往后退一截
        var pose = Player.idle(t, props: PlayerProps(), phase: 8)
        if (2.85...4.2).contains(p) {
            pose.hurt = max(0, 1 - (p - 2.85) / 0.3)
            pose.dx = Int((10 * ramp(p, 2.85, 3.2) * (1 - ramp(p, 3.6, 4.2))).rounded())
            if p < 3.2 { pose.lift = Int((sin((p - 2.85) / 0.35 * .pi) * 5).rounded()) }
        }
        Player.draw(&b, look: cast.player, pose: pose, x: Int(Double(b.cols) * 0.74), feet: g - 1, t: t)
    }
}

// MARK: - 1.14 Village & Pillage：掠夺者袭击村庄

/// 1.14 重做了村庄和村民，加入了掠夺者、劫掠兽、弩、钟。村子里有房子、钟和一个村民；
/// 左边的劫掠兽驮着掠夺者冲进来，掠夺者举弩射击；玩家拿着弩还击，箭矢在中间飞
struct VillageAndPillage: DotScene {
    let id = "1.14"
    let background: UInt32 = 0x86AAF2

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 劫掠兽（朝右，约 46×34，对照原版）：暖深灰的大身子，毛的纹理是规则的竖纹而不是噪点；
    /// 大方头上一道更暗的眉带，绿眼睛，黑色的长鼻子垂到下巴下面，两侧伸出灰绿色的角；
    /// 背上是橙色的鞍，肩膀、屁股和四条腿上有浅青灰色的毛簇
    static func ravager(step: Int) -> Sprite {
        let base: UInt32 = 0x4A4644, light: UInt32 = 0x58534F, dark: UInt32 = 0x3C3836
        let tuft: [UInt32] = [0x9FB8B8, 0xC4D4D4, 0x7A9090]
        func fur(_ x: Int, _ y: Int) -> UInt32 { (x * 3 + y) % 9 == 0 ? light : ((x + y * 2) % 11 == 0 ? dark : base) }
        func tuftC(_ x: Int, _ y: Int, top: Int) -> UInt32 { y == top ? tuft[1] : ((x + y) % 4 == 0 ? tuft[2] : tuft[0]) }
        return Sprite(width: 46, height: 34) { x, y in
            // 鞍：橙色坐垫，深色边
            if (12...26).contains(x) && (3...6).contains(y) { return (x == 12 || x == 26 || y == 6) ? 0x3A2A22 : (y == 3 ? 0xF09A5A : 0xE07A3A) }
            // 肩膀和屁股上的毛簇（浅青灰色的小方块）
            if (3...8).contains(x) && (4...8).contains(y) || (28...33).contains(x) && (4...8).contains(y) { return tuftC(x, y, top: 4) }
            // 身体
            if (2...33).contains(x) && (7...23).contains(y) { return (y == 23 || x == 2) ? dark : (y == 7 ? light : fur(x, y)) }
            // 四条粗腿：上下两圈毛簇，走路时前后错开
            for (lx, ph) in [(3, 0), (11, 1), (21, 0), (28, 1)] {
                let off = (ph == step) ? -1 : 0
                if (lx...(lx + 5)).contains(x) && (24...(33 + off)).contains(y) {
                    if (24...25).contains(y) || (30 + off...31 + off).contains(y) { return tuftC(x, y, top: y < 28 ? 24 : 30 + off) }
                    return y >= 32 + off ? 0x2E2A28 : fur(x, y)
                }
            }
            // 头：在前面偏下；眉带、绿眼睛、黑色长鼻子
            if (31...44).contains(x) && (9...23).contains(y) {
                // 头有一圈更暗的轮廓，和身体分开
                if x == 31 || x == 44 || y == 9 || y == 23 { return 0x2A2624 }
                if y == 10 { return light }
                if (13...14).contains(y) { return (x == 37 || x == 41) && y == 14 ? 0x3AA04A : 0x2E2B2A }
                if (38...41).contains(x) && (15...27).contains(y) { return x == 38 ? 0x161614 : 0x222220 }
                return x == 31 ? dark : fur(x, y)
            }
            if (38...41).contains(x) && (24...27).contains(y) { return x == 38 ? 0x161614 : 0x222220 }
            // 角：从头顶两侧往外、往后伸
            if (33...36).contains(x) && (6...8).contains(y) || (30...33).contains(x) && (4...6).contains(y) { return y <= 4 ? 0x8A9692 : 0x6E7A76 }
            if (42...45).contains(x) && (8...10).contains(y) { return y == 8 ? 0x8A9692 : 0x6E7A76 }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6])
        // 远处的山丘
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.03 + 2) * 0.5 + 0.5) * 16 + noise(x / 6, 0, 2) * 5)
            for y in (g - h)..<g { b.set(x, y, pick([0x5F8C4E, 0x547F45, 0x6A9757], x, y, 3)) }
        }
        // 平原村庄的房子：圆石地基、橡木板墙、原木柱、玻璃窗、斜屋顶
        for (k, hx) in [0.4, 0.7].enumerated() {
            let x0 = Int(Double(b.cols) * hx), w = 30 + k * 6, h = 22
            for y in (g - h)..<g { for x in x0..<(x0 + w) {
                let base = y >= g - 4
                let post = x == x0 || x == x0 + w - 1
                var c = base ? pick([0x7A7A7A, 0x8A8A8A, 0x6A6A6A], x, y, 4) : (post ? 0x6B5133 : ((y - g) % 4 == 0 ? 0x9A7A4A : pick([0xB8945A, 0xA8844E], x, y, 5)))
                if !base && (y - (g - h)) > 5 && (y - (g - h)) < 13 && ((x - x0) % 12 > 3 && (x - x0) % 12 < 9) { c = (x - x0) % 12 == 6 ? 0x6B5133 : 0xB4D8F0 }
                b.set(x, y, c)
            } }
            for r in 0..<10 { for x in (x0 - 3 + r)..<(x0 + w + 3 - r) { b.set(x, g - h - 1 - r, r % 2 == 0 ? 0x6B4A2C : 0x8A6238) } }
        }
        // 钟：两根石柱，横梁上挂着金色的钟
        let bx = Int(Double(b.cols) * 0.6)
        b.fill(bx, g - 22, 2, 22, 0x6E6E6E); b.fill(bx + 12, g - 22, 2, 22, 0x6E6E6E); b.fill(bx, g - 23, 14, 2, 0x4A3A2A)
        for dy in 0..<8 { let w = 4 + dy / 2; b.fill(bx + 7 - w / 2, g - 20 + dy, w, 1, dy == 7 ? 0xC49A2A : (dy % 3 == 0 ? 0xFFE27A : 0xF5C840)) }
        // 草地与土路
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35], topRows: 3, mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30,
                     deep: [0x7F7F7F, 0x6E6E6E], seed: 21)
        for x in Int(Double(b.cols) * 0.36)..<b.cols { b.set(x, g, pick([0xA8844E, 0x9A7A4A], x, 0, 22)); b.set(x, g + 1, 0x8A6A3A) }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        // 营火的烟（从房子后面冒出来）
        for i in 0..<10 {
            let q = (t * 0.15 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
            let x = Int(Double(b.cols) * 0.52) + Int(sin(t + Double(i)) * (1 + q * 4)), y = g - 26 - Int(q * Double(g - 30))
            if dither(x, y, 1 - q) { b.set(x, y, 0xB4B4B8) }
        }
        // 劫掠兽驮着掠夺者，原地踏步、一冲一冲的
        let p = t.truncatingRemainder(dividingBy: 6)
        let charge = (1.0...1.6).contains(p) ? ramp(p, 1.0, 1.3) * (1 - ramp(p, 1.3, 1.6)) : 0
        let rx = Int(Double(b.cols) * 0.04 + charge * 16)
        let step = Int(t * 4) % 2
        b.blit(Self.ravager(step: step), x: rx, bottom: g - 1 - (step == 0 ? 1 : 0))
        var rider = PlayerPose()
        rider.sitting = true
        rider.armAngle = 1.5
        // 弩端平，指向前方：物品角度 = 手臂角度 − π/2 + 0.45 + tilt = −π/2
        rider.itemTilt = -(rider.armAngle + 0.45)
        // 掠夺者骑在鞍上：坐姿的大腿压在鞍上，小腿垂在身体侧面
        Player.draw(&b, look: .pillager, props: PlayerProps(held: .crossbow), pose: rider, x: rx + 20, feet: g - 34 + 3 + 10 - (step == 0 ? 1 : 0), t: t + 2, facingRight: true)
        // 村民在钟旁边抱着手，被吓得来回张望
        var vpose = PlayerPose()
        vpose.armAngle = 0
        Player.draw(&b, look: .villager, pose: vpose, x: Int(Double(b.cols) * 0.6) + 20, feet: g - 1, t: t + 4, facingRight: sin(t * 1.1) > 0.3)
        // 双方的弩箭
        func bolt(from x0: Int, to x1: Int, y: Int, since q: Double) {
            guard q >= 0 && q < 1 else { return }
            let x = x0 + Int(Double(x1 - x0) * q)
            for k in 0..<6 { b.set(x + (x1 > x0 ? -k : k), y, k == 0 ? 0xC4C8CE : 0x6B4A2C) }
        }
        let px = Int(Double(b.cols) * 0.82)
        bolt(from: rx + 30, to: px - 6, y: g - 26, since: (p - 2.0) / 0.8)
        bolt(from: px - 8, to: rx + 34, y: g - 24, since: (p - 4.0) / 0.8)
        // 玩家：举着弩瞄准，射出去时手往后一顿
        var pose = Player.idle(t, props: PlayerProps(held: .crossbow), phase: 9)
        pose.armAngle = 1.5
        if (4.0...4.2).contains(p) { pose.armAngle = 1.38; pose.dx = 1 }
        pose.itemTilt = -(pose.armAngle + 0.45)
        if (2.75...3.1).contains(p) { pose.hurt = 1 - (p - 2.75) / 0.35 }
        Player.draw(&b, look: cast.player, props: PlayerProps(held: .crossbow), pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.15 Buzzy Bees：蜜蜂与蜂巢

/// 1.15 加入了蜜蜂、蜂巢、蜂箱、蜂蜜块和蜂蜜瓶。花田里一棵橡树上挂着蜂巢，蜂蜜往下滴，
/// 蜜蜂带着花粉飞来飞去；树下点着营火让蜜蜂安静，玩家拿着蜂蜜瓶，时不时举起来看看收的蜂蜜
struct BuzzyBees: DotScene {
    let id = "1.15"
    let background: UInt32 = 0x86AAF2

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.64) }

    /// 蜜蜂（朝右，约 9×7）：黄黑条纹、两片白色的翅膀、深色的眼睛
    static func bee(flap: Bool, pollen: Bool) -> Sprite {
        Sprite(flap ? [
            "...ww.ww.", "...ww.ww.", ".YYBYYBYY", "YYYBYYBkY", "YYYBYYBYY", ".YYBYYBYY", (pollen ? "..p..p..." : "........."),
        ] : [
            ".........", "..www.ww.", ".YYBYYBYY", "YYYBYYBkY", "YYYBYYBYY", ".YYBYYBYY", (pollen ? "..p..p..." : "........."),
        ], ["Y": 0xF2C640, "B": 0x2A2A2A, "w": 0xE8F4F8, "k": 0x1E1E1D, "p": 0xFFE27A])
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6])
        // 橡树和挂在树枝上的蜂巢（黄色带棕色环纹的方块，中间一个洞）
        let tx = Int(Double(b.cols) * 0.3)
        b.fill(tx, g - 44, 5, 44, 0x6B5133)
        for y in (g - 74)..<(g - 38) { for x in (tx - 26)..<(tx + 30) where Double((x - tx - 2) * (x - tx - 2)) / 760 + Double((y - g + 56) * (y - g + 56)) / 300 < 1 && noise(x, y, 3) > 0.1 {
            b.set(x, y, pick([0x3E7A2C, 0x4A8A34, 0x356A26], x, y, 4))
        } }
        let nx = tx + 8, ny = g - 38
        for dy in 0..<14 { for dx in 0..<14 {
            let ring = max(abs(dx - 7), abs(dy - 7))
            var c: UInt32 = ring % 3 == 0 ? 0x8A5A2A : (ring % 3 == 1 ? 0xF2C640 : 0xE0AE30)
            if (5...8).contains(dx) && (8...11).contains(dy) { c = 0x3A2412 }
            b.set(nx + dx, ny + dy, c)
        } }
        // 花田：各色小花
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35], topRows: 3, mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30,
                     deep: [0x7F7F7F, 0x6E6E6E], seed: 23)
        let flowers: [UInt32] = [0xF2E64A, 0xE53B2C, 0xF4F4F4, 0x8E6FD6, 0xF29A3A, 0x4A78EE]
        for x in stride(from: 2, to: b.cols, by: 5) where noise(x, 0, 24) > 0.3 {
            let h = 2 + Int(noise(x, 1, 24) * 4)
            for dy in 0..<h { b.set(x, g - 1 - dy, 0x3E8A2A) }
            let c = flowers[Int(noise(x, 2, 24) * Double(flowers.count)) % flowers.count]
            b.set(x, g - 1 - h, c); b.set(x - 1, g - h, c); b.set(x + 1, g - h, c)
        }
        // 营火
        let cx = Int(Double(b.cols) * 0.32)
        b.fill(cx - 7, g - 3, 15, 3, 0x6B4A2C); b.fill(cx - 5, g - 5, 11, 2, 0x8A5A33)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 3)
        let tx = Int(Double(b.cols) * 0.3), nx = tx + 8, ny = g - 38
        // 蜂蜜从蜂巢底部往下滴
        let dp = t.truncatingRemainder(dividingBy: 2.4) / 2.4
        b.set(nx + 7, ny + 14 + Int(dp * dp * Double(g - ny - 18)), 0xF5A42E)
        // 营火与烟
        let cx = Int(Double(b.cols) * 0.32)
        Paint.flame(&b, x: cx - 5, bottom: g - 6, width: 11, height: 9, t: t)
        for i in 0..<10 {
            let q = (t * 0.2 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
            let x = cx + Int(sin(t + Double(i)) * (1 + q * 5)), y = g - 14 - Int(q * 30)
            if dither(x, y, 1 - q) { b.set(x, y, 0xC8C8CC) }
        }
        // 蜜蜂：在蜂巢和花丛之间绕着飞，有的带着花粉
        for i in 0..<5 {
            let a = t * (0.9 + Double(i) * 0.13) + Double(i) * 1.3
            let x = Double(nx) + cos(a) * (18 + Double(i) * 9) + Double(i) * 6
            let y = Double(ny) + 6 + sin(a * 1.7) * (8 + Double(i) * 2) + Double(i) * 3
            b.blit(Self.bee(flap: sin(t * 22 + Double(i)) > 0, pollen: i % 2 == 0), x: Int(x), bottom: Int(y), flip: -sin(a) < 0)
        }
        // 玩家：拿着蜂蜜瓶
        let props = PlayerProps(held: .honeyBottle)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 10), x: Int(Double(b.cols) * 0.7), feet: g - 1, t: t)
    }
}
