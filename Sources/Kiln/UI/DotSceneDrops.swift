import SwiftUI

// MARK: - 1.21 之后的小版本（Game Drop）与 2026 年的版本
//
// 1.21.x 每个小版本都是一次独立的更新（苍白之园、春意盎然、追逐天空、铜器时代、坐骑乱斗），各自一个场景；
// 画法与 DotSceneVersions.swift 相同：先查 minecraft.wiki 的渲染图和贴图，按真实尺寸（1 格 = 16 点）画。

// MARK: - 1.21.4 The Garden Awakens：苍白之园里的嘎枝

/// 1.21.4 加入了苍白之园：深灰的苍白橡木、垂下来的苍白垂须、地上的苍白苔藓、夜里睁开的眼眸花，还有嘎枝与嘎枝之心。
/// 起雾的夜里：左边大树里嵌着嘎枝之心，一明一暗；嘎枝只在玩家没看着它时才动——玩家一回头，它就往前挪几步，
/// 玩家转回来，它立刻僵住。挨到跟前时玩家打它一下，嘎枝化成一串橙色的树脂粒子飞回心脏，再从树边冒出来
struct GardenAwakens: DotScene {
    let id = "1.21.4"
    let background: UInt32 = 0x121418

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }
    private func heartTree(_ b: DotBuffer) -> Int { Int(Double(b.cols) * 0.06) }
    private func heartY(_ b: DotBuffer) -> Int { ground(b) - 40 }

    static let bark: [UInt32] = [0x5A5250, 0x4A4240, 0x3E3634, 0x6A625E]
    static let paleLeaves: [UInt32] = [0x5A645A, 0x6E786E, 0x8A948A, 0xA4ACA2]

    /// 嘎枝（朝右略侧，16×44，约 2.7 格高）：深灰褐的树皮身子，头顶一圈枝杈，脸上几道橙色的眼光，
    /// 头顶和肩上各一块苍白的树皮，细长的手臂垂到膝盖，脚是散开的根。awake 时眼睛发亮；step 为迈步（0 或 1）
    static func creaking(awake: Bool, step: Int) -> Sprite {
        let bark: [UInt32] = [0x483C3C, 0x3C3030, 0x544848, 0x302424]
        let eye: UInt32 = awake ? 0xFF8A1E : 0x6A4630
        let twigs: [(Int, Int)] = [(3, 2), (5, 0), (7, 3), (9, 1), (11, 0), (12, 3)]
        return Sprite(width: 16, height: 44) { x, y in
            for (tx, top) in twigs where x == tx && y >= top && y < 6 { return 0x302424 }
            if y == 1 && (x == 4 || x == 10) { return 0x3C3030 }
            // 头：8 宽 10 高
            if (4...11).contains(x) && (6...15).contains(y) {
                if (y == 9 && (5...6).contains(x)) || (y == 12 && (5...6).contains(x)) || (y == 10 && (9...10).contains(x)) { return eye }
                if y <= 7 && (8...10).contains(x) { return 0xC8C0B8 }
                return pick(bark, x, y, 3)
            }
            // 身子：细，肩上一块苍白的树皮，偶尔带一点苔
            if (5...10).contains(x) && (16...29).contains(y) {
                if (17...19).contains(y) && (9...10).contains(x) { return 0xD8D0C8 }
                if noise(x, y, 4) < 0.12 { return 0x545448 }
                return pick(bark, x, y, 5)
            }
            // 细长的手臂，垂到膝盖，指头是几根小枝
            if (16...33).contains(y) && [3, 4, 11, 12].contains(x) {
                let c = pick(bark, x, y, 6)
                return x == 3 || x == 12 ? shade(c, 0.78) : c
            }
            if y == 34 && (x == 2 || x == 4 || x == 11 || x == 13) { return 0x302424 }
            // 两条腿，迈步时一条抬起一点；脚底是散开的根
            for (leg, c0) in [(0, 5), (1, 9)] {
                let bottom = 43 - (leg == step ? 2 : 0)
                if (c0...(c0 + 1)).contains(x) && (30...(bottom - 2)).contains(y) { return pick(bark, x, y, 7 + leg) }
                if y >= bottom - 1 && y <= bottom && ((c0 - 1)...(c0 + 2)).contains(x) {
                    if y == bottom && (x == c0 || x == c0 + 1) { return nil }
                    return 0x302424
                }
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x2A2E34, 0x343A40, 0x40464C, 0x50565A, 0x62686A])
        // 远处雾里的树：越远越淡
        for i in 0..<9 {
            let x = Int(noise(i, 0, 3) * Double(b.cols)), w = 6 + Int(noise(i, 1, 3) * 6)
            for y in 0..<g { for dx in 0..<w where dither(x + dx, y, 0.6) { b.set(x + dx, y, 0x3A3E44) } }
        }
        // 近处的苍白橡木：粗树干（树皮有竖纹），顶上一片灰绿的树冠
        let trunks: [(Double, Int)] = [(0.06, 24), (0.42, 16), (0.93, 20)]
        for (k, (cx, w)) in trunks.enumerated() {
            let x0 = Int(Double(b.cols) * cx) - w / 2
            for y in 0..<g { for dx in 0..<w {
                var c = pick(Self.bark, (x0 + dx) / 2, y / 3, 4 + k)
                if dx == 0 || dx == w - 1 { c = shade(c, 0.75) }
                b.set(x0 + dx, y, c)
            } }
            // 树根往两边散开
            for r in 0..<4 { b.fill(x0 - 3 + r, g - 4 + r, 2, 1, Self.bark[2]); b.fill(x0 + w + 1 - r, g - 4 + r, 2, 1, Self.bark[2]) }
        }
        // 树冠：盖住画面顶上
        let canopy = Int(Double(g) * 0.24)
        for x in 0..<b.cols {
            let h = canopy + Int(sin(Double(x) * 0.09) * 5 + noise(x / 4, 0, 6) * 7)
            for y in 0..<h {
                let c = ditherRamp(Self.paleLeaves, 1 - Double(y) / Double(h) * 0.9, x, y)
                b.set(x, y, noise(x, y, 7) < 0.1 ? shade(c, 0.8) : c)
            }
            // 苍白垂须：从树冠垂下来，长短不一
            if noise(x, 1, 8) > 0.82 {
                let len = 6 + Int(noise(x, 2, 8) * 22)
                for y in h..<(h + len) where noise(x, y, 9) > 0.15 { b.set(x, y, pick([0x8A948A, 0x6E786E, 0xA4ACA2], x, y, 10)) }
            }
        }
        // 嘎枝之心：嵌在左边的树干里，暗时是一块深色的树心，中间一道竖缝（亮光在动态层）
        let hx = heartTree(b) - 6, hy = heartY(b)
        for y in 0..<12 { for x in 0..<12 {
            let edge = x == 0 || y == 0 || x == 11 || y == 11
            b.set(hx + x, hy + y, edge ? 0x241818 : pick([0x302424, 0x3C3024, 0x544848, 0x241818], x, y, 11))
        } }
        // 地面：苍白苔藓 → 泥土 → 深层
        Paint.strata(&b, from: g, top: [0x6E786E, 0x86907E, 0x5E685E, 0x9AA294], topRows: 5,
                     mid: [0x4A3A2E, 0x3E3026, 0x54422F], midRows: 26, deep: [0x3A3A3E, 0x2E2E32], seed: 12)
        // 眼眸花的茎和叶（花在动态层）
        for x in stride(from: 14, to: b.cols - 4, by: 1) where noise(x, 0, 13) > 0.9 {
            b.fill(x, g - 4, 1, 4, 0x3C3030)
            b.set(x - 1, g - 2, 0x544848); b.set(x + 1, g - 3, 0x544848)
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        let px = Int(Double(b.cols) * 0.76)
        // 夜里睁开的眼眸花：灰色花瓣中间一点橙光，一明一暗
        for x in stride(from: 14, to: b.cols - 4, by: 1) where noise(x, 0, 13) > 0.9 {
            let glow = sin(t * 1.6 + Double(x) * 0.7) > 0 ? 0xFF9A2E : 0xC8642A
            b.set(x - 1, g - 6, 0x9C9090); b.set(x + 1, g - 6, 0x9C9090); b.set(x, g - 7, 0xA89CA8)
            b.set(x, g - 6, UInt32(glow)); b.set(x, g - 5, 0x786C78)
        }
        // 地面上缓缓飘的雾
        for y in (g - 16)..<(g + 2) {
            let k = 1 - Double(abs(y - (g - 6))) / 10
            guard k > 0 else { continue }
            for x in 0..<b.cols where noise((x + Int(t * 3)) / 5, y / 2, 21) * k > 0.42 && dither(x, y, 0.35) { b.set(x, y, 0x7A8282) }
        }

        // 时间线（12 秒一轮）
        let p = t.truncatingRemainder(dividingBy: 12)
        let a = Double(heartTree(b) + 16), c = Double(px - 26), m = (a + c) / 2
        var cx = a
        var moving = false
        switch p {
        case ..<2: cx = a
        case ..<3.6: cx = a + (m - a) * (p - 2) / 1.6; moving = true
        case ..<5.5: cx = m
        case ..<7: cx = m + (c - m) * (p - 5.5) / 1.5; moving = true
        case ..<11.4: cx = c
        default: cx = a   // 粒子飞回心脏以后，从树边重新冒出来
        }
        // 嘎枝之心：嘎枝在外面时中间那道缝发橙光，粒子飞回来时更亮
        let hx = heartTree(b) - 6, hy = heartY(b)
        let returning = (9.4...11.4).contains(p)
        let beat = returning ? 1.0 : (sin(t * 2.2) > 0.2 ? 0.7 : 0.35)
        for y in 2..<10 {
            let col: UInt32 = beat > 0.8 ? 0xFFC04A : (beat > 0.5 ? 0xFF8A1E : 0xA8501E)
            b.set(hx + 5, hy + y, col); b.set(hx + 6, hy + y, y % 3 == 0 ? shade(col, 0.8) : col)
        }
        // 嘎枝：看着它时僵住；被打以后化成树脂粒子飞回心脏
        if p < 9.4 || p > 11.4 {
            var sprite = Self.creaking(awake: !moving, step: moving ? Int(t * 5) % 2 : 0)
            if (8.6...9.4).contains(p) {
                // 挨打：闪白
                let k = 1 - (p - 8.6) / 0.8
                sprite = Sprite(width: sprite.width, height: sprite.height) { x, y in
                    let v = sprite.px[y * sprite.width + x]
                    return v == 0 ? nil : (dither(x, y, k * 0.6) ? 0xF4E8D8 : v & 0xFFFFFF)
                }
            }
            b.blit(sprite, x: Int(cx), bottom: g - 1)
        }
        if returning {
            let q = (p - 9.4) / 2
            for i in 0..<16 {
                let f = max(0, min(1, q * 1.6 - Double(i) * 0.04))
                guard f > 0 && f < 1 else { continue }
                let x = c + 8 + (Double(hx + 6) - c - 8) * f
                let y = Double(g - 22) + (Double(hy + 6) - Double(g - 22)) * f - sin(f * .pi) * 14 + sin(Double(i) * 2.1) * 2
                b.set(Int(x), Int(y), i % 3 == 0 ? 0xFFC04A : 0xFF8A1E)
            }
        }
        // 玩家：不看嘎枝的时候它才会动；挨到跟前时挥手打它一下
        var pose = Player.idle(t, props: PlayerProps(), phase: 3)
        pose.lookBack = (2...3.6).contains(p) || (5.5...7).contains(p)
        if (8.2...9.2).contains(p) {
            let k = (p - 8.2) / 1.0
            pose.armAngle = k < 0.4 ? 1.8 * k / 0.4 : 1.8 * (1 - (k - 0.4) / 0.6)
        }
        Player.draw(&b, look: cast.player, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.21.5 Spring to Life：萤火虫与新的动物变种

/// 1.21.5 让主世界更有生气：萤火虫灌木、野花、落叶堆、会飘落的树叶，还有按气候区分的猪、牛、鸡变种。
/// 黄昏的森林边上：萤火虫在灌木丛边一闪一闪，树叶慢慢飘落；温暖型的鸡在啄地、时不时下一颗棕色的蛋，
/// 寒冷型的猪（一身奶油色的卷毛）慢悠悠地走来走去；玩家手里捧着一束野花
struct SpringToLife: DotScene {
    let id = "1.21.5"
    let background: UInt32 = 0x2A2850

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 温暖型的鸡（朝右，12×12，约 0.7 格高）：橙黄的身子、棕色的鸡冠和喙、红色的肉垂；peck 时低头
    static func warmChicken(peck: Bool) -> Sprite {
        let body: [UInt32] = [0xE8A848, 0xD89438, 0xF0BC5C]
        return Sprite(width: 13, height: 12) { x, y in
            // 身子 8 长 6 高，尾巴翘起一点
            if (0...7).contains(x) && (4...9).contains(y) {
                if y == 9 || x == 0 { return 0xB87428 }
                if (2...5).contains(x) && (6...7).contains(y) { return 0xC88430 }   // 翅膀
                return pick(body, x, y, 3)
            }
            if x == 0 && y == 3 { return 0xB87428 }
            // 头：4 宽 6 高，低头时整个往下、往前
            let hy = peck ? y - 3 : y, hx = peck ? x - 1 : x
            if (6...9).contains(hx) && (0...5).contains(hy) {
                if hy == 2 && hx == 8 { return 0x1E1E1D }
                return hy == 0 ? 0xF4D88A : 0xF0C878
            }
            if (10...11).contains(hx) && (2...3).contains(hy) { return 0x6A3A2A }   // 喙
            if hx == 10 && (4...5).contains(hy) { return 0xD8341F }                 // 肉垂
            // 腿
            if (x == 3 || x == 5) && (10...11).contains(y) { return 0xA06A50 }
            if y == 11 && (x == 2 || x == 6) { return 0xA06A50 }
            return nil
        }
    }

    /// 寒冷型的猪（朝右，18×12）：奶油色的卷毛，头上的毛垂到眼睛，粉褐色的鼻子和蹄子；step 为迈步
    static func coldPig(step: Int) -> Sprite {
        let wool: [UInt32] = [0xF0DCB0, 0xE4CC9C, 0xF8E8C4, 0xD8BC88]
        return Sprite(width: 18, height: 12) { x, y in
            if (0...11).contains(x) && (1...8).contains(y) {
                if y == 8 { return 0xC8AC78 }
                return pick(wool, x / 2, y, 4)
            }
            // 头 6×7，鼻子往前凸
            if (11...16).contains(x) && (0...6).contains(y) {
                if y == 3 && x == 14 { return 0x1E1E1D }
                if y <= 2 { return pick(wool, x, y, 5) }
                return 0xE8C8A0
            }
            if x == 17 && (4...5).contains(y) { return 0xB07A68 }
            if x == 16 && (4...5).contains(y) { return 0xC8907A }
            // 四条腿，迈步时前后两对交替抬起
            for (i, lx) in [1, 4, 8, 11].enumerated() where (lx...(lx + 1)).contains(x) {
                let up = (i % 2 == step) ? 1 : 0
                if (9...(11 - up)).contains(y) { return y == 11 - up ? 0x8A5A48 : 0xD8BC88 }
            }
            return nil
        }
    }

    /// 一小束野花（拿在手里，不转）
    static let bouquet = HeldItem(sprite: Sprite([
        ".y.w.", "yOyWw", ".yoW.", "..g..", ".gGg.", "..G..", "..G..",
    ], ["y": 0xFCCC30, "O": 0xF0B424, "o": 0xE49C24, "w": 0xF0FCFC, "W": 0xCCE4E4, "g": 0x48783C, "G": 0x3C6C30]), swings: false)

    /// 萤火虫灌木（14×12）：橄榄绿的叶子，叶尖发黄
    static let fireflyBush = Sprite(width: 14, height: 12) { x, y in
        let r = pow(Double(x) - 6.5, 2) / 49 + pow(Double(y) - 12, 2) / 150
        guard r < 1, noise(x, y, 31) > 0.18 else { return nil }
        return y < 4 && noise(x, y, 32) > 0.5 ? 0x9C7830 : pick([0x3C4824, 0x545430, 0x6C6C3C], x, y, 33)
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x2A2858, 0x4A3A78, 0x8A5A8A, 0xD8786A, 0xF4A462, 0xF8D088])
        // 快落山的太阳
        let sx = Int(Double(b.cols) * 0.52), sy = g - 14
        for y in (sy - 12)...(sy + 12) { for x in (sx - 12)...(sx + 12) where abs(x - sx) <= 12 && abs(y - sy) <= 12 {
            b.set(x, y, abs(x - sx) > 9 || abs(y - sy) > 9 ? 0xFCC86A : 0xFFE89A)
        } }
        // 远处的丘陵剪影
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.025 + 1) * 0.5 + 0.5) * 14 + noise(x / 7, 0, 2) * 5) + 4
            for y in (g - h)..<g { b.set(x, y, dither(x, y, 0.5) ? 0x5A4A6A : 0x6A5070) }
        }
        // 橡树：树干和树冠，树下是落叶堆
        for (k, cx) in [0.05, 0.36, 0.95].enumerated() {
            let x = Int(Double(b.cols) * cx), h = 40 + k * 4
            b.fill(x - 2, g - h, 5, h, 0x6B5133)
            for y in stride(from: g - h, to: g, by: 4) { b.set(x - 1 + (y / 4) % 3, y, 0x5A4228) }
            for dy in -22...4 { for dx in -16...16 {
                let r = Double(dx * dx) / 256 + Double(dy * dy) / 200
                guard r < 1, noise(x + dx, dy, 34 + k) > 0.1 else { continue }
                let c = ditherRamp([0x2E5A22, 0x3E7A2C, 0x4A8A34, 0x6AA040], 1 - r * 0.8 - Double(dy + 22) / 80, x + dx, dy)
                b.set(x + dx, g - h + dy, c)
            } }
            for dx in -14...14 where noise(x + dx, 0, 36) > 0.35 { b.set(x + dx, g - 1, pick([0x604824, 0x785430, 0x603C24], dx, k, 37)) }
        }
        // 草地 → 泥土；地上一丛丛野花
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35, 0x76B850], topRows: 4,
                     mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30, deep: [0x7F7F7F, 0x6E6E6E], seed: 38)
        for x in 0..<b.cols where noise(x, 0, 39) > 0.72 {
            b.set(x, g - 1, 0x48783C)
            b.set(x, g - 2, pick([0xFCCC30, 0xF0FCFC, 0xE49C24, 0xFCCC30], x, 0, 40))
        }
        // 萤火虫灌木
        for cx in [0.18, 0.47, 0.64] { b.blit(Self.fireflyBush, x: Int(Double(b.cols) * cx), bottom: g - 1) }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 萤火虫：在灌木附近绕小圈，忽明忽暗
        for i in 0..<48 {
            let home = [0.18, 0.47, 0.64, 0.3, 0.84][i % 5]
            let x = Int(Double(b.cols) * home) + 7 + Int(sin(t * (0.5 + noise(i, 0, 41) * 0.6) + Double(i)) * (8 + noise(i, 1, 41) * 14))
            let y = g - 6 - Int(noise(i, 2, 41) * 34) + Int(cos(t * 0.7 + Double(i) * 1.3) * 5)
            let on = sin(t * (2 + noise(i, 3, 41) * 2) + Double(i) * 2.3)
            if on > 0.1 { b.set(x, y, on > 0.6 ? 0xFCFFA0 : 0xD8F05A) }
            if on > 0.75 { b.set(x + 1, y, 0xE8F870); b.set(x, y - 1, 0xE8F870) }
        }
        // 树叶慢慢飘落
        Paint.falling(&b, t: t, count: 14, colors: [0x4A8A34, 0x6AA040, 0x785430], top: 10, bottom: g, speed: 0.035, seed: 42)

        // 温暖型的鸡：啄地，每 9 秒下一颗蛋
        let cx = Int(Double(b.cols) * 0.1)
        let peck = sin(t * 2.6) > 0.55
        let p = t.truncatingRemainder(dividingBy: 9)
        let hop = (6.0...6.3).contains(p) ? 2 : 0
        b.blit(Self.warmChicken(peck: peck), x: cx, bottom: g - 1 - hop)
        if p > 6.2 {
            // 棕色的蛋：落下来停在鸡屁股后面
            let ey = min(g - 1, g - 6 + Int((p - 6.2) * 20))
            b.blit(Sprite([".oo.", "oOOo", "oOOo", ".oo."], ["o": 0x9A6A3A, "O": 0xC08A54]), x: cx - 4, bottom: ey)
        }

        // 寒冷型的猪：在中间慢慢踱步，走到头掉头
        let span = Double(b.cols) * 0.2, x0 = Double(b.cols) * 0.26
        let q = (t * 0.06).truncatingRemainder(dividingBy: 2)
        let forward = q < 1
        let walk = forward ? q : 2 - q
        let pigX = x0 + span * walk
        let pause = abs(sin(t * 0.6)) < 0.25
        b.blit(Self.coldPig(step: pause ? 2 : Int(t * 4) % 2), x: Int(pigX), bottom: g - 1, flip: !forward)

        let props = PlayerProps(held: Self.bouquet)
        Player.draw(&b, look: cast.player, props: props, pose: Player.idle(t, props: props, phase: 5), x: Int(Double(b.cols) * 0.76), feet: g - 1, t: t)
    }
}

