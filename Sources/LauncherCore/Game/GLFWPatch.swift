import Foundation

/// 1.13 ~ 1.18 换用 LWJGL 3.3.1（GLFW 3.4）后，macOS 上调用 glfwSetWindowIcon 会产生
/// GLFW_FEATURE_UNAVAILABLE（65548）错误，而这些版本在创建窗口期间会把任何 GLFW 错误当作致命错误。
/// macOS 本来就不支持窗口图标（Mojang 在 1.19 起也直接跳过了这个调用），
/// 因此生成一份 lwjgl-glfw 的副本，把 glfwSetWindowIcon 中对原生函数的调用替换为出栈指令。
package enum GLFWPatch {
    /// 返回打过补丁的 jar（不存在时生成）；失败时返回 nil，调用方继续使用原 jar
    package static func patchedJar(for original: URL) -> URL? {
        let fm = FileManager.default
        let patched = original.deletingLastPathComponent()
            .appendingPathComponent(original.deletingPathExtension().lastPathComponent + "-kiln-macos.jar")
        if fm.fileExists(atPath: patched.path) { return patched }
        guard fm.fileExists(atPath: original.path),
              let classData = Zip.read(original, "org/lwjgl/glfw/GLFW.class"),
              let fixed = patchClass(classData) else {
            log("[GLFW] 无法为 \(original.lastPathComponent) 生成补丁")
            return nil
        }
        let work = Paths.cache.appendingPathComponent("glfw-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        do {
            let classURL = work.appendingPathComponent("org/lwjgl/glfw/GLFW.class")
            try fm.createDirectory(at: classURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fixed.write(to: classURL)
            let tmpJar = work.appendingPathComponent("patched.jar")
            try fm.copyItem(at: original, to: tmpJar)
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-q", "-X", tmpJar.path, "org/lwjgl/glfw/GLFW.class"]
            zip.currentDirectoryURL = work
            try zip.run()
            zip.waitUntilExit()
            guard zip.terminationStatus == 0 else { return nil }
            try fm.moveItem(at: tmpJar, to: patched)
            log("[GLFW] 已生成 \(patched.lastPathComponent)")
            return patched
        } catch {
            log("[GLFW] 生成补丁失败：\(error.friendly)")
            return nil
        }
    }

    /// 在 class 文件中找到 `invokestatic nglfwSetWindowIcon(JIJ)V; return`，替换为 `pop2; pop; pop2; return`
    package static func patchClass(_ data: Data) -> Data? {
        var bytes = [UInt8](data)
        guard bytes.count > 10, bytes[0] == 0xCA, bytes[1] == 0xFE else { return nil }
        func u2(_ i: Int) -> Int { Int(bytes[i]) << 8 | Int(bytes[i + 1]) }

        // 解析常量池，找到 nglfwSetWindowIcon 的 Methodref 序号
        let count = u2(8)
        var utf8: [Int: String] = [:]
        var nameAndType: [Int: (Int, Int)] = [:]
        var methodRefs: [Int: Int] = [:] // 序号 → NameAndType 序号
        var i = 10
        var index = 1
        while index < count {
            let tag = bytes[i]
            switch tag {
            case 1:
                let len = u2(i + 1)
                utf8[index] = String(decoding: bytes[(i + 3)..<(i + 3 + len)], as: UTF8.self)
                i += 3 + len
            case 3, 4: i += 5
            case 5, 6: i += 9; index += 1
            case 7, 8, 16, 19, 20: i += 3
            case 9, 11, 17, 18: i += 5
            case 10: methodRefs[index] = u2(i + 3); i += 5
            case 12: nameAndType[index] = (u2(i + 1), u2(i + 3)); i += 5
            case 15: i += 4
            default: return nil
            }
            index += 1
        }
        guard let target = methodRefs.first(where: { _, nt in
            guard let (n, d) = nameAndType[nt] else { return false }
            return utf8[n] == "nglfwSetWindowIcon" && utf8[d] == "(JIJ)V"
        })?.key else { return nil }

        // 搜索 lload_0, aload_2, invokestatic, aload_2, invokestatic, invokestatic <target>, return
        let hi = UInt8(target >> 8), lo = UInt8(target & 0xFF)
        var found = 0
        var p = 0
        while p + 13 <= bytes.count {
            if bytes[p] == 0x1E, bytes[p + 1] == 0x2C, bytes[p + 2] == 0xB8, bytes[p + 5] == 0x2C, bytes[p + 6] == 0xB8,
               bytes[p + 9] == 0xB8, bytes[p + 10] == hi, bytes[p + 11] == lo, bytes[p + 12] == 0xB1 {
                // 栈上为 long, int, long：依次出栈，栈平衡不变，无需修改 StackMapTable
                bytes[p + 9] = 0x58   // pop2
                bytes[p + 10] = 0x57  // pop
                bytes[p + 11] = 0x58  // pop2
                found += 1
            }
            p += 1
        }
        return found > 0 ? Data(bytes) : nil
    }
}

/// lwjgl-3.3.1.jar 是多版本 jar，META-INF/versions/19 中有 Java 19 的类。
/// 旧版 Fabric Loader（如 0.4.x）启动时会用旧的 ASM 读取类路径上所有的类，遇到这些类就会崩溃
/// （Unsupported class file major version 63）。这些类只是新版 Java 上的可选实现，去掉后 LWJGL 使用通用实现
/// （已在 Java 8、17、21 上验证），因此为 Fabric / Quilt 生成一份去掉它们的副本。
package enum MultiReleasePatch {
    package static func strippedJar(for original: URL) -> URL? {
        let fm = FileManager.default
        let stripped = original.deletingLastPathComponent()
            .appendingPathComponent(original.deletingPathExtension().lastPathComponent + "-kiln-java17.jar")
        if fm.fileExists(atPath: stripped.path) { return stripped }
        let newer = Zip.list(original).filter { entry in
            guard entry.hasPrefix("META-INF/versions/"), let v = Int(entry.split(separator: "/").dropFirst(2).first ?? "") else { return false }
            return v > 17
        }
        guard !newer.isEmpty else { return nil }
        let tmp = Paths.cache.appendingPathComponent("mr-\(UUID().uuidString).jar")
        defer { try? fm.removeItem(at: tmp) }
        do {
            try fm.copyItem(at: original, to: tmp)
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-q", "-d", tmp.path] + newer
            zip.standardOutput = FileHandle.nullDevice
            try zip.run()
            zip.waitUntilExit()
            guard zip.terminationStatus == 0 else { return nil }
            try fm.moveItem(at: tmp, to: stripped)
            log("[LWJGL] 已生成 \(stripped.lastPathComponent)（去掉 Java 18+ 的类）")
            return stripped
        } catch {
            log("[LWJGL] 生成 \(stripped.lastPathComponent) 失败：\(error.friendly)")
            return nil
        }
    }
}
