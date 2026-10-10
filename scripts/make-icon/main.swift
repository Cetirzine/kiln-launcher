// 生成应用图标：与启动器共用 Sources/Kiln/UI/LogoMark.swift 的绘制代码
// 用法：make-icon <输出的 .iconset 目录> [额外导出的 1024 PNG 路径]
import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

@MainActor
func render(_ px: Int) -> Data {
    let renderer = ImageRenderer(content: LogoMark(fullCanvas: true).frame(width: CGFloat(px), height: CGFloat(px)))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { fatalError("无法渲染图标") }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(size * scale).write(to: out.appendingPathComponent(name))
    }
    if CommandLine.arguments.count > 2 {
        try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
