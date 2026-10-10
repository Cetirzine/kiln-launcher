import Foundation

/// 通过系统自带的 unzip 读取 jar / zip
package enum Zip {
    @discardableResult
    package static func run(_ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    /// 读取压缩包中的单个文件
    package static func read(_ archive: URL, _ entry: String) -> Data? {
        let d = try? run(["-p", archive.path, entry])
        return (d?.isEmpty ?? true) ? nil : d
    }

    /// 解压单个文件到指定位置
    package static func extract(_ archive: URL, _ entry: String, to dest: URL) throws {
        guard let d = read(archive, entry) else { throw LauncherError(T("压缩包中缺少 \(entry)", "\(entry) is missing from the archive")) }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try d.write(to: dest)
    }

    /// 列出压缩包中的文件
    package static func list(_ archive: URL) -> [String] {
        guard let d = try? run(["-Z1", archive.path]) else { return [] }
        return String(decoding: d, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// 读取 jar 的 Main-Class
    package static func mainClass(_ jar: URL) -> String? {
        guard let d = read(jar, "META-INF/MANIFEST.MF") else { return nil }
        for line in String(decoding: d, as: UTF8.self).split(whereSeparator: \.isNewline) where line.hasPrefix("Main-Class:") {
            return line.dropFirst("Main-Class:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
