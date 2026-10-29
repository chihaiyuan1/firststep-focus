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
        guard model.send(Command("appendSubtasks", taskID: inboxID, subtaskTitles: ["先收集三份材料", "检查材料缺口"])),
              let child = model.state.tasks.first(where: {$0.id == inboxID})?.steps.last else { throw FocusError("Subtasks missing") }
        model.selectTask(inboxID, subtaskID: child.id)
        guard model.canStart && model.state.session == nil && model.selectedSubtask == child.id else { throw FocusError("Selection must not start") }
        model.start()
        guard model.state.session?.subtaskID == child.id else { throw FocusError("Start must target selected subtask") }
        let finishAt = model.state.session!.endAt + 1
        _ = try store.transact(now: finishAt); model.refresh()
        model.completeFocusedTask()
        let parent = model.state.tasks.first(where: {$0.id == inboxID})!
        guard !parent.completed && parent.steps.last?.completed == true && parent.steps.first?.completed == false else { throw FocusError("Completion card must mark only focused subtask") }
        try model.capture("快捷输入今天", to: .today)
        guard model.state.tasks.last?.title == "快捷输入今天", model.selectedTask == model.state.tasks.last?.id, model.state.session == nil else { throw FocusError("Today capture must select without starting") }
        model.start()
        let active = model.state.session, selected = model.selectedTask
        try model.capture("稍后处理的事", to: .inbox)
        try model.capture("专注时补记任务", to: .today)
        guard active != nil, model.state.session == active, model.selectedTask == selected,
              model.state.activeInboxItems.last?.title == "稍后处理的事", model.state.tasks.last?.title == "专注时补记任务" else { throw FocusError("Capture must preserve active task and deadline") }
        let taskCount = model.state.tasks.count, inboxCount = model.state.activeInboxItems.count
        for bad in ["  ", String(repeating: "字", count: 121)] {
            for destination in CaptureDestination.allCases {
                var rejected = false
                do { try model.capture(bad, to: destination) } catch { rejected = true }
                guard rejected else { throw FocusError("Invalid capture should be rejected") }
            }
        }
        guard model.state.tasks.count == taskCount, model.state.activeInboxItems.count == inboxCount, model.state.session == active else { throw FocusError("Rejected input cannot alter records") }
        print("PASS: AppModel completion, inbox-to-Today, undo, subtask selection, quick capture and active-session preservation")
    }
}
