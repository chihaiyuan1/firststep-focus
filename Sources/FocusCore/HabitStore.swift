import Foundation
import Darwin

private struct HabitStoreFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
private struct HabitSchema: Decodable { let schema: Int }

/// A separate local document. Every mutation rereads canonical data under the same cross-process lock.
public final class HabitStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> HabitData { try transaction(nil) }

    public func saveHabit(id: String?, draft: HabitDraft, now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateTime(now, calendar: calendar)
        if let id { try validateID(id) }
        try validateDraft(draft)
        let today = HabitDates.day(at: now, calendar: calendar)
        let rule = HabitRule(effectiveDay: today, minimumAction: draft.minimumAction.trimmingCharacters(in: .whitespacesAndNewlines),
                             anchor: draft.anchor.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: draft.weekdays.sorted(),
                             reminderMinute: draft.reminderMinute, paused: draft.paused)
        return try transaction { data in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id {
                guard let index = data.habits.firstIndex(where: { $0.id == id }),
                      today >= HabitDates.day(at: data.habits[index].createdAt, calendar: calendar) else { throw self.failure("找不到可修改的习惯") }
                data.habits[index].name = name
                self.replaceRule(rule, in: &data.habits[index])
            } else {
                data.habits.append(Habit(id: UUID().uuidString, name: name, createdAt: now, rules: [rule]))
            }
            self.reconcile(&data, now: now, calendar: calendar)
        }
    }

    public func setPaused(id: String, paused: Bool, now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateID(id); try validateTime(now, calendar: calendar)
        let today = HabitDates.day(at: now, calendar: calendar)
        return try transaction { data in
            guard let index = data.habits.firstIndex(where: { $0.id == id }),
                  var rule = data.habits[index].rule(on: today) else { throw self.failure("找不到可修改的习惯") }
            guard rule.paused != paused else { return }
            rule.effectiveDay = today; rule.paused = paused
            self.replaceRule(rule, in: &data.habits[index])
            self.reconcile(&data, now: now, calendar: calendar)
        }
    }

    public func setCompletion(habitID: String, day: String, completed: Bool, actualAmount: String? = nil, now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateID(habitID); try validateTime(now, calendar: calendar)
        guard HabitDates.date(for: day, calendar: calendar) != nil else { throw failure("习惯记录日期无效") }
        if let actualAmount, actualAmount.count > 2000 { throw failure("实际完成内容最多可输入2000个字") }
        let today = HabitDates.day(at: now, calendar: calendar)
        guard day <= today else { throw failure("还不能记录未来的日期") }
        return try transaction { data in
            guard let habit = data.habits.first(where: { $0.id == habitID }),
                  day >= HabitDates.day(at: habit.createdAt, calendar: calendar),
                  let rule = habit.rule(on: day) else { throw self.failure("该日期还没有这个习惯") }
            if let index = data.completions.firstIndex(where: { $0.habitID == habitID && $0.day == day }) {
                if completed {
                    if let actualAmount { data.completions[index].actualAmount = actualAmount }
                } else { data.completions.remove(at: index) }
            } else if completed {
                data.completions.append(HabitCompletion(habitID: habitID, day: day, name: habit.name, minimumAction: rule.minimumAction,
                                                        actualAmount: actualAmount ?? "", completedAt: now))
            }
            if completed {
                if let index = data.reminders.firstIndex(where: { $0.habitID == habitID && $0.day == day }) {
                    data.reminders[index].dismissed = true
                } else if day == today, let minute = rule.reminderMinute,
                          let due = HabitDates.reminderTime(on: day, minute: minute, calendar: calendar) {
                    // Completion before a reminder also handles the day, so undo cannot replay it.
                    data.reminders.append(HabitReminderReceipt(habitID: habitID, day: day, dueAt: due, eligibleAt: due, dismissed: true))
                }
            }
            self.reconcile(&data, now: now, calendar: calendar)
        }
    }

    public func poll(now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateTime(now, calendar: calendar)
        return try transaction { self.reconcile(&$0, now: now, calendar: calendar) }
    }

    public func dismissReminder(id: String, now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateTime(now, calendar: calendar)
        return try transaction { data in
            guard let index = data.reminders.firstIndex(where: { $0.id == id }),
                  data.reminders[index].day == HabitDates.day(at: now, calendar: calendar) else { return }
            data.reminders[index].dismissed = true
        }
    }

    public func snoozeReminder(id: String, now: Double = Date().timeIntervalSince1970, calendar: Calendar = .current) throws -> HabitData {
        try validateTime(now, calendar: calendar)
        return try transaction { data in
            guard let index = data.reminders.firstIndex(where: { $0.id == id }),
                  data.pendingReminders(now: now, calendar: calendar).contains(where: { $0.id == id }) else { return }
            data.reminders[index].eligibleAt = now + 600
        }
    }

    private func replaceRule(_ rule: HabitRule, in habit: inout Habit) {
        if let index = habit.rules.firstIndex(where: { $0.effectiveDay == rule.effectiveDay }) { habit.rules[index] = rule }
        else { habit.rules.append(rule) }
        habit.rules.sort { $0.effectiveDay < $1.effectiveDay }
    }

    private func reconcile(_ data: inout HabitData, now: Double, calendar: Calendar) {
        let today = HabitDates.day(at: now, calendar: calendar)
        for habit in data.habits {
            let existing = data.reminders.firstIndex { $0.habitID == habit.id && $0.day == today }
            if data.completion(habitID: habit.id, day: today) != nil {
                if let existing { data.reminders[existing].dismissed = true }
                continue
            }
            guard let rule = habit.rule(on: today), rule.isPlanned(on: today, calendar: calendar),
                  let minute = rule.reminderMinute,
                  let due = HabitDates.reminderTime(on: today, minute: minute, calendar: calendar) else { continue }
            if let existing {
                // A handled day stays handled. A schedule edit replaces an unhandled due time.
                if !data.reminders[existing].dismissed && data.reminders[existing].dueAt != due {
                    data.reminders[existing].dueAt = due
                    data.reminders[existing].eligibleAt = due
                }
            } else if due <= now {
                guard today != HabitDates.day(at: habit.createdAt, calendar: calendar) || due >= habit.createdAt else { continue }
                data.reminders.append(HabitReminderReceipt(habitID: habit.id, day: today, dueAt: due, eligibleAt: due))
            }
        }
    }

    private func validateID(_ id: String) throws {
        guard !id.isEmpty, id.count <= 100 else { throw failure("习惯标识无效") }
    }

    private func validateTime(_ time: Double, calendar: Calendar) throws {
        guard time.isFinite, !HabitDates.day(at: time, calendar: calendar).isEmpty else { throw failure("习惯时间无效") }
    }

    private func validateDraft(_ draft: HabitDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.name.count <= 60 else { throw failure("习惯名称不能为空，最多60个字") }
        guard !draft.minimumAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.minimumAction.count <= 180 else { throw failure("最低标准不能为空，最多180个字") }
        guard draft.anchor.count <= 180 else { throw failure("触发场景最多180个字") }
        guard !draft.weekdays.isEmpty, Set(draft.weekdays).count == draft.weekdays.count,
              draft.weekdays.allSatisfy({ (1...7).contains($0) }) else { throw failure("请选择不重复的有效执行日") }
        guard draft.reminderMinute.map({ (0...1439).contains($0) }) != false else { throw failure("提醒时间无效") }
    }

    private func validate(_ data: HabitData) throws {
        guard data.schema == 1 else { throw failure("习惯数据版本不兼容，已保留原文件，请先升级应用。") }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var habitIDs = Set<String>()
        for habit in data.habits {
            try validateID(habit.id)
            try validateTime(habit.createdAt, calendar: utc)
            guard habitIDs.insert(habit.id).inserted, !habit.rules.isEmpty,
                  !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, habit.name.count <= 60 else { throw failure("习惯数据包含重复或无效记录") }
            var days = Set<String>()
            for rule in habit.rules {
                guard HabitDates.date(for: rule.effectiveDay, calendar: utc) != nil,
                      days.insert(rule.effectiveDay).inserted else { throw failure("习惯规则包含无效日期或重复版本") }
                try validateDraft(HabitDraft(name: habit.name, minimumAction: rule.minimumAction, anchor: rule.anchor,
                                            weekdays: rule.weekdays, reminderMinute: rule.reminderMinute, paused: rule.paused))
            }
        }
        var completionIDs = Set<String>()
        for completion in data.completions {
            guard habitIDs.contains(completion.habitID), completionIDs.insert(completion.id).inserted,
                  HabitDates.date(for: completion.day, calendar: utc) != nil, completion.completedAt.isFinite,
                  !completion.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, completion.name.count <= 60,
                  !completion.minimumAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, completion.minimumAction.count <= 180,
                  completion.actualAmount.count <= 2000 else { throw failure("习惯完成记录包含无效内容或重复日期") }
        }
        var reminderIDs = Set<String>()
        for reminder in data.reminders {
            guard habitIDs.contains(reminder.habitID), reminderIDs.insert(reminder.id).inserted,
                  HabitDates.date(for: reminder.day, calendar: utc) != nil,
                  reminder.dueAt.isFinite, reminder.eligibleAt.isFinite, reminder.eligibleAt >= reminder.dueAt else { throw failure("习惯提醒包含无效时间或重复日期") }
        }
    }

    private func transaction(_ change: ((inout HabitData) throws -> Void)?) throws -> HabitData {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw failure("无法打开习惯数据目录") }
        defer { close(directoryFD) }
        var directoryStatus = stat()
        guard fstat(directoryFD, &directoryStatus) == 0, directoryStatus.st_uid == geteuid(), fchmod(directoryFD, 0o700) == 0 else { throw failure("无法保护习惯数据目录") }
        let lockFD = openat(directoryFD, "habits.lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw failure("无法打开习惯数据锁") }
        defer { close(lockFD) }
        var lockStatus = stat()
        guard fstat(lockFD, &lockStatus) == 0, lockStatus.st_mode & S_IFMT == S_IFREG,
              lockStatus.st_uid == geteuid(), fchmod(lockFD, 0o600) == 0, flock(lockFD, LOCK_EX) == 0 else { throw failure("无法锁定习惯数据") }
        defer { flock(lockFD, LOCK_UN) }

        var data = HabitData()
        // Nonblocking open lets fstat reject a FIFO/device without stalling the main refresh.
        let fileFD = openat(directoryFD, "habits.json", O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if fileFD >= 0 {
            defer { close(fileFD) }
            var status = stat()
            guard fstat(fileFD, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_uid == geteuid() else { throw failure("习惯数据不是有效的本机普通文件，已保留原文件。") }
            let bytes: Data
            do { bytes = try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data() }
            catch { throw failure("习惯数据无法读取，已保留原文件。") }
            let version: Int
            do { version = try JSONDecoder().decode(HabitSchema.self, from: bytes).schema }
            catch { throw failure("习惯数据无法读取，已保留原文件：\(directory.appendingPathComponent("habits.json").path)") }
            guard version == 1 else { throw failure("习惯数据版本不兼容，已保留原文件，请先升级应用。") }
            do { data = try JSONDecoder().decode(HabitData.self, from: bytes); try validate(data) }
            catch { throw failure("习惯数据包含无效内容，已保留原文件：\(directory.appendingPathComponent("habits.json").path)") }
        } else if errno != ENOENT { throw failure("无法读取习惯数据，已保留原文件。") }
        if let change {
            let original = data
            try change(&data)
            try validate(data)
            if data != original {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try atomicWrite(encoder.encode(data), directoryFD: directoryFD)
            }
        }
        return data
    }

    private func atomicWrite(_ data: Data, directoryFD: Int32) throws {
        let name = ".habits-\(UUID().uuidString).tmp"
        let descriptor = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw failure("无法建立习惯数据临时文件") }
        defer { close(descriptor); unlinkat(directoryFD, name, 0) }
        guard fchmod(descriptor, 0o600) == 0 else { throw failure("无法保护习惯数据文件") }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("习惯数据写入失败，原文件未改动") }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw failure("习惯数据写入失败，原文件未改动") }
        guard renameat(directoryFD, name, directoryFD, "habits.json") == 0 else { throw failure("无法保存习惯数据，原文件未改动") }
        guard fsync(directoryFD) == 0 else { throw failure("习惯数据已保存，但目录同步失败，请重新检查。") }
    }

    private func failure(_ message: String) -> HabitStoreFailure { HabitStoreFailure(message: message) }
}
