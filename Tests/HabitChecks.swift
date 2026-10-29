import Foundation
import Darwin

private var failures: [String] = []
private var assertions = 0
private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    assertions += 1
    do { if try !condition() { failures.append(name) } } catch { failures.append("\(name): \(error)") }
}
private func rejects(_ name: String, _ body: () throws -> Void) {
    assertions += 1
    do { try body(); failures.append(name) } catch {}
}
private func scenario(_ name: String, _ body: () throws -> Void) {
    do { try body() } catch { failures.append("\(name): \(error)") }
}
private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}
private let shanghai = calendar()
private func timestamp(_ value: String) -> Double { ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 }
private let morning = timestamp("2026-10-28T08:00:00+08:00")
private let noon = timestamp("2026-10-28T12:00:00+08:00")
private let tomorrow = timestamp("2026-10-29T12:00:00+08:00")
private func draft(_ name: String = "阅读", minimum: String = "读两页", weekdays: [Int] = [1,2,3,4,5,6,7], reminder: Int? = 9 * 60, paused: Bool = false) -> HabitDraft {
    HabitDraft(name: name, minimumAction: minimum, anchor: "早餐后", weekdays: weekdays, reminderMinute: reminder, paused: paused)
}
private func isolated(_ body: (URL, HabitStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("firststep-habits-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory, HabitStore(directory: directory))
}
private func permissions(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue & 0o777
}

@main struct HabitChecks {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--reject-nonregular" {
            do { _ = try HabitStore(directory: URL(fileURLWithPath: CommandLine.arguments[2])).read(); exit(1) }
            catch { return }
        }
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--worker" {
            _ = try HabitStore(directory: URL(fileURLWithPath: CommandLine.arguments[2])).saveHabit(id: nil, draft: draft("process \(CommandLine.arguments[3])"), now: morning, calendar: shanghai)
            return
        }
        scenario("Gregorian local dates") {
            check(HabitDates.day(at: timestamp("2026-01-01T00:30:00+08:00"), calendar: shanghai) == "2026-01-01", "date uses caller timezone")
            check(HabitDates.day(at: timestamp("2026-01-01T00:30:00+08:00"), calendar: calendar("America/Los_Angeles")) == "2025-12-31", "same instant crosses year locally")
            check(HabitDates.weekday(for: "2026-10-26", calendar: shanghai) == 1, "weekday Monday is one")
            check(HabitDates.weekday(for: "2026-11-01", calendar: shanghai) == 7, "weekday Sunday is seven")
            check(HabitDates.date(for: "2024-02-29", calendar: shanghai) != nil, "leap day accepted")
            for invalid in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "2026-1-01", "0000-01-01", "2026-10-28x", "２０２６-10-28"] {
                check(HabitDates.date(for: invalid, calendar: shanghai) == nil, "invalid exact day rejected: \(invalid)")
            }
            var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = shanghai.timeZone
            check(HabitDates.day(at: noon, calendar: buddhist) == "2026-10-28", "non-Gregorian caller retains Gregorian day keys")
            let ny = calendar("America/New_York")
            check(HabitDates.day(at: HabitDates.date(for: "2026-03-08", calendar: ny)!.timeIntervalSince1970, calendar: ny) == "2026-03-08", "DST start roundtrip")
            check(HabitDates.day(at: HabitDates.date(for: "2026-11-01", calendar: ny)!.timeIntervalSince1970, calendar: ny) == "2026-11-01", "DST end roundtrip")
        }
        scenario("empty read and real save") {
            try isolated { directory, store in
                check(try store.read() == HabitData(), "missing store starts empty")
                check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("habits.json").path), "read creates no data document")
                _ = try store.poll(now: noon, calendar: shanghai)
                check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("habits.json").path), "empty idle poll creates no data document")
                let data = try store.saveHabit(id: nil, draft: draft("  阅读  "), now: morning, calendar: shanghai)
                check(data.habits.count == 1 && data.habits[0].name == "阅读", "save creates only user habit and trims name")
                check(data.schema == 1 && data.completions.isEmpty && data.reminders.isEmpty, "separate schema and no fake records")
                check(try store.read() == data, "new store data survives reload")
                check(try permissions(directory) == 0o700 && permissions(directory.appendingPathComponent("habits.json")) == 0o600 && permissions(directory.appendingPathComponent("habits.lock")) == 0o600, "directory data lock use owner permissions")
            }
        }
        scenario("rule versions and snapshots") {
            try isolated { _, store in
                let id = try store.saveHabit(id: nil, draft: draft(), now: morning, calendar: shanghai).habits[0].id
                _ = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, actualAmount: "读了三页", now: noon, calendar: shanghai)
                _ = try store.saveHabit(id: id, draft: draft("书", minimum: "读五页"), now: tomorrow, calendar: shanghai)
                let edited = try store.saveHabit(id: id, draft: draft("书", minimum: "读六页"), now: tomorrow + 1, calendar: shanghai)
                check(edited.habits[0].rules.count == 2, "multiple edits on same effective day replace one rule version")
                check(edited.habits[0].rule(on: "2026-10-28")?.minimumAction == "读两页" && edited.habits[0].rule(on: "2026-10-29")?.minimumAction == "读六页", "edits affect today forward and preserve earlier criteria")
                check(edited.habits[0].rule(on: "2026-10-27") == nil, "no rule before creation")
                let snapshot = edited.completion(habitID: id, day: "2026-10-28")!
                check(snapshot.name == "阅读" && snapshot.minimumAction == "读两页" && snapshot.actualAmount == "读了三页", "completion snapshots survive renamed criteria")
                let repeated = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, now: tomorrow, calendar: shanghai)
                check(repeated.completions.count == 1 && repeated.completions[0] == snapshot, "repeat complete is idempotent and preserves amount/time")
                let changed = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, actualAmount: "补充文字", now: tomorrow, calendar: shanghai)
                check(changed.completions[0].actualAmount == "补充文字" && changed.completions[0].completedAt == noon && changed.completions[0].minimumAction == "读两页", "editing amount retains completion snapshot and original completion time")
                _ = try store.setPaused(id: id, paused: true, now: tomorrow, calendar: shanghai)
                let paused = try store.read().habits[0]
                check(paused.rule(on: "2026-10-28")?.paused == false && paused.rule(on: "2026-10-29")?.paused == true, "pause versions effective day")
                _ = try store.setPaused(id: id, paused: false, now: tomorrow, calendar: shanghai)
                let undone = try store.setCompletion(habitID: id, day: "2026-10-28", completed: false, now: tomorrow, calendar: shanghai)
                check(undone.completions.isEmpty, "undo removes exact habit/day")
                rejects("cannot backfill precreation") { _ = try store.setCompletion(habitID: id, day: "2026-10-27", completed: true, now: tomorrow, calendar: shanghai) }
                rejects("cannot complete future day") { _ = try store.setCompletion(habitID: id, day: "2026-10-30", completed: true, now: tomorrow, calendar: shanghai) }
            }
        }
        scenario("weekday eligibility and history") {
            try isolated { _, store in
                let created = timestamp("2026-10-23T08:00:00+08:00")
                let id = try store.saveHabit(id: nil, draft: draft(weekdays: [1,2,3,4,5]), now: created, calendar: shanghai).habits[0].id
                let voluntary = try store.setCompletion(habitID: id, day: "2026-10-24", completed: true, actualAmount: "周末自愿读了几页", now: noon, calendar: shanghai)
                check(voluntary.completion(habitID: id, day: "2026-10-24")?.actualAmount == "周末自愿读了几页", "nonexecution day permits voluntary backfill")
                check(voluntary.habits[0].rule(on: "2026-10-24")?.isPlanned(on: "2026-10-24", calendar: shanghai) == false, "voluntary record does not change execution schedule")
                _ = try store.setCompletion(habitID: id, day: "2026-10-23", completed: true, now: noon, calendar: shanghai)
                let sunday = timestamp("2026-10-25T12:00:00+08:00")
                check(try store.poll(now: sunday, calendar: shanghai).pendingReminders(now: sunday, calendar: shanghai).isEmpty, "weekend has no reminder")
                _ = try store.poll(now: timestamp("2026-12-01T12:00:00+08:00"), calendar: shanghai)
                check(try store.read().completions.count == 2, "older month and voluntary completion history retained")
            }
        }
        scenario("paused day voluntary record lifecycle") {
            try isolated { _, store in
                let id = try store.saveHabit(id: nil, draft: draft(paused: true), now: morning, calendar: shanghai).habits[0].id
                let saved = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, actualAmount: "今天仍然读了两页", now: noon, calendar: shanghai)
                check(saved.completion(habitID: id, day: "2026-10-28")?.minimumAction == "读两页", "paused day permits voluntary completion snapshot")
                check(saved.habits[0].rule(on: "2026-10-28")?.isPlanned(on: "2026-10-28", calendar: shanghai) == false && saved.pendingReminders(now: noon, calendar: shanghai).isEmpty, "paused voluntary action stays unplanned and queues no reminder")
                let undone = try store.setCompletion(habitID: id, day: "2026-10-28", completed: false, now: noon + 1, calendar: shanghai)
                check(undone.completions.isEmpty, "paused voluntary completion can be undone")
            }
        }
        scenario("reminder queue lifecycle and no idle writes") {
            try isolated { directory, store in
                let id = try store.saveHabit(id: nil, draft: draft(), now: morning, calendar: shanghai).habits[0].id
                let file = directory.appendingPathComponent("habits.json")
                let before = try Data(contentsOf: file)
                check(try store.poll(now: morning + 60, calendar: shanghai).reminders.isEmpty, "not due creates no reminder")
                check(try Data(contentsOf: file) == before, "not due poll leaves exact bytes")
                let due = try store.poll(now: noon, calendar: shanghai)
                let receipt = due.reminders[0]
                check(due.reminders.count == 1 && receipt.day == "2026-10-28" && receipt.dueAt == timestamp("2026-10-28T09:00:00+08:00"), "wake poll materializes one current-day due request")
                check(due.pendingReminders(now: noon, calendar: shanghai).map(\.id) == [receipt.id], "queue remains available for app focus gate")
                let bytes = try Data(contentsOf: file)
                let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
                _ = try store.poll(now: noon + 1, calendar: shanghai)
                check(try Data(contentsOf: file) == bytes && (try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date) == mtime, "idle polling performs no rewrite")
                let snoozed = try store.snoozeReminder(id: receipt.id, now: noon, calendar: shanghai)
                check(snoozed.pendingReminders(now: noon + 599, calendar: shanghai).isEmpty, "snooze hides for ten minutes")
                check(snoozed.pendingReminders(now: noon + 600, calendar: shanghai).count == 1, "snooze returns at ten minutes")
                check(try HabitStore(directory: directory).read().pendingReminders(now: noon + 600, calendar: shanghai).count == 1, "relaunch retains pending snoozed receipt")
                let done = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, now: noon + 601, calendar: shanghai)
                check(done.pendingReminders(now: noon + 1000, calendar: shanghai).isEmpty && done.reminders[0].dismissed, "manual completion cancels pending or snoozed reminder")
                _ = try store.setCompletion(habitID: id, day: "2026-10-28", completed: false, now: noon + 602, calendar: shanghai)
                check(try store.poll(now: noon + 1000, calendar: shanghai).pendingReminders(now: noon + 1000, calendar: shanghai).isEmpty, "undo completion does not replay handled reminder")
                let next = try store.poll(now: tomorrow, calendar: shanghai)
                check(next.pendingReminders(now: tomorrow, calendar: shanghai).count == 1 && next.reminders.count == 2, "new day queues once and retains old receipt")
                let nextReceipt = next.pendingReminders(now: tomorrow, calendar: shanghai)[0]
                _ = try store.dismissReminder(id: nextReceipt.id, now: tomorrow, calendar: shanghai)
                _ = try store.saveHabit(id: id, draft: draft(reminder: 8 * 60), now: tomorrow + 1, calendar: shanghai)
                check(try store.poll(now: tomorrow + 2, calendar: shanghai).pendingReminders(now: tomorrow + 2, calendar: shanghai).isEmpty, "rule edit never reopens handled day")
            }
        }
        scenario("creation skip catch-up pause and cross midnight") {
            try isolated { _, store in
                let id = try store.saveHabit(id: nil, draft: draft(), now: noon, calendar: shanghai).habits[0].id
                check(try store.poll(now: noon + 1, calendar: shanghai).reminders.isEmpty, "new habit does not fire already passed time")
                let twoDays = timestamp("2026-10-30T12:00:00+08:00")
                let caught = try store.poll(now: twoDays, calendar: shanghai)
                check(caught.reminders.count == 1 && caught.reminders[0].day == "2026-10-30", "relaunch catches current day only and never backfills yesterday reminder")
                _ = try store.setPaused(id: id, paused: true, now: twoDays, calendar: shanghai)
                check(try store.read().pendingReminders(now: twoDays, calendar: shanghai).isEmpty, "pause immediately hides a queued reminder")
                _ = try store.setPaused(id: id, paused: false, now: twoDays, calendar: shanghai)
                check(try store.poll(now: twoDays, calendar: shanghai).pendingReminders(now: twoDays, calendar: shanghai).count == 1, "resume makes unhandled day eligible")
                let late = timestamp("2026-10-30T23:58:00+08:00")
                let receiptID = try store.read().reminders[0].id
                _ = try store.snoozeReminder(id: receiptID, now: late, calendar: shanghai)
                let afterMidnight = timestamp("2026-10-31T00:10:00+08:00")
                check(try store.poll(now: afterMidnight, calendar: shanghai).pendingReminders(now: afterMidnight, calendar: shanghai).isEmpty, "snoozed prior day never replays after midnight")
            }
        }
        scenario("creation at reminder boundary") {
            try isolated { _, store in
                let exactlyDue = timestamp("2026-10-28T09:00:00+08:00")
                let result = try store.saveHabit(id: nil, draft: draft(), now: exactlyDue, calendar: shanghai)
                check(result.pendingReminders(now: exactlyDue, calendar: shanghai).count == 1, "time equal to creation is due; only already-passed creation times skip")
            }
        }
        scenario("stable queue order and schedule editing") {
            try isolated { _, store in
                let first = try store.saveHabit(id: nil, draft: draft("A", reminder: 10 * 60), now: morning, calendar: shanghai).habits[0].id
                _ = try store.saveHabit(id: nil, draft: draft("B", reminder: 9 * 60), now: morning, calendar: shanghai)
                let initial = try store.poll(now: noon, calendar: shanghai)
                check(initial.pendingReminders(now: noon, calendar: shanghai).first?.habitID != first, "earlier due request leads stable queue")
                let edited = try store.saveHabit(id: first, draft: draft("A", reminder: 13 * 60), now: noon, calendar: shanghai)
                check(edited.pendingReminders(now: noon, calendar: shanghai).count == 1, "moving unhandled time forward immediately removes its pending request")
                let later = try store.poll(now: noon + 3600, calendar: shanghai)
                check(later.pendingReminders(now: noon + 3600, calendar: shanghai).count == 2 && later.reminders.count == 2, "edited due request returns without duplicate receipt")
                let noReminder = try store.saveHabit(id: first, draft: draft("A", reminder: nil), now: noon + 3601, calendar: shanghai)
                check(noReminder.pendingReminders(now: noon + 3601, calendar: shanghai).count == 1, "removing reminder setting hides unhandled request")
            }
        }
        scenario("completion before reminder and tie ordering") {
            try isolated { _, store in
                let first = try store.saveHabit(id: nil, draft: draft("A"), now: morning, calendar: shanghai).habits[0].id
                _ = try store.setCompletion(habitID: first, day: "2026-10-28", completed: true, now: morning + 1, calendar: shanghai)
                _ = try store.setCompletion(habitID: first, day: "2026-10-28", completed: false, now: morning + 2, calendar: shanghai)
                check(try store.poll(now: noon, calendar: shanghai).pendingReminders(now: noon, calendar: shanghai).isEmpty, "early completion then undo keeps that day's reminder handled")
                _ = try store.saveHabit(id: nil, draft: draft("B"), now: morning, calendar: shanghai)
                _ = try store.saveHabit(id: nil, draft: draft("C"), now: morning, calendar: shanghai)
                let pending = try store.poll(now: noon, calendar: shanghai).pendingReminders(now: noon, calendar: shanghai)
                check(pending.count == 2 && pending.map(\.id) == pending.map(\.id).sorted(), "equal due requests order by stable receipt identifier")
            }
        }
        scenario("DST reminder times") {
            for fixture in [("2026-03-07T08:00:00-05:00", "2026-03-08T04:00:00-04:00", 150, "2026-03-08T03:00:00-04:00"), ("2026-10-31T08:00:00-04:00", "2026-11-01T03:00:00-05:00", 90, "2026-11-01T01:30:00-04:00")] {
                try isolated { _, store in
                    let ny = calendar("America/New_York")
                    _ = try store.saveHabit(id: nil, draft: draft(reminder: fixture.2), now: timestamp(fixture.0), calendar: ny)
                    let result = try store.poll(now: timestamp(fixture.1), calendar: ny)
                    check(result.reminders.count == 1 && result.reminders.first?.dueAt == timestamp(fixture.3), "DST skipped time advances to next valid time; repeated time uses first occurrence: \(fixture.0)")
                }
            }
        }
        scenario("validation and protected malformed documents") {
            try isolated { directory, store in
                rejects("blank name") { _ = try store.saveHabit(id: nil, draft: draft("  "), now: noon, calendar: shanghai) }
                rejects("long name") { _ = try store.saveHabit(id: nil, draft: draft(String(repeating: "字", count: 61)), now: noon, calendar: shanghai) }
                rejects("long minimum") { _ = try store.saveHabit(id: nil, draft: draft(minimum: String(repeating: "字", count: 181)), now: noon, calendar: shanghai) }
                rejects("empty weekdays") { _ = try store.saveHabit(id: nil, draft: draft(weekdays: []), now: noon, calendar: shanghai) }
                rejects("duplicate weekdays") { _ = try store.saveHabit(id: nil, draft: draft(weekdays: [1,1]), now: noon, calendar: shanghai) }
                rejects("invalid weekday") { _ = try store.saveHabit(id: nil, draft: draft(weekdays: [0]), now: noon, calendar: shanghai) }
                rejects("invalid reminder minute") { _ = try store.saveHabit(id: nil, draft: draft(reminder: 1440), now: noon, calendar: shanghai) }
                rejects("nonfinite now") { _ = try store.poll(now: .nan, calendar: shanghai) }
                check(!FileManager.default.fileExists(atPath: directory.path), "invalid input causes no filesystem changes")
                let id = try store.saveHabit(id: nil, draft: draft(), now: morning, calendar: shanghai).habits[0].id
                rejects("unknown habit cannot become replacement") { _ = try store.saveHabit(id: "missing", draft: draft(), now: noon, calendar: shanghai) }
                rejects("overlong amount") { _ = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, actualAmount: String(repeating: "字", count: 2001), now: noon, calendar: shanghai) }
                let file = directory.appendingPathComponent("habits.json")
                let original = try store.read()
                let encoder = JSONEncoder()
                var invalids: [Data] = [Data("broken".utf8), Data("{\"schema\":2,\"extraFutureField\":true}".utf8)]
                var duplicate = original; duplicate.habits.append(original.habits[0]); invalids.append(try encoder.encode(duplicate))
                var badDay = original; badDay.habits[0].rules[0].effectiveDay = "2026-02-30"; invalids.append(try encoder.encode(badDay))
                var ruleDuplicate = original; ruleDuplicate.habits[0].rules.append(original.habits[0].rules[0]); invalids.append(try encoder.encode(ruleDuplicate))
                var unknown = original; unknown.completions.append(HabitCompletion(habitID: "missing", day: "2026-10-28", name: "X", minimumAction: "x", actualAmount: "", completedAt: noon)); invalids.append(try encoder.encode(unknown))
                let complete = try store.setCompletion(habitID: id, day: "2026-10-28", completed: true, now: noon, calendar: shanghai)
                var dupComplete = complete; dupComplete.completions.append(complete.completions[0]); invalids.append(try encoder.encode(dupComplete))
                var dupReminder = complete; dupReminder.reminders.append(complete.reminders[0]); invalids.append(try encoder.encode(dupReminder))
                var backwardsSnooze = complete; backwardsSnooze.reminders[0].eligibleAt = backwardsSnooze.reminders[0].dueAt - 1; invalids.append(try encoder.encode(backwardsSnooze))
                for (index, bytes) in invalids.enumerated() {
                    try bytes.write(to: file)
                    rejects("malformed fixture read \(index)") { _ = try store.read() }
                    rejects("malformed fixture poll \(index)") { _ = try store.poll(now: noon, calendar: shanghai) }
                    rejects("malformed fixture save \(index)") { _ = try store.saveHabit(id: nil, draft: draft(), now: noon, calendar: shanghai) }
                    check(try Data(contentsOf: file) == bytes, "malformed/future file preserved byte-for-byte \(index)")
                }
            }
        }
        scenario("symlink safety and concurrent process writes") {
            try isolated { directory, store in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let state = directory.appendingPathComponent("state.json")
                let bytes = Data("{\"schema\":5,\"untouched\":true}".utf8)
                try bytes.write(to: state)
                let file = directory.appendingPathComponent("habits.json")
                try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: state.path)
                rejects("symlink read rejects") { _ = try store.read() }
                rejects("symlink mutation rejects") { _ = try store.saveHabit(id: nil, draft: draft(), now: morning, calendar: shanghai) }
                check(try Data(contentsOf: state) == bytes, "store never touches shared business state")
                try FileManager.default.removeItem(at: file)
                var workers: [Process] = []
                for index in 0..<8 {
                    let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--worker", directory.path, String(index)]
                    try process.run(); workers.append(process)
                }
                workers.forEach { $0.waitUntilExit() }
                check(workers.allSatisfy { $0.terminationStatus == 0 }, "independent process transactions succeed")
                check(try store.read().habits.count == 8, "exclusive lock preserves concurrent habit additions")
                check(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".tmp") }, "atomic writes clean temporary files")
            }
        }
        scenario("nonregular input never blocks read") {
            try isolated { directory, _ in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fifo = directory.appendingPathComponent("habits.json")
                guard mkfifo(fifo.path, 0o600) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["--reject-nonregular", directory.path]
                try process.run()
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                let blocked = process.isRunning
                if blocked { process.terminate() }
                process.waitUntilExit()
                check(!blocked && process.terminationStatus == 0, "FIFO input is rejected immediately instead of blocking app refresh")
            }
        }
        if failures.isEmpty { print("PASS: \(assertions) habit checks (dates, rules, snapshots, reminders, privacy, validation, corruption and process concurrency)") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
