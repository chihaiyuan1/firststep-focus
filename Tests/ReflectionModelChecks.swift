import Foundation
import FocusCore

@main struct ReflectionModelChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir), now = Date().timeIntervalSince1970
        var state = try store.transact(command: Command("addTask", title: "记录一轮想法"), now: now)
        let id = state.tasks[0].id
        state = try store.transact(command: Command("start", taskID: id, minutes: 15), now: now)
        let firstID = state.session!.id
        let model = AppModel(store: store)
        var ended: [(FocusRecord, Bool)] = []
        model.onSessionEnded = { ended.append(($0, $1)) }
        _ = try store.transact(now: now + 901)
        model.refresh()
        guard ended.count == 1, ended[0].0.id == firstID, ended[0].0.finished, !ended[0].1 else {
            throw FocusError("Complete round must notify once, even when NativeHost ended it first")
        }
        model.refresh(); _ = model.send(Command("getState"))
        guard ended.count == 1 else { throw FocusError("Duplicate completed refresh replayed reminder") }
        let business = try Data(contentsOf: dir.appendingPathComponent("state.json"))
        guard model.saveReflection(recordID: firstID, text: "已保存的发现"),
              model.saveReflectionDraft(recordID: firstID, text: "还没提交的草稿"),
              model.dismissReflection(recordID: firstID) else { throw FocusError("Reflection save/draft/skip failed") }
        let note = try model.reflectionsForAI().first { $0.recordID == firstID }
        guard note?.text == "已保存的发现", note?.editorText == "还没提交的草稿", note?.savedAt != nil else {
            throw FocusError("Draft must not replace submitted text")
        }
        guard try Data(contentsOf: dir.appendingPathComponent("state.json")) == business else {
            throw FocusError("Notes must not rewrite focus history, completion archive or active deadline")
        }
        model.reflectionIsPresented = true
        guard !model.canStart, !model.startFromShortcut(), model.state.session == nil else { throw FocusError("Editing reflection must not start another round") }
        model.reflectionIsPresented = false
        let restarted = AppModel(store: store)
        var replayed = false
        restarted.onSessionEnded = { _, _ in replayed = true }
        restarted.refresh()
        guard !replayed, restarted.reflection(for: firstID)?.editorText == "还没提交的草稿" else { throw FocusError("Restart must preserve draft without replaying old notifications") }
        _ = try store.transact(command: Command("start", taskID: id, minutes: 25), now: now + 1000)
        model.refresh()
        _ = try store.transact(command: Command("requestEnd"), now: now + 1010)
        let pending = try store.transact(now: now + 1011).pending!.id
        model.wantsQuit = true
        _ = try store.transact(command: Command("confirmEnd", requestID: pending), now: now + 1040)
        model.refresh(); model.refresh()
        guard ended.count == 2, !ended[1].0.finished, ended[1].1, ended[1].0.id != firstID else {
            throw FocusError("Early end must notify once and carry deferred quit intent")
        }
        let file = dir.appendingPathComponent("focus-reflections.json"), valid = try Data(contentsOf: file)
        let broken = Data("broken notes, preserve me".utf8); try broken.write(to: file)
        var rejected = false
        do { _ = try model.reflectionsForAI() } catch { rejected = true }
        guard rejected, try Data(contentsOf: file) == broken else { throw FocusError("Corrupt notes must stop AI collection and preserve bytes") }
        try valid.write(to: file)
        let reloaded = try model.reflectionsForAI()
        guard reloaded.first?.text == "已保存的发现", model.reflectionError == nil else { throw FocusError("Canonical notes must reload after recovery") }
        guard !model.saveReflection(recordID: "orphan", text: "不能关联的内容"), try Data(contentsOf: file) == valid else { throw FocusError("Orphan note cannot alter saved file") }
        print("PASS: complete/early-end reminders once, startup no replay, deferred quit, drafts/restart, editing guard, isolated history and corrupt-AI refusal")
    }
}
