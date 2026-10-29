import Foundation

public enum ScheduleTimes {
    public static func reminderWhenMovingPlan(_ reminder: Date, from oldDay: Date, to newDay: Date, calendar: Calendar = .current) -> Date {
        guard calendar.isDate(reminder, inSameDayAs: oldDay) else { return reminder }
        let components = calendar.dateComponents([.hour, .minute, .second], from: reminder)
        return calendar.date(bySettingHour:components.hour ?? 0, minute:components.minute ?? 0, second:components.second ?? 0, of:newDay) ?? reminder
    }
}

func validateSchedule(day: String?, reminderAt: Double?) throws {
    if let day, TimeGrid.date(for: day) == nil { throw FocusError("请选择有效的计划日期") }
    if let reminderAt, (!reminderAt.isFinite || reminderAt < 0 || day == nil) { throw FocusError("提醒时间无效") }
}

public struct PlanningCandidate: Identifiable {
    public let id: String
    public let title: String
    public let isInbox: Bool
    public let scheduledDay: String?
    public init(id: String, title: String, isInbox: Bool, scheduledDay: String?) {
        self.id = id; self.title = title; self.isInbox = isInbox; self.scheduledDay = scheduledDay
    }
}

public struct TaskReminderCandidate {
    public let id: String
    public let title: String
    public let isInbox: Bool
    public let day: String
    public let reminderAt: Double
}

public extension FocusState {
    func nextTaskReminder(now: Double, focusActive: Bool) -> TaskReminderCandidate? {
        dueTaskReminders(now: now, focusActive: focusActive).first
    }
    func dueTaskReminders(now: Double, focusActive: Bool) -> [TaskReminderCandidate] {
        guard !focusActive, now.isFinite else { return [] }
        let inbox = activeInboxItems.compactMap { item -> TaskReminderCandidate? in
            guard let time = item.reminderAt, time <= now, let day = item.scheduledDay else { return nil }
            return TaskReminderCandidate(id: item.id, title: item.title, isInbox: true, day: day, reminderAt: time)
        }
        let pending = tasks.compactMap { task -> TaskReminderCandidate? in
            guard !task.completed, let time = task.reminderAt, time <= now, let day = task.scheduledDay else { return nil }
            return TaskReminderCandidate(id: task.id, title: task.title, isInbox: false, day: day, reminderAt: time)
        }
        return (inbox + pending).sorted { ($0.reminderAt, $0.id) < ($1.reminderAt, $1.id) }
    }
    func visibleTasks(day: String) -> [FocusTask] {
        tasks.filter { !$0.completed && ($0.scheduledDay == nil || $0.scheduledDay! <= day) }
    }
    func planningCandidates(day: String) -> [PlanningCandidate] {
        let inbox = activeInboxItems.filter { $0.scheduledDay == nil || $0.scheduledDay! <= day }
            .map { PlanningCandidate(id: $0.id, title: $0.title, isInbox: true, scheduledDay: $0.scheduledDay) }
        let previous = tasks.filter { !$0.completed && $0.day < day && ($0.scheduledDay == nil || $0.scheduledDay! <= day) }
            .map { PlanningCandidate(id: $0.id, title: $0.title, isInbox: false, scheduledDay: $0.scheduledDay) }
        return previous + inbox
    }
}