// MARK: - 1.21.6 Chase the Skies：骑着快乐恶魂飞

/// 1.21.6 加入了快乐恶魂（4 格见方的白色恶魂，性情温顺，能载 4 个人）、恶魂幼体、干枯的恶魂和挽具。
/// 云海上空：快乐恶魂戴着挽具飞，被人骑着时护目镜放下来盖住眼睛；玩家和作者站在它的背上，
/// 小小的恶魂幼体跟在后面，云一层层往后飘；玩家时不时一拳把作者打下恶魂，作者过一会儿又从天上掉回来
struct ChaseTheSkies: DotScene {
    let id = "1.21.6"
    let background: UInt32 = 0x5288E6

    private func cloudTop(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.8) }

    /// 快乐恶魂（正面，64×64 加触手；贴图 16×16 放大 4 倍，每个贴图像素占 4×4 个点）：
    /// 白色身子带几道浅灰的裂纹，弯弯的嘴在笑；挽具在头顶是一块棕色的皮鞍，两侧垂下白色的带子（中间一道橙线），
    /// 被骑着时护目镜放下来盖住眼睛。wiggle 让触手轮流摆动
    static func happyGhast(t: Double) -> Sprite {
        let white: [UInt32] = [0xF4F4F4, 0xECECEC, 0xF8F8F8, 0xE4E4E4]
        func texel(_ u: Int, _ v: Int) -> UInt32? {
            // 护目镜（放下来）：两个深棕色的镜框，浅蓝的镜片
            for gx in [2, 9] where (gx...(gx + 4)).contains(u) && (5...9).contains(v) {
                let frame = u == gx || u == gx + 4 || v == 5 || v == 9
                if frame { return 0x3C240C }
                return (u == gx + 1 && v == 6) ? 0xD8F4FC : 0x9CD8E8
            }
            if (7...8).contains(u) && v == 7 { return 0x543018 }
            if (u <= 1 || u >= 14) && v == 7 { return 0x543018 }
            // 笑着的嘴
            if v == 12 && (6...9).contains(u) { return 0x8A8A8A }
            if v == 11 && (u == 5 || u == 10) { return 0x8A8A8A }
            // 两侧垂下的挽具带子
            if (u == 0 || u == 15) && v <= 11 { return v % 4 == 2 ? 0xE8A020 : 0xC8C8C8 }
            return nil
        }
        return Sprite(width: 64, height: 78) { x, y in
            if y < 64 {
                let u = x / 4, v = y / 4
                if let c = texel(u, v) { return c }
                // 几道浅灰的裂纹
                let crack = (x - y / 2 == 40 && (8...30).contains(y)) || (x + y / 3 == 20 && (30...50).contains(y))
                if crack { return 0xC8C8C8 }
                var c = pick(white, u, v, 51)
                if y >= 60 || x >= 60 { c = shade(c, 0.86) }
                return c
            }
            // 触手：9 根里看得到 5 根，各自长短摆动
            for (i, u) in [1, 4, 7, 10, 13].enumerated() where (u * 4...(u * 4 + 5)).contains(x) {
                let len = 6 + Int((sin(t * 2.2 + Double(i) * 1.4) * 0.5 + 0.5) * 8)
                if y - 64 < len { return y - 64 == len - 1 ? 0xC8C8C8 : (x == u * 4 + 5 ? 0xD8D8D8 : 0xEAEAEA) }
            }
            return nil
        }
    }

    /// 快乐恶魂背上的皮鞍（64×5）
    static let saddle = Sprite(width: 64, height: 5) { x, y in
        if x < 2 || x > 61 { return y >= 2 ? 0x543018 : nil }
        if y == 0 { return x % 6 == 0 ? 0x6C3C24 : 0x8A5A30 }
        return y == 4 ? 0x543018 : (noise(x, y, 52) < 0.2 ? 0x6C3C24 : 0x784824)
    }

    /// 恶魂幼体（16×16 加触手）：白色的小方块，闭着眼睛在笑
    static func ghastling(t: Double) -> Sprite {
        Sprite(width: 16, height: 22) { x, y in
            if y < 16 {
                if y == 7 && ((3...5).contains(x) || (10...12).contains(x)) { return 0x8A8A8A }
                if y == 11 && (6...9).contains(x) { return 0x8A8A8A }
                if y == 10 && (x == 5 || x == 10) { return 0x8A8A8A }
                if (y == 9 || y == 10) && x == 14 { return 0xC84A4A }
                return y == 15 || x == 15 ? 0xDCDCDC : pick([0xF4F4F4, 0xECECEC], x, y, 53)
            }
            for (i, u) in [2, 7, 12].enumerated() where (u...(u + 1)).contains(x) {
                let len = 3 + Int((sin(t * 3 + Double(i) * 2) * 0.5 + 0.5) * 3)
                if y - 16 < len { return 0xE4E4E4 }
            }
            return nil
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let top = cloudTop(b)
        Paint.sky(&b, until: b.rows, [0x3A6ED8, 0x5288E6, 0x74A4F0, 0xA0C4F8, 0xD4E6FC])
        // 远处的云海：顶上一个个鼓包
        for x in 0..<b.cols {
            let bump = Int(abs(sin(Double(x) * 0.07)) * 7 + abs(sin(Double(x) * 0.19 + 1)) * 4 + noise(x / 5, 0, 54) * 3)
            for y in (top - bump)..<b.rows {
                let d = y - (top - bump)
                let c: UInt32 = d < 2 ? 0xFFFFFF : (d < 8 ? 0xEEF4FE : (dither(x, y, 0.5) ? 0xD4E2F8 : 0xE2ECFA))
                b.set(x, y, c)
            }
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        // 两层云往后飘，近的快、远的慢，看起来在往前飞
        Paint.clouds(&b, t: t * 3, maxY: Int(Double(b.rows) * 0.3), count: 4, color: 0xF4F8FF, shadow: 0xD5E1FB, seed: 55)
        Paint.clouds(&b, t: t * 9, maxY: Int(Double(b.rows) * 0.75), count: 3, color: 0xFFFFFF, shadow: 0xC8D8F0, seed: 56)
        // 风：几道很快的白线
        for i in 0..<7 {
            let y = 10 + Int(noise(i, 0, 57) * Double(b.rows - 30))
            let span = Double(b.cols + 40)
            let x = Int(span - (t * 120 + noise(i, 1, 57) * span).truncatingRemainder(dividingBy: span)) - 20
            for dx in 0..<(8 + i % 3 * 4) where dither(x + dx, y, 0.7) { b.set(x + dx, y, 0xFFFFFF) }
        }
        // 快乐恶魂：上下轻轻浮动
        let bob = Int((sin(t * 1.1) * 3).rounded())
        let gx = Int(Double(b.cols) * 0.5) - 32, top = Int(Double(b.rows) * 0.36) + bob
        b.blit(Self.happyGhast(t: t), x: gx, bottom: top + 77)
        b.blit(Self.saddle, x: gx, bottom: top + 2)
        // 恶魂幼体跟在后面
        let lb = Int((sin(t * 1.5 + 1) * 4).rounded())
        b.blit(Self.ghastling(t: t), x: Int(Double(b.cols) * 0.14), bottom: top + 60 + lb)
        // 作者和玩家站在背上（10 秒一轮）：玩家走过去一拳把作者打下去，作者翻下恶魂、穿过云层掉下去，
        // 过一会儿又从天上掉回鞍上，弹一下
        let p = t.truncatingRemainder(dividingBy: 10)
        let stand = top - 3
        var me = Player.idle(t, props: PlayerProps(), phase: 2)
        let approach = ramp(p, 1.6, 2.4) * (1 - ramp(p, 4.2, 5.2))
        me.dx = -Int(8 * approach)
        if (1.6...2.4).contains(p) || (4.2...5.2).contains(p) { me.walk = t * 9 }
        if (2.5...3.0).contains(p) {
            // 出拳：手往前一挥
            let q = (p - 2.5) / 0.5
            me.armAngle = q < 0.4 ? 1.7 * q / 0.4 : 1.7 * (1 - (q - 0.4) / 0.6)
            me.lookBack = false
        }
        var foe = Player.idle(t, props: PlayerProps(), phase: 9)
        var foeX = Double(gx + 14), foeFeet = Double(stand)
        if (2.75...6.5).contains(p) {
            // 被打中：变红，往左后方飞出去，过了恶魂的边缘就往下掉
            let q = p - 2.75
            foe.hurt = max(0, 1 - q / 0.3)
            foe.armAngle = 2.6 + sin(t * 18) * 0.4
            foeX -= q * 40
            foeFeet = Double(stand) - 18 * q + 40 * q * q
        } else if p > 8.2 {
            // 从天上掉回来，落在鞍上弹一下
            let q = p - 8.2
            foeFeet = q < 0.6 ? Double(stand) - (1 - q / 0.6) * Double(stand + 40) : Double(stand) - abs(sin((q - 0.6) * 9)) * 3 * max(0, 1 - (q - 0.6) / 0.8)
        } else if p > 6.5 {
            foeFeet = -100
        }
        if foeFeet > -60 && foeFeet < Double(b.rows + 40) {
            Player.draw(&b, look: cast.author, pose: foe, x: Int(foeX), feet: Int(foeFeet), t: t, facingRight: true)
        }
        Player.draw(&b, look: cast.player, pose: me, x: gx + 40, feet: stand, t: t)
    }
}

// MARK: - 1.21.9 The Copper Age：铜傀儡搬箱子

/// 1.21.9 加入了铜傀儡（会在铜箱子和普通箱子之间搬东西）、铜箱子、铜制工具与盔甲、铜火把（绿色火焰）和架子。
/// 一座铜顶的小仓库前：铜傀儡抱着东西在两个铜箱子之间来回搬，每趟都氧化一点（铜色 → 斑驳 → 锈蚀 → 氧化），
/// 完全氧化后变成雕像一动不动；穿着铜盔甲的玩家走过去用铜斧把锈刮掉，它又亮晶晶地动起来
struct CopperAge: DotScene {
    let id = "1.21.9"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 铜的四个氧化阶段：亮、中、暗、深
    static let stages: [[UInt32]] = [
        [0xE08A6C, 0xC06A50, 0x9C5440, 0x7A3E30],
        [0xB89070, 0xA07A5E, 0x84644C, 0x6A4E3C],
        [0x7AA884, 0x5E9070, 0x4E7A60, 0x3E6450],
        [0x5ABE9C, 0x48A486, 0x3A8A70, 0x2E6E5A],
    ]

    /// 铜傀儡（正面，12×22，约 1 格高加一根天线）：大方头上是铜棒天线和小球，两只发光的眼睛、长长的鼻子，
    /// 小身子、短手短腿。statue 时眼睛不亮；carrying 为抱着的东西
    static func golem(_ tones: [UInt32], statue: Bool, step: Int, carrying: UInt32?) -> Sprite {
        Sprite(width: 14, height: 22) { x, y in
            let hi = tones[0], mid = tones[1], dark = tones[2], deep = tones[3]
            if (5...6).contains(x) && (0...1).contains(y) { return hi }
            if x == 6 && (2...4).contains(y) { return mid }
            // 头 8×7
            if (3...10).contains(x) && (5...11).contains(y) {
                if y == 8 && (x == 4 || x == 9) { return statue ? deep : 0xF8D86A }
                if y == 8 && (x == 5 || x == 8) { return statue ? dark : 0xD8A84A }
                if (6...7).contains(x) && (8...11).contains(y) { return x == 7 ? dark : mid }
                if y == 5 || x == 3 { return hi }
                return x == 10 ? dark : mid
            }
            // 抱着的东西（挡在身前）
            if let item = carrying, (5...8).contains(x) && (13...15).contains(y) { return y == 13 ? shade(item, 1.15) : item }
            // 身子与手
            if (4...9).contains(x) && (12...17).contains(y) { return y == 17 ? deep : (x == 4 ? hi : mid) }
            if (x == 2 || x == 3 || x == 10 || x == 11) && (12...(carrying == nil ? 16 : 14)).contains(y) { return x == 2 || x == 11 ? dark : mid }
            if carrying != nil && (x == 4 || x == 9) && (14...15).contains(y) { return dark }
            // 短腿，迈步时轮流抬起
            for (leg, c0) in [(0, 4), (1, 7)] where (c0...(c0 + 2)).contains(x) {
                let bottom = 21 - (leg == step ? 1 : 0)
                if (18...bottom).contains(y) { return y == bottom ? deep : dark }
            }
            return nil
        }
    }

    /// 铜箱子（14×13）：铜色的箱体，盖子上一圈深色的边，中间一个灰色的锁扣；open 时盖子掀起来
    static func chest(open: Bool) -> Sprite {
        let c: [UInt32] = [0xC06048, 0x9C543C, 0xD8786C, 0x904830]
        return Sprite(width: 14, height: 16) { x, y in
            let lidTop = open ? 0 : 3
            if (lidTop...(lidTop + 4)).contains(y) {
                if y == lidTop || x == 0 || x == 13 { return 0x783C30 }
                if (6...7).contains(x) && y >= lidTop + 2 && !open { return 0xB8B8B8 }
                return pick(c, x, y, 58)
            }
            if open && (5...7).contains(y) && (1...12).contains(x) { return 0x3A1C12 }
            if (8...15).contains(y) {
                if y == 15 || x == 0 || x == 13 || y == 8 { return 0x783C30 }
                if (6...7).contains(x) && y <= 10 { return 0xB8B8B8 }
                return pick(c, x, y, 59)
            }
            return nil
        }
    }

    static let copperAxe = HeldItem(sprite: Sprite([
        ".hHH.", "hHHHH", "hHHh.", "hHw..", "..w..", "..W..", "..w..", "..W..", "..w..",
    ], ["h": 0xC06048, "H": 0xE08A6C, "w": 0x6B4A2C, "W": 0x8A6238]))

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6])
        // 仓库：切制铜块的墙，铜顶上立着避雷针；墙上是架子和窗户
        let x1 = Int(Double(b.cols) * 0.52), wallTop = g - 58
        for y in wallTop..<g { for x in 0..<x1 {
            let bx = x / 16, by = (y - wallTop) / 16
            let stage = 2 + Int(noise(bx, by, 60) * 1.9)
            let tones = Self.stages[min(3, stage)]
            let lx = x % 8, ly = (y - wallTop) % 8
            var c = (lx == 0 || ly == 0) ? tones[1] : ((lx == 7 || ly == 7) ? tones[3] : tones[2])
            if lx == 1 && ly == 1 { c = tones[0] }
            if noise(x, y, 61) < 0.04 { c = Self.stages[1][2] }
            b.set(x, y, c)
        } }
        // 屋檐和避雷针
        b.fill(0, wallTop - 4, x1 + 6, 4, Self.stages[1][2])
        b.fill(0, wallTop - 5, x1 + 6, 1, Self.stages[1][0])
        let rod = Int(Double(b.cols) * 0.3)
        b.fill(rod, wallTop - 24, 2, 20, 0xC06A50)
        b.fill(rod - 1, wallTop - 26, 4, 3, 0xE08A6C)
        // 窗户
        for wx in [0.06, 0.38] {
            let x = Int(Double(b.cols) * wx)
            b.fill(x, wallTop + 10, 18, 14, 0x3A2A22)
            b.fill(x + 1, wallTop + 11, 16, 12, 0x9CC8E8)
            b.fill(x + 8, wallTop + 11, 1, 12, 0x3A2A22); b.fill(x + 1, wallTop + 17, 16, 1, 0x3A2A22)
        }
        // 架子（1.21.9）：一块木板上摆着三样东西
        let sx = Int(Double(b.cols) * 0.17)
        b.fill(sx, wallTop + 30, 36, 3, 0x8A6238); b.fill(sx, wallTop + 33, 36, 1, 0x5E3E22)
        b.blit(Sprite(["..c..", ".gGg.", "gGGGg", "gGWGg", ".ggg."], ["c": 0x8A6238, "g": 0xB8D8F0, "G": 0xD84A8A, "W": 0xF8B8D8]), x: sx + 4, bottom: wallTop + 29)
        b.blit(Sprite(["..IIII", ".IiiiI", "IIIIII"], ["I": 0xD8D8D8, "i": 0xF0F0F0]), x: sx + 15, bottom: wallTop + 29)
        b.blit(Sprite(["...o", "..oo", ".oO.", "wO..", "w..."], ["o": 0xE08A6C, "O": 0xC06048, "w": 0x6B4A2C]), x: sx + 27, bottom: wallTop + 29)
        // 地面：草 → 泥土
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35], topRows: 4,
                     mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30, deep: [0x7F7F7F, 0x6E6E6E], seed: 62)
        // 两支铜火把的木棍（火焰在动态层）
        for fx in [0.03, 0.5] { b.fill(Int(Double(b.cols) * fx), wallTop + 36, 2, 9, 0x6B5133) }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g - 70, count: 3)
        let wallTop = g - 58
        // 铜火把：绿色的火
        for fx in [0.03, 0.5] {
            Paint.flame(&b, x: Int(Double(b.cols) * fx) - 1, bottom: wallTop + 35, width: 4, height: 5, t: t + fx * 10,
                        palette: [0x3E9A3A, 0x5AC85A, 0x9CF07A, 0xE4FFC8])
        }

        // 时间线（30 秒一轮）：4 趟搬运（每趟氧化一级），然后变成雕像，玩家走过去刮锈
        let p = t.truncatingRemainder(dividingBy: 30)
        let ax = Int(Double(b.cols) * 0.08), bx = Int(Double(b.cols) * 0.62)
        b.blit(Self.chest(open: false), x: ax, bottom: g - 1)
        let from = Double(ax + 16), to = Double(bx - 15)
        // 最后一趟放完东西后走到箱子右边，在那里变成雕像（离玩家近，好刮锈）
        let rest = Double(bx + 18)
        let trip = Int(p / 5), tp = p.truncatingRemainder(dividingBy: 5)
        var gx = rest, step = 0, carrying: UInt32? = nil, flip = false, openB = false
        var stage = min(3, trip)
        let statue = trip >= 4
        if !statue {
            let items: [UInt32] = [0xD8D8D8, 0xF5D74A, 0x4AEDD9, 0xE08A6C]
            switch tp {
            case ..<2.2: gx = from + (to - from) * tp / 2.2; carrying = items[trip]; step = Int(t * 5) % 2
            case ..<2.8: gx = to; openB = true
            default:
                if trip == 3 {
                    // 绕到箱子前面，往右走到停下的地方
                    gx = to + (rest - to) * min(1, (tp - 2.8) / 1.6); step = tp < 4.4 ? Int(t * 5) % 2 : 0
                } else {
                    gx = to - (to - from) * (tp - 2.8) / 2.2; flip = true; step = Int(t * 5) % 2
                }
            }
        }
        // 刮锈：玩家走过去，挥两下斧头，铜傀儡一级级变回铜色
        let props = PlayerProps(held: Self.copperAxe, armor: .full(.copper))
        var pose = Player.idle(t, props: props, phase: 4)
        let px = Int(Double(b.cols) * 0.8)
        if statue {
            let sp = p - 20
            let walk = ramp(sp, 1, 2.5) * (1 - ramp(sp, 8, 9.5))
            pose.dx = -Int((Double(px - Int(rest) - 26) * walk).rounded())
            if (1...2.5).contains(sp) || (8...9.5).contains(sp) { pose.walk = t * 9 }
            for (k, at) in [3.0, 4.2, 5.4].enumerated() where (at...(at + 0.6)).contains(sp) {
                let q = (sp - at) / 0.6
                pose.armAngle = q < 0.35 ? 0.3 + 1.6 * (q / 0.35) : 1.9 - 1.6 * ((q - 0.35) / 0.65)
                // 刮下来的碎屑
                if q > 0.3 {
                    for i in 0..<6 {
                        let f = (q - 0.3) / 0.7
                        b.set(Int(rest) + 8 + i * 2 - Int(f * Double(i) * 3), g - 14 - Int(sin(f * .pi) * Double(4 + i)), k == 2 ? 0xFFFFFF : Self.stages[3 - k][0])
                    }
                }
            }
            stage = sp < 3.3 ? 3 : (sp < 4.5 ? 2 : (sp < 5.7 ? 1 : 0))
            if sp > 6 { stage = 0 }
        }
        b.blit(Self.chest(open: openB), x: bx, bottom: g - 1)
        b.blit(Self.golem(Self.stages[stage], statue: statue && p - 20 < 5.7, step: step, carrying: carrying), x: Int(gx), bottom: g - 1, flip: flip)
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 1.21.11 Mounts of Mayhem：沙漠里的骆驼尸壳

