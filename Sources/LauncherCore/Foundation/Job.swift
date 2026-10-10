import Foundation
import Observation

/// 一个后台任务（安装版本、下载 Java、下载 Mod 等），在“下载管理”中显示
@MainActor
@Observable
package final class Job: Identifiable {
    package enum State { case running, success, failed, cancelled }

    package let id = UUID()
    package let title: String
    package var stage: String = ""
    /// 阶段进度：当前阶段序号 / 总阶段数
    package var stageIndex = 0
    package var stageCount = 1
    /// 当前阶段内的文件下载进度
    package var fileFraction: Double = 0
    package var fileText: String = ""
    package var speed: Double = 0
    package var state: State = .running
    package var error: String?
    @ObservationIgnored package var task: Task<Void, Never>?

    package init(title: String) { self.title = title }

    package var fraction: Double {
        guard stageCount > 0 else { return 0 }
        if state == .success { return 1 }
        return min(1, (Double(stageIndex) + fileFraction) / Double(stageCount))
    }

    package func enter(_ stage: String, index: Int, of count: Int) {
        self.stage = stage
        stageIndex = index
        stageCount = count
        fileFraction = 0
        fileText = ""
    }

    package func cancel() {
        task?.cancel()
    }

    package static func formatSpeed(_ bytesPerSecond: Double) -> String { formatSize(bytesPerSecond) + "/s" }

    package static func formatSize(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var v = max(0, bytes)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: "%.1f %@", v, units[i])
    }
}
