import SwiftUI

/// 应用标志：深蓝方块上的一颗像素风青金石（原创像素画，不使用游戏贴图）。
/// 应用图标、侧栏标志、assets/logo.svg 使用同一份像素数据。
/// 坐标系为 1024×1024 的图标画布，内容区域为 macOS 图标网格的 824×824、圆角 185。
enum LogoGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let tileRadius: CGFloat = 185

    /// 16×16 像素：. 透明  o 描边  d 深蓝  m 中蓝  l 浅蓝  h 高光  w 闪光
    static let pixels: [String] = [
        "................",
        ".......oo.......",
        ".....oohho......",
        "....ohhwlmo.....",
        "...ohlllmmmoo...",
        "..ohllmmmmdddo..",
        "..olmmmlmmmddo..",
        ".olmmmllmmdddo..",
        ".ommmmmmmddddo..",
        ".ommdmmmmmdddoo.",
        "..oddmmmlmmdddo.",
        "..oddddmmmdddo..",
        "...oodddddddo...",
        ".....oodddoo....",
        ".......ooo......",
        "................",
    ]

    static let palette: [Character: UInt32] = [
        "o": 0x0B1240, "d": 0x1A2F9C, "m": 0x2449CF, "l": 0x4A78EE, "h": 0x8FB3FF, "w": 0xFFFFFF,
    ]

    /// 宝石在画布中的区域（每个像素 36pt，共 576pt，居中）
    static let gemRect = CGRect(x: 224, y: 220, width: 576, height: 576)
}

/// 绘制标志。`fullCanvas` 为 true 时按 1024 图标画布（四周留白）绘制，用于生成应用图标
struct LogoMark: View {
    var fullCanvas = false

    var body: some View {
        Canvas { ctx, size in
            let box = fullCanvas ? LogoGeometry.canvas : LogoGeometry.tile
            let s = min(size.width, size.height) / box.width
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            Self.draw(in: &ctx)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func draw(in ctx: inout GraphicsContext) {
        let tile = Path(roundedRect: LogoGeometry.tile, cornerRadius: LogoGeometry.tileRadius, style: .continuous)
        let gem = LogoGeometry.gemRect
        let px = gem.width / 16

        // 背景：冷白到淡蓝灰
        ctx.fill(tile, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xFBFCFF), Color(hex: 0xE3E9F7), Color(hex: 0xC3CEEA)]),
            startPoint: CGPoint(x: 140, y: 100), endPoint: CGPoint(x: 884, y: 924)))
        // 宝石后方的淡蓝光晕
        ctx.drawLayer { glow in
            glow.clip(to: tile)
            glow.fill(tile, with: .radialGradient(
                Gradient(colors: [Color(hex: 0x4A78EE, alpha: 0.28), Color(hex: 0x4A78EE, alpha: 0)]),
                center: CGPoint(x: gem.midX, y: gem.midY), startRadius: 0, endRadius: 400))
        }

        // 像素宝石的剪影
        var silhouette = Path()
        for (row, line) in LogoGeometry.pixels.enumerated() {
            for (col, ch) in line.enumerated() where ch != "." {
                silhouette.addRect(CGRect(x: gem.minX + CGFloat(col) * px, y: gem.minY + CGFloat(row) * px, width: px, height: px))
            }
        }
        // 投影单独画在一层，像素本身直接画在画布上，保持边缘锐利
        ctx.drawLayer { shadow in
            shadow.addFilter(.shadow(color: Color(hex: 0x0B1240, alpha: 0.45), radius: 24, x: 0, y: 22))
            shadow.fill(silhouette, with: .color(Color(hex: 0x0B1240)))
        }
        for (row, line) in LogoGeometry.pixels.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let hex = LogoGeometry.palette[ch] else { continue }
                let r = CGRect(x: gem.minX + CGFloat(col) * px, y: gem.minY + CGFloat(row) * px, width: px, height: px)
                ctx.fill(Path(r), with: .color(Color(hex: hex)))
            }
        }

        // 边缘细描边
        ctx.stroke(Path(roundedRect: LogoGeometry.tile.insetBy(dx: 1.5, dy: 1.5), cornerRadius: LogoGeometry.tileRadius - 1.5, style: .continuous),
                   with: .color(Color(hex: 0x0B1240, alpha: 0.12)), lineWidth: 3)
    }
}