/// 1.21.11 加入了长矛（带冲刺附魔）、鹦鹉螺、僵尸马、骆驼尸壳和焦骸（沙漠里的骷髅变种），焦骸骑着骆驼尸壳出现。
/// 黄昏的沙漠：焦骸骑着骆驼尸壳从左边走过来；玩家拿着铁长矛，看准时机往前一冲刺，把骆驼尸壳顶退，
/// 它掉头走开，过一会儿又走回来
struct MountsOfMayhem: DotScene {
    let id = "1.21.11"
    let background: UInt32 = 0x3A2E6A

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 骆驼尸壳（朝右，36×38，约 2.4 格高）：深褐色的干皮，驼峰上一块破鞍，肚子上露出一道道肋骨，
    /// 细长的脖子往上弯，头往前伸。step 为迈步
    static func camelHusk(step: Int) -> Sprite {
        let hide: [UInt32] = [0x3C3024, 0x302418, 0x4A3C2A, 0x241818]
        return Sprite(width: 36, height: 38) { x, y in
            // 头（往前伸的长脸）
            if (25...34).contains(x) && (0...5).contains(y) {
                if y == 2 && x == 29 { return 0xD8C890 }
                if x >= 32 && y >= 3 { return 0x241818 }
                return pick(hide, x, y, 63)
            }
            if (27...28).contains(x) && y == 0 { return nil }
            // 脖子：从胸前往上弯，比驼峰高出一截
            if (24...28).contains(x) && (5...18).contains(y) { return pick(hide, x, y, 64) }
            // 驼峰和破鞍
            if (9...19).contains(x) && (10...13).contains(y) { return y == 10 ? 0x5A4A36 : (y >= 12 ? 0x6E5A3E : 0x5A4A36) }
            // 身子
            if (3...26).contains(x) && (14...24).contains(y) {
                if (16...22).contains(y) && x % 4 == 1 && (9...21).contains(x) && y != 19 { return 0x7A6A4E }   // 肋骨
                if y == 24 { return 0x241818 }
                return pick(hide, x, y, 65)
            }
            if (1...2).contains(x) && (15...21).contains(y) { return 0x302418 }   // 尾巴
            // 四条细长的腿
            for (i, lx) in [3, 7, 19, 23].enumerated() where (lx...(lx + 3)).contains(x) {
                let up = i % 2 == step ? 2 : 0
                if (25...(37 - up)).contains(y) { return y >= 36 - up ? 0x18180C : pick(hide, x, y, 66 + i) }
            }
            return nil
        }
    }

