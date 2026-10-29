import Foundation

public enum CaptureDestination: String, CaseIterable, Codable {
    case today, inbox
    public var title: String { self == .today ? "今天的事" : "收集箱" }
    public var shortcutTitle: String { self == .today ? "添加今日任务" : "添加收集箱事项" }
    public var hotKeyID: UInt32 { self == .today ? 1 : 2 }
}
