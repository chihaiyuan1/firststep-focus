import Foundation

public struct HabitDraft: Equatable {
    public var name: String
    public var minimumAction: String
    public var anchor: String
    public var weekdays: [Int]
    public var reminderMinute: Int?
    public var paused: Bool

    public init(name: String, minimumAction: String, anchor: String, weekdays: [Int], reminderMinute: Int?, paused: Bool = false) {
        self.name = name; self.minimumAction = minimumAction; self.anchor = anchor
        self.weekdays = weekdays; self.reminderMinute = reminderMinute; self.paused = paused
    }
}

public struct HabitRule: Codable, Equatable {
    public var effectiveDay: String
    public var minimumAction: String
    public var anchor: String
    public var weekdays: [Int]
    public var reminderMinute: Int?
    public var paused: Bool

    public init(effectiveDay: String, minimumAction: String, anchor: String, weekdays: [Int], reminderMinute: Int?, paused: Bool = false) {
        self.effectiveDay = effectiveDay; self.minimumAction = minimumAction; self.anchor = anchor
        self.weekdays = weekdays; self.reminderMinute = reminderMinute; self.paused = paused
    }

    public func isPlanned(on day: String, calendar: Calendar = .current) -> Bool {
        !paused && HabitDates.weekday(for: day, calendar: calendar).map { weekdays.contains($0) } == true
    }
}

public struct Habit: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var createdAt: Double
    public var rules: [HabitRule]

    public init(id: String, name: String, createdAt: Double, rules: [HabitRule]) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.rules = rules
    }

    public func rule(on day: String) -> HabitRule? {
        rules.filter { $0.effectiveDay <= day }.max { $0.effectiveDay < $1.effectiveDay }
    }
}

public struct HabitCompletion: Codable, Identifiable, Equatable {
    public var habitID: String
    public var day: String
    public var name: String
    public var minimumAction: String
    public var actualAmount: String
    public var completedAt: Double
    public var id: String { "\(habitID):\(day)" }

    public init(habitID: String, day: String, name: String, minimumAction: String, actualAmount: String, completedAt: Double) {
        self.habitID = habitID; self.day = day; self.name = name; self.minimumAction = minimumAction
        self.actualAmount = actualAmount; self.completedAt = completedAt
    }
}

public struct HabitData: Codable, Equatable {
    public var schema: Int
    public var habits: [Habit]
    public var completions: [HabitCompletion]
    public var reminders: [HabitReminderReceipt]

    public init() { schema = 1; habits = []; completions = []; reminders = [] }

    public func completion(habitID: String, day: String) -> HabitCompletion? {
        completions.first { $0.habitID == habitID && $0.day == day }
    }
}

/// Day keys always use Gregorian years; only the caller's local timezone is inherited.
public enum HabitDates {
    static func gregorian(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US_POSIX")
        result.timeZone = calendar.timeZone
        return result
    }

    public static func day(at time: Double, calendar: Calendar = .current) -> String {
        guard time.isFinite else { return "" }
        let parts = gregorian(calendar).dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: time))
        guard let year = parts.year, (1...9999).contains(year), let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(for day: String, calendar: Calendar = .current) -> Date? {
        let bytes = Array(day.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(day.prefix(4)), (1...9999).contains(year),
              let month = Int(day.dropFirst(5).prefix(2)), (1...12).contains(month),
              let number = Int(day.suffix(2)), (1...31).contains(number) else { return nil }
        let local = gregorian(calendar)
        guard let date = local.date(from: DateComponents(year: year, month: month, day: number)),
              self.day(at: date.timeIntervalSince1970, calendar: local) == day else { return nil }
        return date
    }

    public static func weekday(for day: String, calendar: Calendar = .current) -> Int? {
        guard let date = date(for: day, calendar: calendar) else { return nil }
        return (gregorian(calendar).component(.weekday, from: date) + 5) % 7 + 1
    }
}