    /// 焦骸（1.21.11）：沙黄色的骷髅，头上的骨头发灰，深色的眼窝，瘦得只剩骨头的四肢
    static let parched = PlayerLook(
        headFront: Sprite(["TTTTTTTT", "TtTTTtTT", "TTTTTTTT", "TkkTTkkT", "TkkTTkkT", "TTTggTTT", "TgkgkgkT", "tTTTTTTt"],
                          ["T": 0x9C9060, "t": 0x847848, "k": 0x302418, "g": 0x6A6A5A]),
        headSide: Sprite(["TTTt", "TTTt", "TTtt", "TTTt", "TTTt", "TtTt", "TTtt", "tttt"], ["T": 0x847848, "t": 0x6C603C]),
        bodyFront: Sprite(["TTTTTTTT", "dTkTTkTd", "dTTTTTTd", "dTkTTkTd", "dTTTTTTd", "ddTkkTdd", "dddTTddd", "dddTTddd", "ddTTTTdd", "dTtTTtTd", "dTTTTTTd", "dddddddd"],
                          ["T": 0x9C9060, "t": 0x786C48, "k": 0x302418, "d": 0x54482E]),
        bodySide: Sprite(Array(repeating: "Tt", count: 12), ["T": 0x847848, "t": 0x6C603C]),
        nearArm: Sprite(Array(repeating: "dTTdd", count: 11) + ["dttdd"], ["T": 0x9C9060, "t": 0x786C48, "d": 0x54482E]),
        farArm: Sprite(Array(repeating: "dTd", count: 12), ["T": 0x786C48, "d": 0x4A3E28]),
        legs: Sprite(Array(repeating: "dTTdTTTdtd", count: 10) + ["dggdgggdgd", "dggdgggdgd"], ["T": 0x9C9060, "t": 0x786C48, "d": 0x54482E, "g": 0x3C4824]))

