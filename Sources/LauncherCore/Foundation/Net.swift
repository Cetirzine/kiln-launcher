import Foundation
import CryptoKit

package enum Net {
    package static let userAgent = "\(AppInfo.shortName)/\(AppInfo.version)"

    package static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        c.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: c)
    }()

    // MARK: 镜像源（BMCLAPI）

    package enum Kind { case versionList, file }

    private static let mirrorRules: [(String, String)] = [
        ("https://piston-meta.mojang.com/", "https://bmclapi2.bangbang93.com/"),
        ("https://launchermeta.mojang.com/", "https://bmclapi2.bangbang93.com/"),
        ("https://piston-data.mojang.com/", "https://bmclapi2.bangbang93.com/"),
        ("https://launcher.mojang.com/", "https://bmclapi2.bangbang93.com/"),
        ("https://libraries.minecraft.net/", "https://bmclapi2.bangbang93.com/maven/"),
        ("https://resources.download.minecraft.net/", "https://bmclapi2.bangbang93.com/assets/"),
        ("https://maven.fabricmc.net/", "https://bmclapi2.bangbang93.com/maven/"),
        ("https://meta.fabricmc.net/", "https://bmclapi2.bangbang93.com/fabric-meta/"),
        ("https://maven.quiltmc.org/repository/release/", "https://bmclapi2.bangbang93.com/maven/"),
        ("https://meta.quiltmc.org/", "https://bmclapi2.bangbang93.com/quilt-meta/"),
        ("https://maven.minecraftforge.net/", "https://bmclapi2.bangbang93.com/maven/"),
        ("https://maven.neoforged.net/releases/", "https://bmclapi2.bangbang93.com/maven/"),
    ]

    package static func mirror(_ url: String) -> String? {
        for (from, to) in mirrorRules where url.hasPrefix(from) {
            return to + url.dropFirst(from.count)
        }
        return nil
    }

    /// 根据下载源设置给出候选地址（按尝试顺序）
    package static func candidates(_ url: String, kind: Kind) -> [String] {
        guard let m = mirror(url) else { return [url] }
        let source = kind == .versionList ? LauncherSettings.shared.versionListSource : LauncherSettings.shared.fileSource
        return source == .mirrorFirst ? [m, url] : [url, m]
    }

    // MARK: 请求

    package static func data(_ urls: [String], timeout: TimeInterval? = nil, headers: [String: String] = [:]) async throws -> Data {
        var lastError: Error = LauncherError("No URL")
        let firstTimeout: TimeInterval? = {
            if let timeout { return timeout }
            // “仅在官方源加载缓慢时改用镜像源”：第一个地址只给较短的超时
            return urls.count > 1 && LauncherSettings.shared.versionListSource == .officialSlowFallback ? 8 : nil
        }()
        for (i, u) in urls.enumerated() {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            if i == 0, let t = firstTimeout { req.timeoutInterval = t }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            do {
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw LauncherError("HTTP \(http.statusCode): \(u)")
                }
                return data
            } catch {
                if Task.isCancelled { throw CancellationError() }
                log("[Net] 请求失败 \(u)：\(error.friendly)")
                lastError = error
            }
        }
        throw lastError
    }

    package static func json(_ url: String, kind: Kind = .versionList) async throws -> JSON {
        try JSON(data: try await data(candidates(url, kind: kind)))
    }

    package static func json(urls: [String]) async throws -> JSON {
        try JSON(data: try await data(urls))
    }

    /// 发送 JSON / 表单请求（用于正版登录）
    package static func request(_ url: String, method: String = "POST", body: Data? = nil, contentType: String? = nil,
                        headers: [String: String] = [:]) async throws -> (Int, JSON) {
        guard let u = URL(string: url) else { throw LauncherError("Bad URL \(url)") }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 30
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        // 本地代理等环境下，复用的空闲连接可能已被关闭（-1005）；系统不会自动重试 POST，这里重试临时性网络错误
        var attempt = 0
        while true {
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code >= 400 { log("[Net] \(method) \(u.host ?? url) → HTTP \(code)") }
                return (code, (try? JSON(data: data)) ?? .null)
            } catch {
                attempt += 1
                log("[Net] \(method) \(u.host ?? url) 失败（第 \(attempt) 次）：\(error.friendly)")
                guard attempt < 4, isTransient(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    /// 连接中断、超时等可以重试的网络错误
    package static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet, NSURLErrorSecureConnectionFailed,
                NSURLErrorCannotFindHost].contains(ns.code)
    }

    package static func formBody(_ items: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = items.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
        return Data(s.utf8)
    }
}

