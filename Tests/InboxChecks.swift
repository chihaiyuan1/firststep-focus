import Foundation

func check(_ value: Bool, _ message: String) throws { if !value { throw FocusError(message) } }
func rejects(_ body: () throws -> Void) throws {
    var rejected = false
    do { try body() } catch { rejected = true }
    try check(rejected, "Expected rejected operation")
}
func inbox(_ state: FocusState) throws -> [[String: Any]] {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    return (object["inboxItems"] as? [[String: Any]] ?? []).filter { $0["deletedAt"] == nil }
}

@main struct InboxChecks {
    static func main() {
        do { try run(); print("PASS: inbox capture, validation, edit, undo, atomic/idempotent promotion, migration, concurrency and corruption protection") }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        var state = try store.transact(command: Command("addInbox", title: "  一件\n临时任务  "), now: 1000)
        try check(state.tasks.isEmpty && state.session == nil, "Capture must not enter Today or start focus")
        let items = try inbox(state)
        try check(items.count == 1 && items[0]["title"] as? String == "一件 临时任务", "Title normalization")
        let id = items[0]["id"] as! String
        try rejects { _ = try store.transact(command: Command("addInbox", title: " \n "), now: 1001) }
        try rejects { _ = try store.transact(command: Command("addInbox", title: String(repeating: "字", count: 121)), now: 1001) }
        try rejects { _ = try store.transact(command: Command("start", taskID: id, minutes: 15), now: 1001) }
        state = try store.transact(command: Command("editInbox", taskID: id, title: "先列出需要的资料"), now: 1002)
        try check(try inbox(state).first?["title"] as? String == "先列出需要的资料", "Edit title")
        state = try store.transact(command: Command("deleteInbox", taskID: id), now: 1003)
        try check(try inbox(state).isEmpty, "Deleted item hidden")
        try rejects { _ = try store.transact(command: Command("moveInboxToday", taskID: id), now: 1004) }
        state = try store.transact(command: Command("restoreInbox", taskID: id), now: 1004)
        try check(try inbox(state).first?["title"] as? String == "先列出需要的资料", "Undo keeps edited title")
        state = try store.transact(command: Command("moveInboxToday", taskID: id), now: 1005)
        try check(try inbox(state).isEmpty, "Promotion removes inbox item")
        try check(state.tasks.count == 1 && state.tasks[0].id == id && state.tasks[0].title == "先列出需要的资料" && state.tasks[0].day == "1970-01-01", "Promotion keeps identity/title and sets today")
        try check(state.session == nil && state.tasks[0].nextStep.isEmpty, "Promotion must not start timer")
        _ = try store.transact(command: Command("moveInboxToday", taskID: id), now: 1005)
        try check(try store.transact(now: 1006).tasks.count == 1, "Double-click promotion is idempotent")
        state = try store.transact(command: Command("start", taskID: id, minutes: 15), now: 1006)
        let session = state.session
        state = try store.transact(command: Command("addInbox", title: "下一件"), now: 1007)
        let next = try inbox(state).first?["id"] as! String
        state = try store.transact(command: Command("moveInboxToday", taskID: next), now: 1008)
        try check(state.session == session, "Capture/promotion cannot interrupt current focus")

        let file = directory.appendingPathComponent("state.json")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        legacy["schema"] = 2; legacy.removeValue(forKey: "inboxItems")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let migrated = try store.transact(now: 1009)
        try check(migrated.schema == 4 && migrated.tasks == state.tasks && migrated.session == session, "Schema2 migration preserves focus and tasks")
        try check(try inbox(migrated).isEmpty, "Migration starts empty")
        state = try store.transact(command: Command("addInbox", title: "并发移动"), now: 1010)
        let concurrentID = try inbox(state).first?["id"] as! String
        let lock = NSLock(); var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do { _ = try StateStore(directory: directory).transact(command: index.isMultiple(of: 2) ? Command("moveInboxToday", taskID: concurrentID) : Command("heartbeat", protocolVersion: 2), now: 1011) }
            catch { lock.lock(); errors.append(error.localizedDescription); lock.unlock() }
        }
        state = try store.transact(now: 1012)
        try check(errors.isEmpty && state.tasks.filter { $0.id == concurrentID }.count == 1, "Concurrent promotion/heartbeat cannot duplicate or lose the task")
        try check(try inbox(state).isEmpty, "Concurrent promotion removes exactly once")
        var invalid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        invalid["inboxItems"] = [["id":"broken","title":" ","createdAt":1000]]
        let bytes = try JSONSerialization.data(withJSONObject: invalid)
        try bytes.write(to: file)
        try rejects { _ = try store.transact(now: 1013) }
        try check(try Data(contentsOf: file) == bytes, "Invalid inbox must not be overwritten")
    }
}
