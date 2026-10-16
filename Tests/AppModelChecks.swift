import Foundation
import FocusCore

@main struct AppModelChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir), now = Date().timeIntervalSince1970
        let first = try store.transact(command: Command("addTask", title: "任务"), now: now)
        _ = try store.transact(command: Command("start", taskID: first.tasks[0].id, minutes: 15), now: now)
        let model = AppModel(store: store)
        _ = try store.transact(now: now + 901)
        guard model.send(Command("getState")), model.completion?.finished == true else {
            print("FAIL: command-triggered deadline must expose completion before replacing state"); exit(1)
        }
        model.completion = nil
        _ = model.send(Command("getState"))
        guard model.completion == nil else { print("FAIL: completion must not repeat"); exit(1) }
        print("PASS: AppModel command-triggered completion and no duplicate notification")
    }
}
