import SwiftUI
import LauncherCore

/// 版本图标：有本机游戏材质时使用原版材质，否则使用代码绘制的方块
struct BlockIcon: View {
    let kind: String

    var body: some View {
        Group {
            if let faces = BlockTextures.shared.faces[kind] {
                TexturedBlock(faces: faces)
            } else {
                DrawnBlock(kind: kind)
            }
        }
        // 自定义方块按需从游戏文件中读取
        .task(id: kind) {
            if kind.hasPrefix("block:") && BlockTextures.shared.faces[kind] == nil {
                await BlockTextures.shared.ensure([kind])
            }
        }
    }
}

/// 代码绘制的等轴测方块（本机还没有游戏文件时使用）
struct DrawnBlock: View {
    let kind: String

    private struct Palette { let top: Color; let left: Color; let right: Color; var stripe: Color? = nil; var mark: Color? = nil }

    private var palette: Palette {
        switch kind {
        case "Grass": return Palette(top: Color(hex: 0x6dbb45), left: Color(hex: 0x8a5a33), right: Color(hex: 0x6f4627), stripe: Color(hex: 0x5ea43a))
        case "CommandBlock": return Palette(top: Color(hex: 0xc98a4b), left: Color(hex: 0xb07339), right: Color(hex: 0x8f5c2c), mark: Color(hex: 0xe8e2c9))
        case "CobbleStone": return Palette(top: Color(hex: 0x9a9a9a), left: Color(hex: 0x7d7d7d), right: Color(hex: 0x636363))
        case "GoldBlock": return Palette(top: Color(hex: 0xf7d84a), left: Color(hex: 0xe0b52c), right: Color(hex: 0xc39318))
        case "Anvil": return Palette(top: Color(hex: 0x5b5f66), left: Color(hex: 0x44474d), right: Color(hex: 0x33363b), mark: Color(hex: 0x8d939c))
        case "Fabric": return Palette(top: Color(hex: 0xdcd3b8), left: Color(hex: 0xbfb391), right: Color(hex: 0xa39674), mark: Color(hex: 0x38342a))
        case "NeoForge": return Palette(top: Color(hex: 0xf08a3c), left: Color(hex: 0xd36d22), right: Color(hex: 0xae5615), mark: Color(hex: 0xffe2c4))
        case "Quilt": return Palette(top: Color(hex: 0xb58ee8), left: Color(hex: 0x9068cc), right: Color(hex: 0x7350ad))
        case "GrassPath": return Palette(top: Color(hex: 0xa98b4f), left: Color(hex: 0x8a5a33), right: Color(hex: 0x6f4627))
        case "RedstoneBlock": return Palette(top: Color(hex: 0xd8341f), left: Color(hex: 0xb02412), right: Color(hex: 0x8d1a0c))
        case "Kiln": return Palette(top: Color(hex: 0xa3a39e), left: Color(hex: 0x7e7e79), right: Color(hex: 0x62625e))
        default: return Palette(top: Color(hex: 0x6aa7f7), left: Color(hex: 0x3f86ee), right: Color(hex: 0x1d6ae0))
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let g = IsoGeometry(size)
            let h = size.height
            let c = g.center
            let topY = g.top.y, midY = g.left.y, botY = g.bottom.y, edgeY = g.leftBottom.y
            let l = g.left.x, r = g.right.x
            let p = palette
            var top = Path()
            top.move(to: CGPoint(x: c.x, y: topY)); top.addLine(to: CGPoint(x: r, y: midY))
            top.addLine(to: CGPoint(x: c.x, y: c.y)); top.addLine(to: CGPoint(x: l, y: midY)); top.closeSubpath()
            var left = Path()
            left.move(to: CGPoint(x: l, y: midY)); left.addLine(to: CGPoint(x: c.x, y: c.y))
            left.addLine(to: CGPoint(x: c.x, y: botY)); left.addLine(to: CGPoint(x: l, y: edgeY)); left.closeSubpath()
            var right = Path()
            right.move(to: CGPoint(x: c.x, y: c.y)); right.addLine(to: CGPoint(x: r, y: midY))
            right.addLine(to: CGPoint(x: r, y: edgeY)); right.addLine(to: CGPoint(x: c.x, y: botY)); right.closeSubpath()
            ctx.fill(top, with: .color(p.top))
            ctx.fill(left, with: .color(p.left))
            ctx.fill(right, with: .color(p.right))
            if let s = p.stripe {
                // 草方块侧面顶部的草皮
                let d = h * 0.12
                var sl = Path()
                sl.move(to: CGPoint(x: l, y: midY)); sl.addLine(to: CGPoint(x: c.x, y: c.y))
                sl.addLine(to: CGPoint(x: c.x, y: c.y + d)); sl.addLine(to: CGPoint(x: l, y: midY + d)); sl.closeSubpath()
                var sr = Path()
                sr.move(to: CGPoint(x: c.x, y: c.y)); sr.addLine(to: CGPoint(x: r, y: midY))
                sr.addLine(to: CGPoint(x: r, y: midY + d)); sr.addLine(to: CGPoint(x: c.x, y: c.y + d)); sr.closeSubpath()
                ctx.fill(sl, with: .color(s)); ctx.fill(sr, with: .color(s.opacity(0.8)))
            }
            if let m = p.mark {
                // 顶面中央的标记
                var mk = Path()
                let s: CGFloat = 0.32
                mk.move(to: CGPoint(x: c.x, y: topY + (c.y - topY) * s))
                mk.addLine(to: CGPoint(x: c.x + (r - c.x) * (1 - s * 1.4), y: midY))
                mk.addLine(to: CGPoint(x: c.x, y: c.y - (c.y - topY) * s))
                mk.addLine(to: CGPoint(x: c.x - (c.x - l) * (1 - s * 1.4), y: midY)); mk.closeSubpath()
                ctx.fill(mk, with: .color(m.opacity(0.85)))
            }
            if kind == "Kiln" {
                // 左侧面上的炉口，透出火光
                func onLeft(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                    let top = CGPoint(x: l + (c.x - l) * u, y: midY + (c.y - midY) * u)
                    let bottomY = edgeY + (botY - edgeY) * u
                    return CGPoint(x: top.x, y: top.y + (bottomY - top.y) * v)
                }
                var mouth = Path()
                mouth.move(to: onLeft(0.25, 0.45)); mouth.addLine(to: onLeft(0.75, 0.45))
                mouth.addLine(to: onLeft(0.75, 0.85)); mouth.addLine(to: onLeft(0.25, 0.85)); mouth.closeSubpath()
                ctx.fill(mouth, with: .color(Color(hex: 0x2a2a28)))
                var glow = Path()
                glow.move(to: onLeft(0.3, 0.62)); glow.addLine(to: onLeft(0.7, 0.62))
                glow.addLine(to: onLeft(0.7, 0.8)); glow.addLine(to: onLeft(0.3, 0.8)); glow.closeSubpath()
                ctx.fill(glow, with: .color(Color(hex: 0xf29a3a)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 与游戏物品栏一致的等轴测投影：绕 Y 轴 45°、绕 X 轴 30°。
/// 顶面菱形的高度是宽度的 1/2，侧面高度约为宽度的 0.612 倍，整个方块高宽比约 1.11。
struct IsoGeometry {
    let top, left, right, center, leftBottom, rightBottom, bottom: CGPoint

    init(_ size: CGSize) {
        let side: CGFloat = 0.6124  // cos30° / (2·cos45°)
        let ratio: CGFloat = 0.5 + side
        // 在给定区域内取最大的、保持比例的方块，居中放置
        let width = min(size.width, size.height / ratio) * 0.96
        let height = width * ratio
        let x0 = (size.width - width) / 2, y0 = (size.height - height) / 2
        top = CGPoint(x: x0 + width / 2, y: y0)
        left = CGPoint(x: x0, y: y0 + width / 4)
        right = CGPoint(x: x0 + width, y: y0 + width / 4)
        center = CGPoint(x: x0 + width / 2, y: y0 + width / 2)
        leftBottom = CGPoint(x: left.x, y: left.y + width * side)
        rightBottom = CGPoint(x: right.x, y: right.y + width * side)
        bottom = CGPoint(x: center.x, y: center.y + width * side)
    }
}