package enum Hash {
    package static func sha1(file url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    package static func md5(_ data: Data) -> [UInt8] { Array(Insecure.MD5.hash(data: data)) }
}

// MARK: - 文件下载

/// 单个需要下载的文件
package struct DownloadItem: Sendable, Hashable {
    package var urls: [String]
    package var destination: URL
    package var sha1: String?
    package var size: Int64?

    package init(url: String, destination: URL, sha1: String? = nil, size: Int64? = nil, kind: Net.Kind = .file) {
        self.urls = Net.candidates(url, kind: kind)
        self.destination = destination
        self.sha1 = sha1?.lowercased()
        self.size = size
    }

    /// 本地文件是否已存在且完整
    package func isValid(checkHash: Bool = true) -> Bool {
        let path = destination.path
        guard let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let fsize = attr[.size] as? Int64 else { return false }
        if let size, size > 0, fsize != size { return false }
        if fsize == 0 && (size ?? 1) != 0 { return false }
        if checkHash, let sha1, !sha1.isEmpty {
            // 快速校验：文件的大小与修改时间未变时，沿用上次的校验结果，避免重复计算 SHA1
            let mtime = (attr[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let stamp = "\(fsize):\(Int(mtime)):\(sha1)"
            if LauncherSettings.shared.fastVerify && VerifyCache.shared.get(path) == stamp { return true }
            guard Hash.sha1(file: destination) == sha1 else { return false }
            VerifyCache.shared.set(path, stamp)
            return true
        }
        return true
    }
}

/// 已校验文件的记录（路径 → 大小:修改时间:SHA1）
package final class VerifyCache: @unchecked Sendable {
    package static let shared = VerifyCache()
    private let lock = NSLock()
    private var table: [String: String]
    private var dirty = false
    private let url = Paths.cache.appendingPathComponent("verified.json")

    private init() {
        table = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    func get(_ path: String) -> String? { lock.lock(); defer { lock.unlock() }; return table[path] }
    func set(_ path: String, _ stamp: String) { lock.lock(); table[path] = stamp; dirty = true; lock.unlock() }

    package func save() {
        lock.lock(); defer { lock.unlock() }
        guard dirty, let data = try? JSONEncoder().encode(table) else { return }
        try? data.write(to: url, options: .atomic)
        dirty = false
    }
}

/// 下载进度计数器（线程安全）
package final class DownloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _bytes: Int64 = 0
    private var _done = 0
    package var total = 0
    package var totalBytes: Int64 = 0

    package func addBytes(_ n: Int64) { lock.lock(); _bytes += n; lock.unlock() }
    package func finishOne() { lock.lock(); _done += 1; lock.unlock() }
    package var bytes: Int64 { lock.lock(); defer { lock.unlock() }; return _bytes }
    package var done: Int { lock.lock(); defer { lock.unlock() }; return _done }
}

/// 基于 URLSessionDownloadDelegate 的下载引擎，支持字节级进度
package final class DownloadEngine: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    package static let shared = DownloadEngine()

    private struct Pending {
        package let continuation: CheckedContinuation<URL, Error>
        package let counter: DownloadCounter?
        package var written: Int64 = 0
    }

    private let lock = NSLock()
    /// 以任务对象为键（不能用 taskIdentifier：不同 URLSession 的编号会重复）
    private var pending: [ObjectIdentifier: Pending] = [:]
    /// 在初始化时创建（lazy 属性在并发访问下不安全，可能创建出多个 session）
    private var session: URLSession!

    private override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": Net.userAgent]
        c.httpMaximumConnectionsPerHost = 32
        c.urlCache = nil
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }

    /// 下载到临时文件并返回其位置
    package func download(_ url: URL, counter: DownloadCounter?) async throws -> URL {
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                pending[ObjectIdentifier(task)] = Pending(continuation: cont, counter: counter)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func take(_ id: ObjectIdentifier) -> Pending? {
        lock.lock(); defer { lock.unlock() }
        return pending.removeValue(forKey: id)
    }

    package func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        let counter = pending[ObjectIdentifier(downloadTask)]?.counter
        pending[ObjectIdentifier(downloadTask)]?.written = totalBytesWritten
        lock.unlock()
        counter?.addBytes(bytesWritten)
    }

    package func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let p = take(ObjectIdentifier(downloadTask)) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            p.counter?.addBytes(-p.written)
            p.continuation.resume(throwing: LauncherError("HTTP \(http.statusCode): \(downloadTask.originalRequest?.url?.absoluteString ?? "")"))
            return
        }
        let tmp = Paths.cache.appendingPathComponent("dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            p.continuation.resume(returning: tmp)
        } catch {
            p.continuation.resume(throwing: error)
        }
    }

    package func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let p = take(ObjectIdentifier(task)) else { return }
        p.counter?.addBytes(-p.written)
        p.continuation.resume(throwing: error)
    }
}

