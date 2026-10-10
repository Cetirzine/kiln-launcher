import Foundation

/// 启动器日志：写入 ~/Library/Application Support/PCL-macOS/Log/Log1.txt
package final class Log: @unchecked Sendable {
    package static let shared = Log()
    private let queue = DispatchQueue(label: "pcl.log")
    private var handle: FileHandle?
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let url = Paths.logs.appendingPathComponent("Log1.txt")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let old = Paths.logs.appendingPathComponent("Log2.txt")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    package func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [weak self] in
            self?.handle?.write(Data(line.utf8))
            #if DEBUG
            FileHandle.standardError.write(Data(line.utf8))
            #endif
        }
    }

    package static var file: URL { Paths.logs.appendingPathComponent("Log1.txt") }
}

package func log(_ message: String) { Log.shared.write(message) }

extension Error {
    /// 获取较为友好的错误描述
    package var friendly: String {
        if let e = self as? LocalizedError, let d = e.errorDescription { return d }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain {
            return "\(ns.localizedDescription) (\(ns.code))"
        }
        return ns.localizedDescription
    }
}

package struct LauncherError: LocalizedError {
    package let message: String
    package init(_ message: String) { self.message = message }
    package var errorDescription: String? { message }
}