    /// 铁长矛（竖着画，矛尖朝上；比剑长得多）
    static let ironSpear = HeldItem(sprite: Sprite([
        "..l..", ".lLl.", ".LML.", ".LML.", "..M..", ".bBb.", "..w..",
    ] + Array(repeating: "..W..", count: 12).enumerated().flatMap { i, r in i % 3 == 0 ? [r, "..w.."] : [r] }
      + ["..W..", "..w..", "..W.."],
    ["l": 0xF0F0F0, "L": 0xD8D8D8, "M": 0xA0A0A0, "b": 0x604818, "B": 0x846024, "w": 0x604818, "W": 0x846024]))

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x2E2660, 0x5A3A78, 0x9A4A72, 0xD8705A, 0xF4A85A, 0xF8D890])
        // 远处的沙丘，两层
        for (layer, (amp, base, col)) in [(10.0, 0.22, UInt32(0xC88A5A)), (7.0, 0.1, UInt32(0xE0A86A))].enumerated() {
            for x in 0..<b.cols {
                let h = Int(Double(g) * base + (sin(Double(x) * (0.03 + 0.02 * Double(layer)) + Double(layer)) * 0.5 + 0.5) * amp)
                for y in (g - h)..<g { b.set(x, y, dither(x, y, 0.3) ? shade(col, 0.92) : col) }
            }
        }
        // 仙人掌和枯灌木
        for (k, cx) in [0.04, 0.55, 0.97].enumerated() {
            let x = Int(Double(b.cols) * cx), h = 18 + k * 5
            b.fill(x, g - h, 5, h, 0x3E7A2C)
            for y in stride(from: g - h + 1, to: g, by: 3) { b.set(x + 1, y, 0x2E5A22); b.set(x + 3, y + 1, 0x5DA03F) }
            if k != 1 { b.fill(x + 5, g - h + 6, 3, 2, 0x3E7A2C); b.fill(x + 7, g - h + 2, 2, 6, 0x3E7A2C) }
        }
        for cx in [0.2, 0.44, 0.68] {
            let x = Int(Double(b.cols) * cx)
            for (dx, dy) in [(0, 0), (1, -1), (-1, -1), (2, -2), (-2, -3), (0, -2), (3, -4), (-3, -4)] { b.set(x + dx, g - 1 + dy, 0x8A6238) }
        }
        // 沙地
        Paint.strata(&b, from: g, top: [0xDBCFA3, 0xE3D7AE, 0xCFC294, 0xD6C99B], topRows: 16,
                     mid: [0xD8C78E, 0xC9B67A, 0xD1BF85], midRows: 16, deep: [0xB5A26A, 0xA69360], seed: 67)
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 风吹起的沙粒
        Paint.falling(&b, t: t, count: 16, colors: [0xF4E4B8, 0xE8D49A], top: g - 30, bottom: g, speed: 0.12, seed: 68)

        // 时间线（9 秒一轮）：骆驼走过来 → 停下 → 玩家冲刺把它顶退 → 它掉头走开
        let p = t.truncatingRemainder(dividingBy: 9)
        let px = Int(Double(b.cols) * 0.76)
        let start = -40.0, stop = Double(px) - 70
        var cx = start, flip = false, walking = true, hurt = 0.0
        switch p {
        case ..<3: cx = start + (stop - start) * p / 3
        case ..<4.3: cx = stop; walking = false
        case ..<5.4:
            cx = stop - 8 * ramp(p, 4.3, 4.7); walking = false
            hurt = max(0, 1 - (p - 4.3) / 0.4)
        default: cx = stop - 8 - (stop - 8 - start) * (p - 5.4) / 3.6; flip = true
        }
        var camel = Self.camelHusk(step: walking || flip ? Int(t * 4) % 2 : 2)
        if hurt > 0 {
            let src = camel
            camel = Sprite(width: src.width, height: src.height) { x, y in
                let v = src.px[y * src.width + x]
                return v == 0 ? nil : (dither(x, y, hurt * 0.7) ? 0xC83A2A : v & 0xFFFFFF)
            }
        }
        let bob = (walking || flip) && Int(t * 4) % 2 == 0 ? 1 : 0
        b.blit(camel, x: Int(cx), bottom: g - 1, flip: flip)
        // 焦骸坐在驼峰上
        var rider = PlayerPose()
        rider.sitting = true
        rider.hurt = hurt
        Player.draw(&b, look: Self.parched, pose: rider, x: Int(cx) + (flip ? 14 : 12), feet: g - 19 - bob, t: t, facingRight: !flip)

        // 玩家：平端长矛往前冲刺
        let props = PlayerProps(held: Self.ironSpear)
        var pose = Player.idle(t, props: props, phase: 6)
        if (3.6...5.6).contains(p) {
            let aim = ramp(p, 3.6, 3.9) * (1 - ramp(p, 5.2, 5.6))
            pose.armAngle = 0.06 + 1.45 * aim
            // 让矛身转到水平、矛尖朝前（朝着骆驼）：总转角 = armAngle - π/2 + 0.45 + itemTilt ≈ -π/2
            pose.itemTilt = -1.95 * aim
            let dash = ramp(p, 4.0, 4.3) * (1 - ramp(p, 4.6, 5.4))
            pose.dx = -Int((Double(px) - stop - 56) * dash)
            if (4.0...4.3).contains(p) || (4.6...5.4).contains(p) { pose.walk = t * 14 }
            // 冲刺扬起的沙尘
            if (4.0...4.8).contains(p) {
                for i in 0..<10 {
                    let f = (p - 4.0) / 0.8
                    b.set(px + 12 + pose.dx + i * 2 + Int(f * 6), g - 1 - Int(sin(f * .pi + Double(i)) * 3 + 2), i % 2 == 0 ? 0xF4E4B8 : 0xD8C78E)
                }
            }
        }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 26.1 Tiny Takeover：小动物们

