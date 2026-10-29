import Foundation

private var failures: [String] = []
private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { failures.append(message) }
}
private func object(_ state: FocusState) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
}
private func command(_ json: String) throws -> Command { try JSONDecoder().decode(Command.self, from: Data(json.utf8)) }
private func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); failures.append(message) } catch {}
}

@main struct TaskProgressChecks {
    static func main() throws {
        var state = FocusState()
        try state.apply(command("{\"action\":\"addTask\",\"title\":\"写文章\",\"estimatedPomodoros\":2}"), now: 1000)
        let id = state.tasks[0].id
        let firstTask = (try object(state)["tasks"] as! [[String: Any]])[0]
        check(firstTask["estimatedPomodoros"] as? Int == 2, "optional estimate persists from command")
        try state.apply(Command("start", taskID: id, minutes: 15), now: 1000)
        try state.apply(Command("completeTask", taskID: id), now: 1900)
        let snapshots = try object(state)["completionRecords"] as? [[String: Any]] ?? []
        check(snapshots.count == 1, "manual completion stores an immutable snapshot after deadline tick")
        check(snapshots.first?["completedPomodoros"] as? Int == 1, "snapshot counts the just-finished round")
        check(snapshots.first?["focusSeconds"] as? Double == 900, "snapshot includes net focus seconds")
        try state.apply(Command("completeTask", taskID: id), now: 1901)
        try state.apply(Command("editTask", taskID: id, title: "改名后"), now: 1902)
        try state.apply(Command("completeTask", taskID: id), now: 1903)
        try state.apply(Command("deleteTask", taskID: id), now: 1904)
        let afterDelete = try object(state)["completionRecords"] as? [[String: Any]] ?? []
        check(afterDelete.count == 2 && afterDelete.contains { $0["title"] as? String == "写文章" } && afterDelete.contains { $0["title"] as? String == "改名后" }, "restore/re-complete/rename/delete preserves both completion events")
        rejects("zero estimate must be rejected") { try state.apply(command("{\"action\":\"addTask\",\"title\":\"无效\",\"estimatedPomodoros\":0}"), now: 2000) }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        let legacy = Data("{\"schema\":4,\"tasks\":[{\"id\":\"old\",\"title\":\"无日期任务\",\"nextStep\":\"\",\"day\":\"2026-01-01\",\"completed\":true}],\"history\":[]}".utf8)
        try legacy.write(to: file)
        let migrated = try StateStore(directory: dir).transact(now: 3000)
        let legacyRecords = try object(migrated)["completionRecords"] as? [[String: Any]] ?? []
        check(legacyRecords.count == 1 && legacyRecords.first?["completedAt"] == nil, "legacy completed task migrates with unknown date")
        let invalid = Data("{\"schema\":4,\"tasks\":[{\"id\":\"old\",\"title\":\"不应覆盖\",\"nextStep\":\"\",\"day\":\"2026-01-01\",\"completed\":false,\"estimatedPomodoros\":0}],\"history\":[]}".utf8)
        try invalid.write(to: file)
        rejects("malformed stored estimate must be rejected") { _ = try StateStore(directory: dir).transact(now: 3001) }
        let afterFailure = try Data(contentsOf: file)
        check(afterFailure == invalid, "malformed stored estimate keeps original file bytes")
        try checkEstimatesAndRounds()
        try checkHierarchySnapshotsAndCohorts()
        try checkLegacyMigrations()
        try checkSnapshotCorruptionPreserved()
        if failures.isEmpty { print("PASS: task estimates, all presets, net focus, hierarchy/cutoffs, immutable/repeated completions, schema1-6 migration and corruption preservation") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}

private func record(_ id: String, taskID: String = "parent", subtaskID: String? = nil,
                    start: Double, end: Double, seconds: Double, finished: Bool = true) -> FocusRecord {
    FocusRecord(id: id, taskID: taskID, title: "历史标题", startAt: start, endAt: end,
                focusSeconds: seconds, finished: finished, accessCount: 0, subtaskID: subtaskID, subtaskTitle: nil)
}

private func checkEstimatesAndRounds() throws {
    var state = FocusState()
    try state.apply(Command("addTask", title: "标题即可"), now: 1000)
    let id = state.tasks[0].id
    check(state.tasks[0].estimatedPomodoros == nil, "title-only capture has no estimate")
    try state.apply(Command("editTask", taskID: id, title: "可选预估", estimatedPomodoros: 2), now: 1001)
    try state.apply(Command("editTask", taskID: id, title: "旧客户端编辑"), now: 1002)
    check(state.tasks[0].estimatedPomodoros == 2, "omitted estimate preserves existing edit")
    try state.apply(Command("editTask", taskID: id, title: "清空预估", updateEstimate: true), now: 1003)
    check(state.tasks[0].estimatedPomodoros == nil, "explicit update with nil clears estimate")
    rejects("negative edit estimate rejected") {
        try state.apply(Command("editTask", taskID: id, title: "不应修改", estimatedPomodoros: -1), now: 1004)
    }
    check(state.tasks[0].title == "清空预估", "invalid estimate cannot partly change task")
    rejects("fractional command estimate rejected") { _ = try command("{\"action\":\"addTask\",\"title\":\"分数\",\"estimatedPomodoros\":1.5}") }
    for minutes in [15, 25, 30, 45] {
        var round = FocusState()
        try round.apply(Command("addTask", title: "完成一轮", estimatedPomodoros: 1), now: 2000)
        let taskID = round.tasks[0].id
        try round.apply(Command("start", taskID: taskID, minutes: minutes), now: 2000)
        round.tick(now: 2000 + Double(minutes * 60))
        let progress = round.taskProgress(taskID: taskID)
        check(progress.completedPomodoros == 1 && progress.focusSeconds == Double(minutes * 60), "every supported duration counts as one complete round")
        check(!round.tasks[0].completed && round.completionHistory.isEmpty, "reaching estimate never completes task")
    }
    try state.apply(Command("start", taskID: id, minutes: 15), now: 3000)
    try state.apply(Command("requestAccess", site: "x.com"), now: 3010)
    try state.apply(Command("confirmAccess", requestID: state.pending?.id), now: 3040)
    try state.apply(Command("requestEnd"), now: 3100)
    try state.apply(Command("confirmEnd", requestID: state.pending?.id), now: 3130)
    let early = state.taskProgress(taskID: id)
    check(early.completedPomodoros == 0 && early.focusSeconds == 40 && early.recordIDs.count == 1, "early-ended session contributes net time and ID, no tomato")
    try state.apply(Command("completeTask", taskID: id), now: 3140)
    check(state.completionHistory[0].completedPomodoros == 0 && state.completionHistory[0].focusSeconds == 40 && state.completionHistory[0].focusRecordIDs.count == 1, "early-ended session is retained in completion snapshot")
}

private func checkHierarchySnapshotsAndCohorts() throws {
    var state = FocusState()
    state.tasks = [FocusTask(id: "parent", title: "主任务", nextStep: "", day: "2026-01-01",
        subtasks: [FocusSubtask(id: "child", title: "小任务")], estimatedPomodoros: 3)]
    state.history = [
        record("later", subtaskID: "child", start: 300, end: 400, seconds: 100),
        record("child-done", subtaskID: "child", start: 100, end: 200, seconds: 80),
        record("child-done", subtaskID: "child", start: 100, end: 200, seconds: 80),
        record("parent-done", start: 0, end: 100, seconds: 90),
        record("child-early", subtaskID: "child", start: 200, end: 250, seconds: 30, finished: false),
        record("other", taskID: "other", start: 0, end: 100, seconds: 100)
    ]
    let child = state.taskProgress(taskID: "parent", subtaskID: "child", through: 250)
    check(child.completedPomodoros == 1 && child.focusSeconds == 110 && Set(child.recordIDs) == ["child-done", "child-early"], "child cutoff is inclusive and duplicate IDs count once")
    let parent = state.taskProgress(taskID: "parent", through: 250)
    check(parent.completedPomodoros == 2 && parent.focusSeconds == 200 && parent.recordIDs.count == 3, "main task includes all child and direct focus once")
    try state.apply(Command("completeSubtask", taskID: "parent", subtaskID: "child"), now: 250)
    let childSnapshot = state.completionHistory[0]
    check(childSnapshot.title == "小任务" && childSnapshot.parentTitle == "主任务" && childSnapshot.completedAt == 250, "subtask completion stores immutable child and parent titles")
    check(childSnapshot.estimatedPomodoros == nil && childSnapshot.focusSeconds == 110, "subtasks have no invented estimate")
    try state.apply(Command("completeTask", taskID: "parent"), now: 250)
    let mainSnapshot = state.completionHistory[0]
    check(mainSnapshot.completedPomodoros == 2 && mainSnapshot.focusSeconds == 200 && mainSnapshot.estimatedPomodoros == 3, "main snapshot includes cumulative focus through completion only")
    let cohort = state.completionProgress(for: state.completionHistory)
    check(cohort.completedPomodoros == 2 && cohort.focusSeconds == 200 && cohort.recordIDs.count == 3, "parent/child page totals deduplicate common sessions")
    try state.apply(Command("completeTask", taskID: "parent"), now: 260)
    try state.apply(Command("editTask", taskID: "parent", title: "主任务改名", estimatedPomodoros: 4), now: 261)
    try state.apply(Command("completeTask", taskID: "parent"), now: 500)
    check(Set(state.completionHistory.map(\.id)).count == 3, "re-completion appends a fresh event ID")
    let repeated = state.completionProgress(for: state.completionHistory)
    check(repeated.completedPomodoros == 3 && repeated.focusSeconds == 300 && repeated.recordIDs.count == 4, "repeated completion cohort deduplicates session IDs across cutoffs")
    try state.apply(Command("deleteSubtask", taskID: "parent", subtaskID: "child"), now: 501)
    try state.apply(Command("deleteTask", taskID: "parent"), now: 502)
    check(state.completionHistory.contains(mainSnapshot) && state.completionHistory.contains(childSnapshot), "delete/rename/reopen cannot alter earlier snapshots")
    check(state.taskProgress(taskID: "parent").completedPomodoros == 3 && state.history.count == 6, "deletion retains full source history")
    let decoded = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
    check(decoded.completionHistory == state.completionHistory, "completion snapshots survive encode/decode")
}

private func checkLegacyMigrations() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    for schema in 1...5 {
        var legacy = FocusState()
        legacy.schema = schema
        legacy.tasks = [
            FocusTask(id: "known", title: "已知日期", nextStep: "", day: "2026-01-01", completed: true,
                subtasks: [FocusSubtask(id: "unknown-child", title: "未知日期小任务", completed: true)], completedAt: 200),
            FocusTask(id: "unknown", title: "未知日期主任务", nextStep: "", day: "2026-02-01", completed: true),
            FocusTask(id: "open", title: "未完成", nextStep: "", day: "2026-03-01")
        ]
        legacy.history = [record("before", taskID: "known", start: 0, end: 100, seconds: 100),
            record("after", taskID: "known", start: 200, end: 300, seconds: 100),
            record("unknown-session", taskID: "unknown", start: 300, end: 400, seconds: 80)]
        let dir = base.appendingPathComponent("schema-\(schema)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("state.json"))
        let store = StateStore(directory: dir)
        let migrated = try store.transact(now: 1000)
        check(migrated.schema == 6 && migrated.history == legacy.history && migrated.completionHistory.count == 3, "schema1-5 migrate without dropping history or open tasks")
        let known = migrated.completionHistory.first { $0.taskID == "known" && $0.subtaskID == nil }
        check(known?.completedAt == 200 && known?.focusSeconds == 100 && known?.focusRecordIDs == ["before"], "known legacy completion applies exact cutoff")
        let unknownMain = migrated.completionHistory.first { $0.taskID == "unknown" }
        check(unknownMain?.completedAt == nil && unknownMain?.focusSeconds == 80, "unknown completion preserves nil and available full history")
        let unknownChild = migrated.completionHistory.first { $0.subtaskID == "unknown-child" }
        check(unknownChild?.completedAt == nil && unknownChild?.focusSeconds == 0, "unknown child date does not inherit parent date; empty focus is valid")
        let reloaded = try store.transact(now: 1100)
        check(reloaded.completionHistory == migrated.completionHistory, "migration is one-time and completion IDs stay stable")
        var direct = legacy
        try direct.apply(Command("getState"), now: 1000)
        check(direct.schema == 6 && direct.completionHistory.count == 3, "in-memory apply migrates direct legacy task fixtures")
    }
}

private func checkSnapshotCorruptionPreserved() throws {
    var valid = FocusState()
    valid.tasks = [FocusTask(id: "parent", title: "完整记录", nextStep: "", day: "2026-01-01")]
    valid.history = [record("focus", start: 100, end: 200, seconds: 75)]
    try valid.apply(Command("completeTask", taskID: "parent"), now: 200)
    let bytes = try JSONEncoder().encode(valid)
    let base = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    let snapshot = (base["completionRecords"] as! [[String: Any]])[0]
    var fixtures: [(String, [String: Any])] = []
    for (key, value): (String, Any) in [("estimatedPomodoros", 0), ("focusSeconds", -1), ("completedPomodoros", 0),
        ("focusRecordIDs", ["missing"]), ("focusRecordIDs", ["focus", "focus"]), ("taskID", "other"),
        ("completedAt", 199), ("title", " "), ("focusSeconds", 74), ("estimatedPomodoros", 1.5)] {
        var changed = base, entry = snapshot
        entry[key] = value; changed["completionRecords"] = [entry]
        fixtures.append(("invalid snapshot \(key)=\(value)", changed))
    }
    var duplicate = base; duplicate["completionRecords"] = [snapshot, snapshot]
    fixtures.append(("duplicate completion IDs", duplicate))
    var future = base; future["schema"] = 7
    fixtures.append(("future schema", future))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("state.json"), store = StateStore(directory: dir)
    for (message, fixture) in fixtures {
        let invalid = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
        try invalid.write(to: file)
        rejects(message) { _ = try store.transact(command: Command("heartbeat", protocolVersion: 2), now: 1000) }
        let retained = try Data(contentsOf: file)
        check(retained == invalid, "rejected \(message) preserves original bytes")
    }
    try bytes.write(to: file)
    let reloaded = try store.transact(now: 1000)
    check(reloaded.completionHistory == valid.completionHistory, "valid completion data reloads after corruption probes")
}
