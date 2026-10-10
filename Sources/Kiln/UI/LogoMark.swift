import SwiftUI

/// 应用标志：深色渐变方块上的镐子（应用图标、侧栏、assets/logo.svg 使用同一套几何）
/// 坐标系为 1024×1024 的图标画布，内容区域为 macOS 图标网格的 824×824、圆角 185。
enum LogoGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let tileRadius: CGFloat = 185

    /// 局部坐标（镐柄竖直向下、镐头在上方）→ 图标画布：缩放后旋转 45° 指向右上
    static let placement = CGAffineTransform(translationX: 512, y: 512).scaledBy(x: 1.06, y: 1.06)
        .translatedBy(x: -49, y: 49).rotated(by: .pi / 4)

    private static func transformed(_ p: CGMutablePath) -> CGPath {
        var t = placement
        return p.copy(using: &t) ?? p
    }

    /// 镐头：外弧（圆心 (0,140)，半径 430）与内弧（圆心 (0,1158.8)，半径 1348.8）围成的月牙，两端为尖角
    static func head() -> CGPath {
        let p = CGMutablePath()
        let tipX: CGFloat = 315, tipY: CGFloat = -152.7
        p.addArc(center: CGPoint(x: 0, y: 140), radius: 430,
                 startAngle: atan2(tipY - 140, -tipX), endAngle: atan2(tipY - 140, tipX), clockwise: false)
        p.addArc(center: CGPoint(x: 0, y: 1158.8), radius: 1348.8,
                 startAngle: atan2(tipY - 1158.8, tipX), endAngle: atan2(tipY - 1158.8, -tipX), clockwise: true)
        p.closeSubpath()
        return transformed(p)
    }

    /// 镐柄：顶端平直并藏入镐头，末端为圆头
    static func handle() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -35, y: -200))
        p.addLine(to: CGPoint(x: 35, y: -200))
        p.addLine(to: CGPoint(x: 35, y: 295))
        p.addArc(center: CGPoint(x: 0, y: 295), radius: 35, startAngle: 0, endAngle: .pi, clockwise: false)
        p.closeSubpath()
        return transformed(p)
    }

    /// 镐柄与镐头相接处的金属箍
    static func collar() -> CGPath {
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: -48, y: -196, width: 96, height: 46), cornerWidth: 12, cornerHeight: 12)
        return transformed(p)
    }

    /// 局部坐标中的点映射到图标画布
    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(placement) }
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

        // 背景：左上石墨色到右下纯黑
        ctx.fill(tile, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x30343D), Color(hex: 0x111216), Color(hex: 0x030304)]),
            startPoint: CGPoint(x: 120, y: 100), endPoint: CGPoint(x: 900, y: 924)))
        // 镐头后方的青色光晕
        ctx.drawLayer { glow in
            glow.clip(to: tile)
            glow.fill(tile, with: .radialGradient(
                Gradient(colors: [Color(hex: 0x46D9E6, alpha: 0.34), Color(hex: 0x46D9E6, alpha: 0)]),
                center: LogoGeometry.point(0, -170), startRadius: 0, endRadius: 470))
        }

        // 镐子投影
        ctx.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.6), radius: 26, x: 0, y: 22))
            shadow.fill(Path(LogoGeometry.handle()), with: .color(.black))
            shadow.fill(Path(LogoGeometry.head()), with: .color(.black))
        }

        // 镐柄：银白到灰
        ctx.fill(Path(LogoGeometry.handle()), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xF4F5F7), Color(hex: 0xB9BCC2), Color(hex: 0x8A8D93)]),
            startPoint: LogoGeometry.point(-35, 0), endPoint: LogoGeometry.point(35, 0)))
        // 金属箍
        ctx.fill(Path(LogoGeometry.collar()), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xE3E6EA), Color(hex: 0x7C8087)]),
            startPoint: LogoGeometry.point(0, -196), endPoint: LogoGeometry.point(0, -150)))

        // 镐头：白色到冰青色
        let head = Path(LogoGeometry.head())
        ctx.fill(head, with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: 0xFFFFFF), location: 0),
                             .init(color: Color(hex: 0xD6FAFC), location: 0.45),
                             .init(color: Color(hex: 0x56D3E0), location: 1)]),
            startPoint: LogoGeometry.point(-315, -230), endPoint: LogoGeometry.point(315, -120)))
        // 镐头上沿的高光
        ctx.drawLayer { hl in
            hl.clip(to: head)
            hl.stroke(head, with: .color(.white.opacity(0.9)), lineWidth: 10)
        }

        // 边缘细高光
        ctx.stroke(Path(roundedRect: LogoGeometry.tile.insetBy(dx: 2, dy: 2), cornerRadius: LogoGeometry.tileRadius - 2, style: .continuous),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.02)]),
                                         startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 924, y: 924)),
                   lineWidth: 3)
    }
}
