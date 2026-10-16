import Foundation

var failed: [String] = []
func check(_ ok: @autoclosure () throws -> Bool, _ name: String) { do { if try !ok() { failed.append(name) } } catch { failed.append("\(name): \(error)") } }
func rejects(_ name: String, _ body: () throws -> Void) { do { try body(); failed.append(name) } catch {} }
func entry(_ start: Int = 540, _ end: Int = 600, day: String = "2026-10-16", id: String = UUID().uuidString) throws -> TimeEntry { try TimeEntry(id: id, day: day, startMinute: start, endMinute: end, title: "写文章") }
@main struct TimeLogChecks {
    static func main() throws {
        rejects("blank title") { _ = try TimeEntry(day: "2026-10-16", startMinute: 540, endMinute: 600, title: " \n ") }
        rejects("out of bounds") { _ = try entry(419, 600) }
        rejects("end after 20") { _ = try entry(1190, 1201) }
        rejects("reversed") { _ = try entry(600, 590) }
        rejects("invalid date") { _ = try entry(day: "2026-02-30") }
        rejects("invalid color") { _ = try TimeEntry(day: "2026-10-16", startMinute: 540, endMinute: 600, title: "事", color: "unknown") }
        check(TimeGrid.selection(fromY: 128, toY: 192, hourHeight: 64) == (540,600), "one hour drag")
        check(TimeGrid.selection(fromY: 192, toY: 128, hourHeight: 64) == (540,600), "reverse drag")
        check(TimeGrid.selection(fromY: 832, toY: 832, hourHeight: 64) == (1170,1200), "bottom click")
        check(TimeGrid.selection(fromY: -100, toY: 1000, hourHeight: 64) == (420,1200), "selection clamps bounds")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let sunday = ISO8601DateFormatter().date(from: "2026-10-18T04:00:00Z")!
        let week = TimeGrid.week(containing: sunday, calendar: cal)
        check(week.count == 7 && week.first.map { TimeGrid.dayKey($0, calendar: cal) } == "2026-10-12", "Sunday week starts Monday")
        let newYear = ISO8601DateFormatter().date(from: "2027-01-01T04:00:00Z")!
        check(TimeGrid.week(containing: newYear, calendar: cal).first.map { TimeGrid.dayKey($0, calendar: cal) } == "2026-12-28", "cross-year week")
        let moved = TimeGrid.moved(try entry(540,600), deltaMinutes: 45, dayOffset: 1, calendar: cal)
        check(moved.day == "2026-10-17" && moved.startMinute == 600 && moved.endMinute == 660, "move snaps and shifts date")
        let bottom = TimeGrid.moved(try entry(1140,1200), deltaMinutes: 90)
        check(bottom.startMinute == 1140 && bottom.endMinute == 1200, "move stays in range and preserves duration")
        let top = TimeGrid.resized(try entry(540,600), edge: "start", deltaMinutes: -300)
        check(top.startMinute == 420 && top.endMinute == 600, "resize top clamps")
        let end = TimeGrid.resized(try entry(540,600), edge: "end", deltaMinutes: -120)
        check(end.startMinute == 540 && end.endMinute == 570, "resize cannot invert")
        let shortStart = TimeGrid.resized(try entry(540,550), edge: "start", deltaMinutes: 6)
        check(shortStart.startMinute == 540 && shortStart.endMinute == 550, "short start does not jump backwards")
        let shortEnd = TimeGrid.resized(try entry(545,560), edge: "end", deltaMinutes: -6)
        check(shortEnd.endMinute == 560, "short end does not grow when dragged earlier")
        let shortLayout = TimeGrid.placements([try entry(540,541,id:"short-a"), try entry(541,542,id:"short-b")], minimumDuration: 25)
        check(shortLayout.allSatisfy { $0.laneCount == 2 } && shortLayout.count == 2, "minimum visible cards occupy separate lanes")
        let layout = TimeGrid.placements([try entry(540,600,id:"a"),try entry(570,630,id:"b"),try entry(600,660,id:"c"),try entry(660,690,id:"d")])
        check(layout.first { $0.id == "a" } == TimePlacement(id:"a",lane:0,laneCount:2), "overlap first lane")
        check(layout.first { $0.id == "b" } == TimePlacement(id:"b",lane:1,laneCount:2), "overlap second lane")
        check(layout.first { $0.id == "c" }?.lane == 0, "adjacent endpoints reuse lane")
        check(layout.first { $0.id == "d" }?.laneCount == 1, "non-overlap cluster full width")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TimeLogStore(directory: dir), original = try entry(id: "saved")
        _ = try store.upsert(original)
        check(try store.read() == [original], "save and restart read")
        var changed = original; changed.title = "改好了"; changed.startMinute = 600; changed.endMinute = 660
        _ = try store.upsert(changed)
        check(try store.read().count == 1, "edit not duplicated")
        _ = try store.remove(id: original.id)
        check(try store.read().first?.deletedAt != nil, "soft delete")
        _ = try store.restore(id: original.id)
        check(try store.read().first?.title == "改好了", "undo preserves content")
        let lock = NSLock(); var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 12) { i in
            do { _ = try TimeLogStore(directory: dir).upsert(entry(id:"parallel-\(i)")) }
            catch { lock.lock(); errors.append(error.localizedDescription); lock.unlock() }
        }
        let concurrentCount = try store.read().count
        check(errors.isEmpty && concurrentCount == 13, "concurrent writes preserved")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("time-records.json"), broken = Data("broken, preserve this".utf8)
        try broken.write(to: file)
        rejects("corrupt read") { _ = try store.read() }
        rejects("corrupt file not overwritten") { _ = try store.upsert(original) }
        check(try Data(contentsOf: file) == broken, "corrupt bytes preserved")
        if failed.isEmpty { print("PASS: time-log validation, selection, week dates, drag bounds, overlap layout, persistence, undo, concurrency, corrupt-file protection") }
        else { failed.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
