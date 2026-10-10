import Foundation

/// Apple 芯片优化：
/// - 1.19+：版本 JSON 自带 natives-macos-arm64，直接使用 arm64 Java 原生运行。
/// - 1.13 ~ 1.18（LWJGL 3.1/3.2）：替换为 LWJGL 3.3.1（含 arm64 原生库），以 arm64 Java 原生运行。
/// - 1.12.2 及以前（LWJGL 2）：替换为社区编译的 LWJGL 2.9.4 arm64 原生库（MinecraftMachina，Prism Launcher 同样使用），
///   并使用 arm64 的 Java 8（Azul Zulu）原生运行；关闭原生模式时才使用 Rosetta 2。
package enum Lwjgl {
    package static let arm64Version = "3.3.1"

    /// LWJGL 3.3.1 中存在的模块
    package static let modules: Set<String> = [
        "lwjgl", "lwjgl-glfw", "lwjgl-jemalloc", "lwjgl-openal", "lwjgl-opengl", "lwjgl-stb", "lwjgl-tinyfd",
    ]

    /// 将 org.lwjgl:<module>:3.x 替换为 3.3.1 的 jar 与 arm64 原生库；不是 LWJGL 库则返回 nil
    package static func arm64Replacement(_ name: String, libDir: URL) -> [McLibrary]? {
        let parts = name.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "org.lwjgl", parts[2].hasPrefix("3.") else { return nil }
        let module = parts[1]
        // 原有的 natives 条目（classifier 为 natives-*）也被替换
        guard modules.contains(module) else { return [] }
        func lib(_ classifier: String?) -> McLibrary {
            let fullName = "org.lwjgl:\(module):\(arm64Version)" + (classifier.map { ":\($0)" } ?? "")
            let rel = Maven.path(fullName)!
            return McLibrary(name: fullName, path: libDir.appendingPathComponent(rel),
                             url: "https://libraries.minecraft.net/\(rel)", sha1: nil, size: nil,
                             isNatives: false, nativeArch: classifier == nil ? nil : "arm64")
        }
        return [lib(nil), lib("natives-macos-arm64")]
    }

    // MARK: LWJGL 2

    package static let lwjgl2Version = "2.9.4-nightly-20150209"
    static let lwjgl2NativesURL = "https://github.com/MinecraftMachina/lwjgl/releases/download/2.9.4-20150209-mmachina.2/lwjgl-platform-2.9.4-nightly-20150209-natives-osx.jar"
    static let lwjgl2NativesSHA1 = "eff546c0b319d6ffc7a835652124c18089c67f36"

    /// LWJGL 2 相关库在 arm64 上的替换；不相关的库返回 nil，需要移除的库返回空数组
    package static func lwjgl2Arm64Replacement(_ name: String, libDir: URL) -> [McLibrary]? {
        let parts = name.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return nil }
        let (group, artifact) = (parts[0], parts[1])
        func lib(_ coords: String, url: String, sha1: String? = nil, size: Int64? = nil, natives: Bool = false, arch: String? = nil) -> McLibrary {
            let rel = Maven.path(coords)!
            return McLibrary(name: coords, path: libDir.appendingPathComponent(rel), url: url, sha1: sha1, size: size,
                             isNatives: natives, nativeArch: arch)
        }
        switch (group, artifact) {
        case ("org.lwjgl.lwjgl", "lwjgl"), ("org.lwjgl.lwjgl", "lwjgl_util"):
            let coords = "org.lwjgl.lwjgl:\(artifact):\(lwjgl2Version)"
            return [lib(coords, url: "https://libraries.minecraft.net/" + Maven.path(coords)!)]
        case ("org.lwjgl.lwjgl", "lwjgl-platform"):
            return [lib("org.lwjgl.lwjgl:lwjgl-platform:\(lwjgl2Version):natives-osx-arm64", url: lwjgl2NativesURL,
                        sha1: lwjgl2NativesSHA1, size: 488316, natives: true)]
        case ("ca.weblite", "java-objc-bridge"):
            // 1.1 起为通用二进制（含 arm64），原生库位于主 jar 中
            let coords = "ca.weblite:java-objc-bridge:1.1"
            return [lib(coords, url: "https://repo1.maven.org/maven2/" + Maven.path(coords)!, arch: "arm64")]
        case ("net.java.jinput", "jinput-platform"), ("tv.twitch", "twitch-platform"), ("tv.twitch", "twitch-external-platform"):
            // 只有 x86_64 原生库；手柄与 Twitch 功能在 macOS 上本就不可用
            return []
        default:
            return nil
        }
    }
}

extension McInstance {
    /// 含有需要 Java 8 的旧版 Mod 加载器（Forge 1.16 及以前、LiteLoader、旧 OptiFine）
    package var needsStrictJava8: Bool {
        javaMajor <= 8 && loaders.contains { ["Forge", "LiteLoader", "OptiFine"].contains($0) }
    }

    /// 期望的 Java 架构（不考虑已安装的 Java）
    package var preferredArch: String {
        guard Arch.isAppleSilicon else { return "x86_64" }
        // 关闭原生模式时，只有自带 arm64 原生库的版本才原生运行
        if !LauncherSettings.shared.arm64Native { return hasArm64Natives || !needsNatives ? "arm64" : "x86_64" }
        return canRunNativelyOnArm ? "arm64" : "x86_64"
    }

    /// 在 arm64 原生模式下可以接受的 Java 主版本
    package func acceptsJava(_ java: JavaInfo) -> Bool {
        // LWJGL 2 版本只能使用 Java 8
        if isLwjgl2 { return java.major == 8 }
        if java.compatible(with: javaMajor) { return true }
        // 1.13 ~ 1.16 原版 / Fabric / Quilt 可以在 Java 17 上运行，用于没有 arm64 Java 8 的情况
        if javaMajor <= 8, java.arch == "arm64", !needsStrictJava8, lwjglVersion?.hasPrefix("3.") == true {
            return java.major >= 17 && java.major <= 21
        }
        return false
    }
}