/// 26.1 给几乎所有幼年生物换上了自己的模型（圆滚滚的大脑袋、小身子），还加入了金蒲公英——喂给幼崽，它就不再长大。
/// 晴天的草地上：方块小鸡、小猪、小牛、小狼蹦蹦跳跳；玩家拿着金蒲公英，喂给跑到跟前的小鸡，金色的星星冒出来
struct TinyTakeover: DotScene {
    let id = "26.1"
    let background: UInt32 = 0x6F98EC

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.66) }

    /// 小鸡（朝右，10×10）：一个黄色的小方块，大黑眼睛，棕色的小喙，两根细腿
    static let chick = Sprite([
        "YYYYYYYY..",
        "YYYYYYYY..",
        "YYYYYkYY..",
        "YYYYYkYbb.",
        "YYYYYYYbB.",
        "yYYYYYYY..",
        "yyYYYYYY..",
        "yyyyyyyy..",
        "..l..l....",
        ".ll.ll....",
    ], ["Y": 0xFCD830, "y": 0xCC900C, "k": 0x1E1E1D, "b": 0x9A6A3A, "B": 0x845400, "l": 0xB08A4A])

    /// 小猪（朝右，13×10）：大头、小身子、短短的腿
    static let piglet = Sprite([
        "......PPPPPP.",
        "pPPPPPPPPPPP.",
        "pPPPPPPPkPPP.",
        "pPPPPPPPPPPnN",
        "pPPPPPPPPPPnN",
        "ppPPPPPPPPPP.",
        "ppppppPPPPPP.",
        ".hh..hh.hh...",
        ".hh..hh.hh...",
        ".dd..dd.dd...",
    ], ["P": 0xFCB4A8, "p": 0xE08A80, "k": 0x1E1E1D, "n": 0xF4A09A, "N": 0xB86A60, "h": 0xF0A098, "d": 0xB86A60])

    /// 小牛（朝右，16×14，对照 26.1 的新模型）：大方脑袋占了快一半，脸前面是灰色的大鼻头，两只小灰角、侧面一只耳朵；
    /// 黑褐色的身子带白斑，四条粗短的腿
    static let calf = Sprite([
        "..........h..h..",
        "........DDDDDDD.",
        "........DDDDDDDD",
        "......eDDWWDkwDD",
        "......eDDWWDkkDD",
        "BBBBBBBDDDDDDsSS",
        "BWWBBBBDDDDDDsSS",
        "BWWWBBBDDDDDDsnS",
        "BBWBBBBBDDDDDsSS",
        "bBBBBWWBBDDDDDD.",
        "bbBBBWBBBBBBBB..",
        ".LL.LL....LL.LL.",
        ".LL.LL....LL.LL.",
        ".dd.dd....dd.dd.",
    ], ["B": 0x302418, "b": 0x1E1610, "D": 0x3C3024, "W": 0xD8D8D8, "e": 0x241818, "h": 0x9C9C9C,
        "k": 0x0C0C0C, "w": 0xF0F0F0, "s": 0x9C9C9C, "S": 0x787878, "n": 0x3A3A3A, "L": 0x302418, "d": 0x180C0C])

    /// 小狼（朝右，13×9）：灰色的大头和竖着的耳朵，小身子，尾巴翘着
    static let pup = Sprite([
        ".......k..k..",
        ".......GGGGG.",
        "t......GGkGGs",
        ".tGGGGGGGGGsS",
        "..GGGGGGGGG..",
        "..gGGGGgGG...",
        "..gg.gg.gg...",
        "..gg.gg.gg...",
        "..dd.dd.dd...",
    ], ["G": 0xC8C8C8, "g": 0x9C9C9C, "k": 0x3A3A3A, "t": 0xA8A8A8, "s": 0xB49C84, "S": 0x3A3A3A, "d": 0x7A7A7A])

    /// 金蒲公英（拿在手里，不转）
    static let goldenDandelion = HeldItem(sprite: Sprite([
        ".WyW.", "yYOYy", ".yOy.", "..g..", ".gg..", "..g..", "..g..",
    ], ["W": 0xFCFCE4, "y": 0xE4C03C, "Y": 0xE4E454, "O": 0xA8600C, "g": 0x5A8A2E]), swings: false)

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        Paint.sky(&b, until: g, [0x5B87E0, 0x6F98EC, 0x86AAF2, 0xA5C1F6, 0xC8DCFA])
        // 远处的山和树
        for x in 0..<b.cols {
            let h = Int((sin(Double(x) * 0.028 + 2) * 0.5 + 0.5) * 20 + noise(x / 6, 0, 70) * 6)
            for y in (g - h)..<g { b.set(x, y, pick([0x5F8C4E, 0x547F45, 0x6A9757], x, y, 71)) }
        }
        for (k, cx) in [0.03, 0.97].enumerated() {
            let x = Int(Double(b.cols) * cx)
            b.fill(x - 2, g - 36, 4, 36, 0x6B5133)
            for dy in -20...6 { for dx in -14...14 where Double(dx * dx) / 196 + Double(dy * dy) / 180 < 1 && noise(x + dx, dy, 72 + k) > 0.1 {
                b.set(x + dx, g - 36 + dy, pick([0x3E7A2C, 0x4A8A34, 0x5DA03F], x + dx, dy, 73))
            } }
        }
        Paint.strata(&b, from: g, top: [0x5DA03F, 0x6DB34A, 0x4F8F35, 0x76B850], topRows: 4,
                     mid: [0x8A5A33, 0x6F4627, 0x9B6B3F], midRows: 30, deep: [0x7F7F7F, 0x6E6E6E], seed: 74)
        // 草地上的蒲公英和虞美人
        for x in 0..<b.cols where noise(x, 0, 75) > 0.8 {
            b.set(x, g - 1, 0x48783C); b.set(x, g - 2, noise(x, 1, 75) > 0.5 ? 0xFCE040 : 0xD8341F)
        }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        Paint.clouds(&b, t: t, maxY: g / 3, count: 4)
        let px = Int(Double(b.cols) * 0.76)
        // 小动物们：各自蹦着走，走到头掉头
        func wander(_ s: Sprite, x0: Double, span: Double, speed: Double, hopRate: Double, phase: Double) {
            let q = (t * speed + phase).truncatingRemainder(dividingBy: 2)
            let forward = q < 1
            let x = x0 + span * (forward ? q : 2 - q)
            let hop = Int(max(0, sin(t * hopRate + phase * 5)) * 3)
            b.blit(s, x: Int(x), bottom: g - 1 - hop, flip: !forward)
        }
        wander(Self.calf, x0: Double(b.cols) * 0.08, span: Double(b.cols) * 0.14, speed: 0.05, hopRate: 3, phase: 0.3)
        wander(Self.piglet, x0: Double(b.cols) * 0.26, span: Double(b.cols) * 0.16, speed: 0.07, hopRate: 5, phase: 1.1)
        // 小狼追着自己的尾巴转圈
        let spin = Int(t * 2.5) % 2 == 0
        b.blit(Self.pup, x: Int(Double(b.cols) * 0.46), bottom: g - 1 - (sin(t * 5) > 0.6 ? 1 : 0), flip: spin)

        // 小鸡：蹦到玩家跟前，被喂金蒲公英，冒出金色的星星，然后蹦回去
        let p = t.truncatingRemainder(dividingBy: 10)
        let home = Double(b.cols) * 0.56, near = Double(px - 16)
        var cx = home
        switch p {
        case ..<2: cx = home
        case ..<3.5: cx = home + (near - home) * ease((p - 2) / 1.5)
        case ..<7: cx = near
        case ..<8.5: cx = near - (near - home) * ease((p - 7) / 1.5)
        default: cx = home
        }
        let moving = (2...3.5).contains(p) || (7...8.5).contains(p)
        let hop = moving ? Int(abs(sin(t * 10)) * 3) : (sin(t * 4) > 0.8 ? 1 : 0)
        b.blit(Self.chick, x: Int(cx), bottom: g - 1 - hop, flip: (7...8.5).contains(p))
        if (4.2...7).contains(p) {
            for i in 0..<9 {
                let a = Double(i) / 9 * 2 * .pi + t * 2
                let r = 6 + (p - 4.2) * 3
                let x = Int(cx) + 5 + Int(cos(a) * r), y = g - 8 - Int(sin(a) * r * 0.6) - Int((p - 4.2) * 2)
                if sin(t * 9 + Double(i)) > -0.2 { b.set(x, y, i % 2 == 0 ? 0xFCE040 : 0xFFF6B0) }
            }
        }
        // 玩家：小鸡跑过来时把金蒲公英递下去
        let props = PlayerProps(held: Self.goldenDandelion)
        var pose = Player.idle(t, props: props, phase: 7)
        if (3.4...5).contains(p) {
            let k = ramp(p, 3.4, 3.8) * (1 - ramp(p, 4.6, 5))
            pose.armAngle = 0.9 * k
            pose.headDip = k > 0.5 ? 1 : 0
            pose.itemUp = 0
        }
        Player.draw(&b, look: cast.player, props: props, pose: pose, x: px, feet: g - 1, t: t)
    }
}

