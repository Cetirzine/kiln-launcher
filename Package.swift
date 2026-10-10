// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kiln",
    platforms: [.macOS(.v14)],
    targets: [
        // 与界面无关的启动器核心：版本解析、下载、Java、登录、启动
        .target(
            name: "LauncherCore",
            path: "Sources/LauncherCore"
        ),
        // macOS 界面（SwiftUI）
        .executableTarget(
            name: "Kiln",
            dependencies: ["LauncherCore"],
            path: "Sources/Kiln"
        ),
    ]
)
