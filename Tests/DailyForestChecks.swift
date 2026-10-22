import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FocusError(message) }
}
private func time(_ value: String) -> Double { ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 }
private func record(_ id: String, start: Double, minutes: Int, net: Double? = nil, finished: Bool = true) -> FocusRecord {
    FocusRecord(id: id, taskID: "task", title: "工作 \(id)", startAt: start,
                endAt: start + Double(minutes * 60), focusSeconds: net ?? Double(minutes * 60),
                finished: finished, accessCount: net == nil ? 0 : 1)
}

@main struct DailyForestChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = time("2026-10-21T01:00:00Z"), date = Date(timeIntervalSince1970: morning)
        let durations = [15, 25, 30, 45, 25, 45]
        var records = durations.enumerated().map { record("r\($0.offset)", start: morning + Double($0.offset * 3600), minutes: $0.element) }
        records.append(record("pit", start: morning + 7 * 3600, minutes: 8, finished: false))
        let forest = DailyForest(records: records.reversed(), on: date, calendar: calendar)
        try check(forest.completedCount == 6 && forest.interruptedCount == 1 && forest.focusMinutes == 193,
                  "Six completions plus an 8-minute early end must count as 6 trees, 1 pit and 193 minutes")
        try check(forest.records.map(\.id) == ["r0", "r1", "r2", "r3", "r4", "r5", "pit"], "Forest order must be chronological")
        try check(forest.items.map(\.kind) == [.sapling, .tree, .mediumTree, .largeTree, .tree, .largeTree, .pit], "Each completed duration must produce its matching tree; early end is always a pit")

        let empty = DailyForest(records: records, on: date.addingTimeInterval(86400), calendar: calendar)
        try check(empty.records.isEmpty && empty.completedCount == 0 && empty.interruptedCount == 0 && empty.focusMinutes == 0, "An empty day must not borrow counts from other days")
        let midnight = time("2026-10-20T16:00:00Z")
        let boundaries = [record("previous", start: midnight - 600, minutes: 25), record("first", start: midnight, minutes: 15),
                          record("last", start: midnight + 86399, minutes: 25), record("next", start: midnight + 86400, minutes: 15)]
        let boundaryDay = DailyForest(records: boundaries, on: date, calendar: calendar)
        try check(boundaryDay.records.map(\.id) == ["first", "last"], "Start date owns a cross-midnight round; day interval must be half open")

        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstRecords = [record("before", start: time("2026-11-01T06:59:59Z"), minutes: 15),
                          record("start", start: time("2026-11-01T07:00:00Z"), minutes: 15),
                          record("extraHour", start: time("2026-11-02T07:30:00Z"), minutes: 15),
                          record("after", start: time("2026-11-02T08:00:00Z"), minutes: 15)]
        let dst = DailyForest(records: dstRecords, on: Date(timeIntervalSince1970: time("2026-11-01T20:00:00Z")), calendar: calendar)
        try check(dst.records.map(\.id) == ["start", "extraHour"], "DST day must use the local calendar rather than a fixed 24-hour window")

        let allowance = record("allowance", start: morning, minutes: 45, net: 40 * 60)
        let netDay = DailyForest(records: [allowance], on: date)
        try check(ForestItem(record: allowance).kind == .largeTree && netDay.focusMinutes == 40 && netDay.completedCount == 1,
                  "Temporary access reduces minutes, not the original 45-minute tree size or completed count")
        let oldJSON = try JSONEncoder().encode(records[0])
        let oldRecord = try JSONDecoder().decode(FocusRecord.self, from: oldJSON)
        try check(ForestItem(record: oldRecord).kind == .sapling, "Existing record JSON must work without new required fields")

        var state = FocusState()
        state.history = (0..<500).map { record("old\($0)", start: morning - Double(($0 + 1) * 86400), minutes: 15) }
        try state.apply(Command("addTask", title: "保留过去的森林"), now: morning)
        try state.apply(Command("start", taskID: state.tasks[0].id, minutes: 15), now: morning)
        state.tick(now: morning + 901)
        try check(state.history.count == 501 && state.history.last?.id == "old499", "Finishing the 501st round must not erase older forest records")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("state.json"))
        let reloaded = try StateStore(directory: dir).transact(now: morning + 902)
        try check(reloaded.history.count == 501 && reloaded.schema == 4, "Reload must preserve all forest records during the schema upgrade")

        for count in [0, 1, 7, 24, 53, 100] {
            let slots = ForestLayout.positions(count: count)
            try check(slots.count == count, "Every record must have a visible forest position, including crowded days")
            try check(slots.allSatisfy { (0.14...0.86).contains($0.x) && (0.25...0.82).contains($0.y) && $0.scale > 0 && $0.scale <= 1 }, "Forest positions must fit the land and have valid sizes")
            try check(Set(slots.map { "\($0.x),\($0.y)" }).count == count, "Two records must not be assigned the same plot")
            try check(slots == ForestLayout.positions(count: count), "A refresh must not shuffle trees")
        }
        print("PASS: daily forest counts, tree sizes, net time, empty days, midnight/DST, legacy JSON, 501-record retention and crowded layout")
    }
}
