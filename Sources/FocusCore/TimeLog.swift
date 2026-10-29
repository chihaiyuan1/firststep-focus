import Foundation

public struct TimeEntry: Codable, Identifiable, Equatable {
    public var id: String
    public var day: String
    public var startMinute: Int
    public var endMinute: Int
    public var title: String
    public var note: String
    public var color: String
    public var deletedAt: Double?
    public var taskID: String?
    public var taskTitleSnapshot: String?
    public init(id: String = UUID().uuidString, day: String, startMinute: Int, endMinute: Int, title: String, note: String = "", color: String = "violet", taskID: String? = nil, taskTitleSnapshot: String? = nil) throws {
        self.id = id; self.day = day; self.startMinute = startMinute; self.endMinute = endMinute
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines); self.note = note; self.color = color; self.taskID = taskID; self.taskTitleSnapshot = taskTitleSnapshot
        try validate()
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 100 else { throw FocusError("记录编号无效") }
        guard taskID.map({ !$0.isEmpty && $0.count <= 100 }) != false else { throw FocusError("关联任务编号无效") }
        guard taskTitleSnapshot.map({ taskID != nil && !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count <= 120 }) != false else { throw FocusError("关联任务名称无效") }
        guard TimeGrid.date(for: day) != nil else { throw FocusError("请选择有效日期") }
        guard startMinute >= 420, endMinute <= 1200, endMinute > startMinute else { throw FocusError("起止时间需在 07:00–20:00 内，结束要晚于开始") }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120 else { throw FocusError("请填写事情，最多 120 字") }
        guard note.count <= 1000 else { throw FocusError("备注最多 1000 字") }
        guard TimeGrid.colors.contains(color) else { throw FocusError("请选择一种记录颜色") }
    }
    public func linkedTaskTitle(tasks: [FocusTask]) -> String? {
        guard let taskID else { return nil }
        return taskTitleSnapshot ?? tasks.first(where: { $0.id == taskID })?.title
    }
}
public struct TimePlacement: Equatable {
    public var id: String; public var lane: Int; public var laneCount: Int
}
public enum TimeGrid {
    public static let startMinute = 420, endMinute = 1200
    public static let colors = ["violet", "sky", "mint", "rose", "amber"]
    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian); result.timeZone = calendar.timeZone; return result
    }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = gregorian(calendar)
        f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    public static func date(for key: String, calendar: Calendar = .current) -> Date? {
        guard key.count == 10 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = gregorian(calendar)
        f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let date = f.date(from: key), f.string(from: date) == key else { return nil }; return date
    }
    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let c = gregorian(calendar), day = c.startOfDay(for: date)
        let offset = (c.component(.weekday, from: day) + 5) % 7
        guard let monday = c.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: monday) }
    }
    public static func selection(fromY: Double, toY: Double, hourHeight: Double) -> (Int, Int) {
        guard hourHeight > 0, hourHeight.isFinite, fromY.isFinite, toY.isFinite else { return (420,450) }
        let low = max(0, min(780, min(fromY, toY) / hourHeight * 60))
        let high = max(0, min(780, max(fromY, toY) / hourHeight * 60))
        let start = min(1170, 420 + Int(floor(low / 30)) * 30)
        let end = min(1200, max(start + 30, 420 + Int(ceil(high / 30)) * 30))
        return (start,end)
    }
    public static func moved(_ entry: TimeEntry, deltaMinutes: Int, dayOffset: Int = 0, calendar: Calendar = .current) -> TimeEntry {
        var result = entry
        let duration = entry.endMinute - entry.startMinute
        let maxStart = ((1200 - duration) / 30) * 30
        let snapped = Int((Double(entry.startMinute + deltaMinutes) / 30).rounded()) * 30
        result.startMinute = max(420, min(maxStart, snapped)); result.endMinute = result.startMinute + duration
        if let day = date(for: entry.day, calendar: calendar), let moved = gregorian(calendar).date(byAdding: .day, value: dayOffset, to: day) { result.day = dayKey(moved, calendar: calendar) }
        return result
    }
    public static func resized(_ entry: TimeEntry, edge: String, deltaMinutes: Int) -> TimeEntry {
        var result = entry
        if edge == "start" {
            let snapped = Int((Double(entry.startMinute + deltaMinutes) / 30).rounded()) * 30
            let latest = ((entry.endMinute - 1) / 30) * 30
            let candidate = max(420, min(latest, snapped))
            if deltaMinutes <= 0 || candidate >= entry.startMinute { result.startMinute = candidate }
        } else if edge == "end" {
            let snapped = Int((Double(entry.endMinute + deltaMinutes) / 30).rounded()) * 30
            let earliest = Int(ceil(Double(entry.startMinute + 1) / 30)) * 30
            let candidate = min(1200, max(earliest, snapped))
            if deltaMinutes >= 0 || candidate <= entry.endMinute { result.endMinute = candidate }
        }
        return result
    }
    public static func placements(_ entries: [TimeEntry], minimumDuration: Int = 0) -> [TimePlacement] {
        var result: [TimePlacement] = []
        for dayEntries in Dictionary(grouping: entries.filter { $0.deletedAt == nil }, by: \.day).values {
            let sorted = dayEntries.sorted { ($0.startMinute, $0.endMinute, $0.id) < ($1.startMinute, $1.endMinute, $1.id) }
            var cluster: [TimeEntry] = [], clusterEnd = 0
            func flush() {
                var ends: [Int] = [], placements: [(String,Int)] = []
                for entry in cluster {
                    let lane = ends.firstIndex(where: { $0 <= entry.startMinute }) ?? ends.count
                    if lane == ends.count { ends.append(max(entry.endMinute, entry.startMinute + minimumDuration)) } else { ends[lane] = max(entry.endMinute, entry.startMinute + minimumDuration) }
                    placements.append((entry.id,lane))
                }
                result += placements.map { TimePlacement(id: $0.0, lane: $0.1, laneCount: ends.count) }
            }
            for entry in sorted {
                if !cluster.isEmpty && entry.startMinute >= clusterEnd { flush(); cluster = []; clusterEnd = 0 }
                cluster.append(entry); clusterEnd = max(clusterEnd, max(entry.endMinute, entry.startMinute + minimumDuration))
            }
            flush()
        }
        return result
    }
}
