import Foundation
import SwiftUI
import FocusCore

@MainActor final class HabitModel: ObservableObject {
    @Published private(set) var data = HabitData()
    @Published var selectedID: String?
    @Published var monthDate: Date
    @Published var error: String?
    private(set) var now: Double
    let calendar: Calendar
    let store: HabitStore
    var onChange: (() -> Void)?
    private var lastPollAt: Double?
    private var storageAvailable = false

    init(directory: URL, calendar: Calendar = .autoupdatingCurrent,
         now: Double = Date().timeIntervalSince1970) {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        localCalendar.locale = Locale(identifier: "zh_Hans_CN")
        self.calendar = localCalendar
        self.now = now
        monthDate = Date(timeIntervalSince1970: now)
        store = HabitStore(directory: directory)
        refresh(now: now, force: true)
    }

    var today: String { HabitDates.day(at: now, calendar: calendar) }
    var selectedHabit: Habit? { data.habits.first { $0.id == selectedID } }
    var todayPlannedCount: Int { data.habits.filter { planned($0) }.count }
    var todayCompletedCount: Int {
        data.habits.filter { planned($0) && data.completion(habitID: $0.id, day: today) != nil }.count
    }
    private func planned(_ habit: Habit) -> Bool {
        guard today >= HabitDates.day(at: habit.createdAt, calendar: calendar),
              let rule = habit.rule(on: today), let weekday = HabitDates.weekday(for: today, calendar: calendar) else { return false }
        return !rule.paused && rule.weekdays.contains(weekday)
    }

    func refresh(now: Double, force: Bool = false) {
        let previousDay = today
        self.now = now
        guard force || lastPollAt == nil || now < lastPollAt! || now - lastPollAt! >= 5 || today != previousDay else { return }
        lastPollAt = now
        do { accept(try store.poll(now: now, calendar: calendar)) }
        catch { storageAvailable = false; self.error = error.localizedDescription }
    }

    private func accept(_ value: HabitData) {
        data = value
        storageAvailable = true
        if !data.habits.contains(where: { $0.id == selectedID }) { selectedID = data.habits.first?.id }
    }

    @discardableResult private func perform(_ update: () throws -> HabitData,
                                          select id: String? = nil, returnToToday: Bool = false) -> Bool {
        do {
            accept(try update())
            if let id { selectedID = id }
            if returnToToday { monthDate = Date(timeIntervalSince1970: now) }
            error = nil
            onChange?()
            return true
        } catch {
            storageAvailable = false
            self.error = error.localizedDescription
            onChange?()
            return false
        }
    }

    @discardableResult func saveHabit(id: String?, draft: HabitDraft) -> Bool {
        do {
            let existing = Set(try store.read().habits.map(\.id))
            let result = try store.saveHabit(id: id, draft: draft, now: now, calendar: calendar)
            accept(result)
            selectedID = id ?? result.habits.first(where: { !existing.contains($0.id) })?.id ?? selectedID
            monthDate = Date(timeIntervalSince1970: now)
            error = nil
            onChange?()
            return true
        } catch {
            storageAvailable = false
            self.error = error.localizedDescription
            onChange?()
            return false
        }
    }

    func setPaused(id: String, paused: Bool) {
        perform { try store.setPaused(id: id, paused: paused, now: now, calendar: calendar) }
    }

    func select(_ id: String) {
        guard data.habits.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func toggleToday(_ id: String) {
        perform({
            let canonical = try store.read()
            return try store.setCompletion(habitID: id, day: today,
                completed: canonical.completion(habitID: id, day: today) == nil,
                now: now, calendar: calendar)
        }, select: id, returnToToday: true)
    }

    @discardableResult func saveCompletion(habitID: String, day: String, actualAmount: String) -> Bool {
        perform({ try store.setCompletion(habitID: habitID, day: day, completed: true,
            actualAmount: actualAmount, now: now, calendar: calendar) }, select: habitID)
    }

    func removeCompletion(habitID: String, day: String) {
        perform({ try store.setCompletion(habitID: habitID, day: day, completed: false,
            now: now, calendar: calendar) }, select: habitID)
    }

    func reminderPresentation(focusActive: Bool, focusStateAvailable: Bool = true) -> HabitReminderPresentation? {
        guard !focusActive, focusStateAvailable, storageAvailable,
              let receipt = data.pendingReminders(now: now, calendar: calendar).first,
              let habit = data.habits.first(where: { $0.id == receipt.habitID }),
              let rule = habit.rule(on: receipt.day) else { return nil }
        return HabitReminderPresentation(id: receipt.id, habitID: habit.id, name: habit.name,
                                         minimumAction: rule.minimumAction, day: receipt.day)
    }

    var pendingReminderCount: Int {
        storageAvailable ? data.pendingReminders(now: now, calendar: calendar).count : 0
    }

    func completeFromReminder(_ id: String) {
        guard let receipt = data.reminders.first(where: { $0.id == id }), receipt.day == today else { return }
        perform({ try store.setCompletion(habitID: receipt.habitID, day: receipt.day, completed: true,
            now: now, calendar: calendar) }, select: receipt.habitID, returnToToday: true)
    }

    func dismissReminder(_ id: String) {
        perform { try store.dismissReminder(id: id, now: now, calendar: calendar) }
    }

    func snoozeReminder(_ id: String) {
        perform { try store.snoozeReminder(id: id, now: now, calendar: calendar) }
    }
}
