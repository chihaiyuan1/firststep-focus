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
        guard model.send(Command("addInbox", title: "暂存标题")), let inboxID = model.state.activeInboxItems.first?.id else { throw FocusError("Capture failed") }
        model.page = "inbox"
        guard model.moveInboxToToday(inboxID), model.page == "today", model.selectedTask == inboxID,
              model.state.session == nil, model.todayTasks.contains(where: { $0.id == inboxID }), model.state.activeInboxItems.isEmpty else { throw FocusError("Promotion must select the new Today task without starting") }
        guard model.send(Command("addInbox", title: "可撤销")), let deletedID = model.state.activeInboxItems.first?.id else { throw FocusError("Second capture failed") }
        model.removeInboxItem(deletedID)
        guard model.state.activeInboxItems.isEmpty, model.lastDeletedInboxID == deletedID else { throw FocusError("Delete failed") }
        model.undoInboxDeletion()
        guard model.state.activeInboxItems.first?.id == deletedID, model.lastDeletedInboxID == nil else { throw FocusError("Undo failed") }
        print("PASS: AppModel completion notifications, inbox-to-Today selection without auto-start, delete and undo")
    }
}
