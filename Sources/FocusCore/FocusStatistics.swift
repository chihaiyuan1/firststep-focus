import Foundation

public enum FocusStatisticsScope: String, CaseIterable, Sendable {
    case day, week, month

    public var title: String {
        switch self { case .day: return "日"; case .week: return "周"; case .month: return "月" }
    }
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        switch self {
        case .day:
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return DateInterval(start: day, end: calendar.startOfDay(for: next))
        case .week:
            let offset = (calendar.component(.weekday, from: day) + 5) % 7
            // A day whose midnight was skipped can start at 01:00; do not carry that hour into Monday.
            let monday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: day) ?? day)
            let next = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
            return DateInterval(start: monday, end: calendar.startOfDay(for: next))
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: day, duration: 0)
        }
    }
    public func shiftedDate(from date: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        let start = interval(containing: date, calendar: calendar).start
        let next = calendar.date(byAdding: self == .month ? .month : .day,
                                 value: offset * (self == .week ? 7 : 1), to: start) ?? start
        return calendar.startOfDay(for: next)
    }
}

public struct FocusStatisticsBucket: Identifiable {
    public let start: Date
    public let end: Date
    public var focusSeconds: Double = 0
    public var completedCount: Int = 0
    public var id: Date { start }
}

public struct FocusStatistics {
    public let scope: FocusStatisticsScope
    public let interval: DateInterval
    public let buckets: [FocusStatisticsBucket]
    public var totalFocusSeconds: Double { buckets.reduce(0) { $0 + $1.focusSeconds } }
    public var completedCount: Int { buckets.reduce(0) { $0 + $1.completedCount } }

    public init(records: [FocusRecord], on date: Date, scope: FocusStatisticsScope, calendar: Calendar = .current) {
        self.scope = scope
        interval = scope.interval(containing: date, calendar: calendar)
        var result: [FocusStatisticsBucket] = []
        var cursor = interval.start
        while cursor < interval.end {
            let days = scope == .month ? 7 - (calendar.component(.weekday, from: cursor) + 5) % 7 : 1
            guard let next = calendar.date(byAdding: .day, value: days, to: cursor), next > cursor else { break }
            let end = min(calendar.startOfDay(for: next), interval.end)
            result.append(FocusStatisticsBucket(start: cursor, end: end))
            cursor = end
        }
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        for record in records where record.startAt >= start && record.startAt < end {
            if let index = result.firstIndex(where: { record.startAt >= $0.start.timeIntervalSince1970 && record.startAt < $0.end.timeIntervalSince1970 }) {
                result[index].focusSeconds += max(0, record.focusSeconds.isFinite ? record.focusSeconds : 0)
                if record.finished { result[index].completedCount += 1 }
            }
        }
        buckets = result
    }
}
