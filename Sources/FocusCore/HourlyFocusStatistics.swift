import Foundation

public struct HourlyFocusStatistics {
    public let seconds: [Double]
    public init(records: [FocusRecord], ending now: Date, days: Int, calendar: Calendar = .current) {
        var result = Array(repeating: 0.0, count: 24)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        for record in records where record.startAt.isFinite && record.startAt >= start.timeIntervalSince1970 && record.startAt <= now.timeIntervalSince1970 {
            let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: record.startAt))
            guard (0..<24).contains(hour), record.focusSeconds.isFinite else { continue }
            result[hour] += max(0, record.focusSeconds)
        }
        seconds = result
    }
}
