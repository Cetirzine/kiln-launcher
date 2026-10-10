import Foundation
import CoreServices

/// 用 FSEvents 监视游戏目录，版本或 Mod 发生变化时回调（已防抖）
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func watch(_ folder: URL) {
        stop()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            if list.prefix(count).contains(where: FolderWatcher.isRelevant) { watcher.schedule() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// 只关心版本与 Mod 的变化；忽略下载与运行中频繁变动的目录
    static func isRelevant(_ path: String) -> Bool {
        let ignored = ["/assets/", "/libraries/", "/logs/", "/.kiln/", "-natives", "/crash-reports/", "/screenshots/",
                       "/saves/", "/config/", "/.fabric/", "/options.txt", "/usercache.json", "/.DS_Store"]
        if ignored.contains(where: path.contains) { return false }
        return path.contains("/versions/") || path.hasSuffix("/versions") || path.contains("/mods/") || path.hasSuffix("/mods")
            || path.contains("/resourcepacks/") || path.contains("/shaderpacks/")
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
