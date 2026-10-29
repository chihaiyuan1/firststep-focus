import Foundation

public struct HabitReminderReceipt: Codable, Identifiable, Equatable {
    public var habitID: String
    public var day: String
    public var dueAt: Double
    public var eligibleAt: Double
    public var dismissed: Bool
    public var id: String { "\(habitID):\(day)" }

    public init(habitID: String, day: String, dueAt: Double, eligibleAt: Double, dismissed: Bool = false) {
        self.habitID = habitID; self.day = day; self.dueAt = dueAt
        self.eligibleAt = eligibleAt; self.dismissed = dismissed
    }
}

extension HabitData {
    /// The app owns focus gating and panel presentation. Persisted receipts remain queued here.
    public func pendingReminders(now: Double, calendar: Calendar = .current) -> [HabitReminderReceipt] {
        guard now.isFinite else { return [] }
        let today = HabitDates.day(at: now, calendar: calendar)
        return reminders.filter { receipt in
            guard receipt.day == today, !receipt.dismissed, receipt.eligibleAt <= now,
                  receipt.dueAt <= now, completion(habitID: receipt.habitID, day: today) == nil,
                  let habit = habits.first(where: { $0.id == receipt.habitID }),
                  let rule = habit.rule(on: today), rule.reminderMinute != nil,
                  rule.isPlanned(on: today, calendar: calendar) else { return false }
            return true
        }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
    }
}

extension HabitDates {
    /// In a spring gap use the next valid wall time; in a fall overlap use its first occurrence.
    static func reminderTime(on day: String, minute: Int, calendar: Calendar) -> Double? {
        guard let start = date(for: day, calendar: calendar) else { return nil }
        let local = gregorian(calendar)
        guard let result = local.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                      of: start, matchingPolicy: .nextTime,
                                      repeatedTimePolicy: .first, direction: .forward),
              self.day(at: result.timeIntervalSince1970, calendar: local) == day else { return nil }
        return result.timeIntervalSince1970
    }
}
