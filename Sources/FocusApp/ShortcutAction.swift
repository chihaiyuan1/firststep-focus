import Foundation
import FocusCore

/// UI actions are separate from the two destinations used for collecting titles.
enum ShortcutAction: String, CaseIterable, Codable, CodingKey {
    case today, inbox, toggleMain, startFocus, toggleFloat
    var shortcutTitle: String {
        switch self {
        case .today: return "添加今日任务"
        case .inbox: return "添加收集箱事项"
        case .toggleMain: return "显示／隐藏主窗口"
        case .startFocus: return "开始当前选中的任务"
        case .toggleFloat: return "显示／隐藏悬浮计时窗"
        }
    }
    var subtitle: String {
        switch self {
        case .today: return "准备今天推进的事"
        case .inbox: return "临时想到、不急着做的事"
        case .toggleMain: return "随时查看任务，看完回到工作"
        case .startFocus: return "沿用当前任务或小任务和时长"
        case .toggleFloat: return "专注或休息期间，按需查看进度"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .inbox: return "tray"
        case .toggleMain: return "macwindow"
        case .startFocus: return "play.circle"
        case .toggleFloat: return "pip"
        }
    }
    var hotKeyID: UInt32 {
        switch self { case .today: return 1; case .inbox: return 2; case .toggleMain: return 3; case .startFocus: return 4; case .toggleFloat: return 5 }
    }
    var captureDestination: CaptureDestination? {
        switch self { case .today: return .today; case .inbox: return .inbox; default: return nil }
    }
}

/// A refresh changes panel visibility only when the timer period changes.
struct TimerPanelVisibility {
    private var period: String?
    mutating func refresh(sessionID: String?, breakUntil: Double?) -> Bool? {
        let next = sessionID.map { "focus:\($0)" } ?? breakUntil.map { "rest:\($0)" }
        guard next != period else { return nil }
        period = next
        return next != nil
    }
}