package enum Downloader {
    /// 并发下载一组文件；已存在且校验通过的文件会被跳过
    package static func run(_ items: [DownloadItem], job: Job?, threads: Int = LauncherSettings.shared.downloadThreads,
                    checkHash: Bool = true) async throws {
        // 去重
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.destination.path).inserted }
        // 先过滤掉已完成的文件
        let todo: [DownloadItem] = await withTaskGroup(of: DownloadItem?.self) { group in
            var result: [DownloadItem] = []
            var iterator = unique.makeIterator()
            for _ in 0..<min(8, unique.count) {
                if let item = iterator.next() { group.addTask { item.isValid(checkHash: checkHash) ? nil : item } }
            }
            while let r = await group.next() {
                if let r { result.append(r) }
                if let item = iterator.next() { group.addTask { item.isValid(checkHash: checkHash) ? nil : item } }
            }
            return result
        }
        defer { VerifyCache.shared.save() }
        guard !todo.isEmpty else { return }
        log("[Download] 需要下载 \(todo.count) 个文件")

        let counter = DownloadCounter()
        counter.total = todo.count
        counter.totalBytes = todo.reduce(0) { $0 + ($1.size ?? 0) }
        let monitor = Task { @MainActor in
            var lastBytes: Int64 = 0
            var lastTime = Date()
            while !Task.isCancelled {
                let b = counter.bytes
                let now = Date()
                let dt = now.timeIntervalSince(lastTime)
                if dt > 0.4 {
                    job?.speed = Double(b - lastBytes) / dt
                    lastBytes = b
                    lastTime = now
                }
                if counter.totalBytes > 0 {
                    job?.fileFraction = min(1, Double(b) / Double(counter.totalBytes))
                } else {
                    job?.fileFraction = Double(counter.done) / Double(max(1, counter.total))
                }
                job?.fileText = "\(counter.done) / \(counter.total)"
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { monitor.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = todo.makeIterator()
            for _ in 0..<min(max(1, threads), todo.count) {
                if let item = iterator.next() { group.addTask { try await fetch(item, counter: counter) } }
            }
            while try await group.next() != nil {
                if let item = iterator.next() { group.addTask { try await fetch(item, counter: counter) } }
            }
        }
        await MainActor.run { job?.fileFraction = 1; job?.speed = 0 }
    }

    package static func fetch(_ item: DownloadItem, counter: DownloadCounter? = nil) async throws {
        var lastError: Error = LauncherError("No URL for \(item.destination.lastPathComponent)")
        let fm = FileManager.default
        for attempt in 0..<(item.urls.count * 2) {
            try Task.checkCancellation()
            let u = item.urls[attempt % item.urls.count]
            guard let url = URL(string: u) else { continue }
            if LauncherSettings.shared.debugLog { log("[Download] 开始 \(u)") }
            do {
                let tmp = try await DownloadEngine.shared.download(url, counter: counter)
                defer { try? fm.removeItem(at: tmp) }
                if let sha1 = item.sha1, !sha1.isEmpty, let actual = Hash.sha1(file: tmp), actual != sha1 {
                    throw LauncherError("SHA1 mismatch: \(item.destination.lastPathComponent)")
                }
                try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: item.destination.path) { try fm.removeItem(at: item.destination) }
                try fm.moveItem(at: tmp, to: item.destination)
                if let sha1 = item.sha1, !sha1.isEmpty,
                   let attr = try? fm.attributesOfItem(atPath: item.destination.path),
                   let size = attr[.size] as? Int64, let date = attr[.modificationDate] as? Date {
                    VerifyCache.shared.set(item.destination.path, "\(size):\(Int(date.timeIntervalSince1970)):\(sha1)")
                }
                counter?.finishOne()
                return
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { throw CancellationError() }
                lastError = error
                log("[Download] 下载失败（第 \(attempt + 1) 次）\(u)：\(error.friendly)")
            }
        }
        throw LauncherError(T("下载 \(item.destination.lastPathComponent) 失败：\(lastError.friendly)", "Failed to download \(item.destination.lastPathComponent): \(lastError.friendly)"))
    }
}
