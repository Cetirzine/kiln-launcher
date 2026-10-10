// 生成应用图标（蓝色渐变圆角方块 + 火焰），输出 .iconset 目录
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS 图标网格：内容区约占 80%
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.62, blue: 1, alpha: 1), NSColor(srgbRed: 0.05, green: 0.36, blue: 0.86, alpha: 1)])!
        .draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    // 火焰符号
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let fs = flame.size
        flame.draw(in: NSRect(x: (s - fs.width) / 2, y: (s - fs.height) / 2, width: fs.width, height: fs.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try! render(size * scale).write(to: out.appendingPathComponent(name))
}