// MARK: - 26.4 冰洞与冻尸

/// 26.4（快照）加入了冰洞：蓝冰的洞顶垂着冰锥，洞里长着发光的冰晶；还有冻尸（在细雪里待久了的僵尸）、冰冻效果。
/// 冰洞里：冻尸在左边，往玩家这边扔冰球；玩家举盾挡住，冰球碎成冰碴；洞顶的冰锥时不时掉下来摔碎
struct IceCaves: DotScene {
    let id = "26.4"
    let background: UInt32 = 0x0A1430

    private func ground(_ b: DotBuffer) -> Int { Int(Double(b.rows) * 0.68) }
    private func ceiling(_ b: DotBuffer, _ x: Int) -> Int {
        Int(Double(b.rows) * 0.14 + abs(sin(Double(x) * 0.05)) * 8 + noise(x / 6, 0, 80) * 6)
    }

    /// 冻尸：青灰色的冻僵的皮肤，头顶、肩膀和脚上结着白霜，深蓝的上衣，破破烂烂的棕裤子
    static let frostbite = PlayerLook(
        headFront: Sprite(["WWwWWwWW", "WSSWSSWS", "SSSSSSSS", "SSSSSSSS", "SkrSSrkS", "SSSSSSSS", "SSsddsSS", "sSSSSSSs"],
                          ["W": 0xD8ECEC, "w": 0x9CB4B4, "S": 0x609090, "s": 0x4A7878, "k": 0x302418, "r": 0x6A3A2A, "d": 0x3C5C5C]),
        headSide: Sprite(["WWWw", "SSWs", "SSSs", "SSSs", "SSSs", "SSSs", "SSss", "ssss"], ["W": 0xC8DCDC, "w": 0x9CB4B4, "S": 0x548484, "s": 0x426E6E]),
        bodyFront: Sprite(["WWBBBBWW"] + Array(repeating: "BBBbBBBB", count: 6) + ["BBSBBbBB", "BbSSBBBB", "BBBBBbBB", "bBBBBBBb", "bbbbbbbb"],
                          ["W": 0xD8ECEC, "B": 0x2E5A7A, "b": 0x244A66, "S": 0x609090]),
        bodySide: Sprite(Array(repeating: "Bb", count: 12), ["B": 0x244A66, "b": 0x1C3A52]),
        nearArm: Sprite(["WWWWw", "WWSSs"] + Array(repeating: "SSSSs", count: 9) + ["sssss"], ["W": 0xD8ECEC, "w": 0x9CB4B4, "S": 0x609090, "s": 0x4A7878]),
        farArm: Sprite(["WWw"] + Array(repeating: "SSs", count: 11), ["W": 0xC8DCDC, "w": 0x9CB4B4, "S": 0x548484, "s": 0x426E6E]),
        legs: Sprite(Array(repeating: "PPPpPPPPpp", count: 7) + ["PP.pPPP.pp", "P..pP...p.", "WWWWWWWWww", "WWWWWWWWww", "wwwwwwwwww"],
                     ["P": 0x3C3024, "p": 0x302418, "W": 0xD8ECEC, "w": 0x9CB4B4]))

    /// 冰锥（宽 w、长 len）：上宽下尖，浅蓝带白色高光
    static func icicle(_ b: inout DotBuffer, x: Int, top: Int, len: Int, w: Int = 4) {
        for dy in 0..<len {
            let half = Double(w) / 2 * (1 - Double(dy) / Double(len))
            for dx in 0..<w where abs(Double(dx) + 0.5 - Double(w) / 2) <= half + 0.3 {
                b.set(x + dx, top + dy, dx == 0 ? 0xD8E4FC : (dx == w - 1 ? 0x6078C0 : pick([0x90B4FC, 0x84A8F0, 0x789CF0], x + dx, dy, 81)))
            }
        }
    }

    /// 一簇冰晶（底边在 bottom）：几根往上的尖刺
    static func crystal(_ b: inout DotBuffer, x: Int, bottom: Int, size: Int) {
        for (k, (off, h)) in [(0, size), (-3, size * 2 / 3), (3, size * 3 / 4), (-5, size / 3), (5, size / 2)].enumerated() {
            for dy in 0..<h {
                let w = max(0, 2 - dy * 3 / max(1, h))
                for dx in -w...w { b.set(x + off + dx, bottom - dy, dx == -w ? 0xFCFCFC : (k % 2 == 0 ? 0xB4CCFC : 0xD8E4FC)) }
            }
        }
    }

    func paintStatic(_ b: inout DotBuffer) {
        let g = ground(b)
        // 洞里的深处：深蓝，往下渐亮一点
        Paint.sky(&b, until: g, [0x0A1430, 0x0E1C40, 0x142450, 0x1E3468])
        // 远处的冰墙：一块块蓝冰
        for y in 0..<g { for x in 0..<b.cols where noise(x / 9, y / 9, 82) > 0.55 && dither(x, y, 0.5) {
            b.set(x, y, 0x1E3468)
        } }
        // 洞顶（蓝冰）和挂着的冰锥
        for x in 0..<b.cols {
            let c = ceiling(b, x)
            for y in 0..<c { b.set(x, y, y >= c - 2 ? 0x6C90E0 : pick([0x30549C, 0x304890, 0x3A5CA8, 0x4A6CC0], x / 2, y / 2, 83)) }
        }
        for i in 0..<22 {
            let x = Int(noise(i, 0, 84) * Double(b.cols))
            Self.icicle(&b, x: x, top: ceiling(b, x) - 1, len: 6 + Int(noise(i, 1, 84) * 24), w: 3 + Int(noise(i, 2, 84) * 3))
        }
        // 地面：雪 → 浮冰 → 蓝冰
        Paint.strata(&b, from: g, top: [0xE8F0FC, 0xD8E8FC, 0xF4F8FF, 0xC8DCF8], topRows: 4,
                     mid: [0x90B4FC, 0x84A8F0, 0x789CF0, 0xA0C0FC], midRows: 18, deep: [0x30549C, 0x304890], seed: 85)
        // 地上的冰晶
        for (k, cx) in [0.06, 0.33, 0.52, 0.95].enumerated() { Self.crystal(&b, x: Int(Double(b.cols) * cx), bottom: g - 1, size: 9 + k % 2 * 5) }
    }

    func paintDynamic(_ b: inout DotBuffer, t: Double, cast: SceneCast) {
        let g = ground(b)
        // 冰晶发出的微光，一明一暗
        for (k, cx) in [0.06, 0.33, 0.52, 0.95].enumerated() {
            let x0 = Int(Double(b.cols) * cx), r = 14.0 + sin(t * 1.4 + Double(k)) * 3
            for y in (g - 26)..<g { for x in (x0 - 18)...(x0 + 18) {
                let d = (pow(Double(x - x0), 2) + pow(Double(y - g + 6), 2) * 1.6).squareRoot() / r
                if d < 1 && dither(x, y, (1 - d) * 0.35) && b[x, y] == 0 { b.set(x, y, 0x4A78D0) }
            } }
        }
        // 飘着的小冰晶粒
        Paint.falling(&b, t: t, count: 26, colors: [0xD8E4FC, 0xFFFFFF], top: 20, bottom: g, speed: 0.03, seed: 86)
        // 冰锥掉下来摔碎（6 秒一根）
        let n = Int(t / 6), fp = t.truncatingRemainder(dividingBy: 6)
        let ix = Int(Double(b.cols) * (0.1 + noise(n, 0, 87) * 0.4))
        let top = ceiling(b, ix)
        if fp < 1.2 {
            let y = top + Int(fp * fp * 90)
            if y + 14 < g { Self.icicle(&b, x: ix, top: y, len: 14, w: 4) }
            else {
                for i in 0..<10 {
                    let f = (fp - sqrt(Double(g - 14 - top) / 90)) * 3
                    b.set(ix + 2 + Int(Double(i - 5) * f * 3), g - 1 - Int(sin(Double(i)) * 3 * f + 2 * f), i % 2 == 0 ? 0xD8E4FC : 0x90B4FC)
                }
            }
        }

        // 冻尸扔冰球（4 秒一次），玩家举盾挡住
        let px = Int(Double(b.cols) * 0.76), fx = Int(Double(b.cols) * 0.18)
        let p = t.truncatingRemainder(dividingBy: 4)
        var fpose = PlayerPose()
        fpose.armAngle = 1.35 + sin(t * 2) * 0.08
        fpose.dx = Int((sin(t * 0.8) * 3).rounded())
        if (0.4...1.0).contains(p) { fpose.armAngle = p < 0.7 ? 1.35 + 1.4 * (p - 0.4) / 0.3 : 2.75 - 1.4 * (p - 0.7) / 0.3 }
        Player.draw(&b, look: Self.frostbite, pose: fpose, x: fx, feet: g - 1, t: t + 2, facingRight: true)
        // 冰球：抛物线飞过去，撞到盾上碎掉
        let flight = (0.9...2.1)
        let sx = Double(fx + 18), ex = Double(px - 6)
        if flight.contains(p) {
            let f = (p - 0.9) / 1.2
            let x = sx + (ex - sx) * f, y = Double(g - 24) - sin(f * .pi) * 22
            b.blit(Sprite([".bb.", "bWbb", "bbbB", ".BB."], ["b": 0x90B4FC, "W": 0xFFFFFF, "B": 0x6078C0]), x: Int(x), bottom: Int(y))
        } else if (2.1...2.6).contains(p) {
            let f = (p - 2.1) / 0.5
            for i in 0..<8 {
                let a = Double(i) / 8 * .pi + .pi / 2
                b.set(Int(ex) - Int(cos(a) * f * 8) - 2, g - 24 + Int(sin(a + .pi / 2) * f * 6) + Int(f * f * 10), i % 2 == 0 ? 0xFFFFFF : 0x90B4FC)
            }
        }
        var pose = Player.idle(t, props: PlayerProps(), phase: 1)
        pose.blocking = (1.6...2.8).contains(p)
        Player.draw(&b, look: cast.player, props: PlayerProps(offhand: CombatUpdate.shield), pose: pose, x: px, feet: g - 1, t: t)
    }
}
