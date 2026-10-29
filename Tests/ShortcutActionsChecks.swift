import AppKit
import Carbon
import FocusCore

@main struct ShortcutActionsChecks {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw FocusError(message) } }
        let defaults = ShortcutPreferences.defaults
        let legacy = try JSONDecoder().decode(ShortcutPreferences.self, from: Data("{\"today\":{\"keyCode\":1,\"modifiers\":6400}}".utf8))
        try check(legacy.today?.keyCode == 1 && legacy.inbox == nil, "Legacy custom and omitted-disabled settings must survive")
        try check(legacy.startFocus == nil && legacy.toggleMain == defaults.toggleMain && legacy.toggleFloat == defaults.toggleFloat, "New defaults must not collide with legacy binding")
        let explicitNew = try JSONDecoder().decode(ShortcutPreferences.self, from: Data("{\"today\":null,\"inbox\":null,\"toggleFloat\":{\"keyCode\":31,\"modifiers\":6400}}".utf8))
        try check(explicitNew.today == nil && explicitNew.inbox == nil && explicitNew.toggleMain == nil && explicitNew.toggleFloat == defaults.toggleMain, "Explicit additions take priority over missing-field defaults")
        var disabled = defaults; disabled.toggleMain = nil; disabled.startFocus = nil; disabled.toggleFloat = nil
        let roundTrip = try JSONDecoder().decode(ShortcutPreferences.self, from: JSONEncoder().encode(disabled))
        try check(roundTrip == disabled, "New explicit disabled settings must round-trip")
        for action in ShortcutAction.allCases where action != .today {
            var duplicate = defaults; duplicate[action] = defaults.today
            var rejected = false; do { try duplicate.validate() } catch { rejected = true }
            try check(rejected, "Every cross-action duplicate must fail")
        }
        var visibility = TimerPanelVisibility()
        try check(visibility.refresh(sessionID: nil, breakUntil: nil) == nil, "Idle cannot show a timer")
        try check(visibility.refresh(sessionID: "first", breakUntil: nil) == true, "New focus shows timer")
        try check(visibility.refresh(sessionID: "first", breakUntil: nil) == nil, "Refresh must preserve manual hiding")
        try check(visibility.refresh(sessionID: "second", breakUntil: nil) == true, "A different session restores the timer")
        try check(visibility.refresh(sessionID: nil, breakUntil: 100) == true, "Rest is a new timer period")
        try check(visibility.refresh(sessionID: nil, breakUntil: 100) == nil, "Rest refresh preserves hiding")
        try check(visibility.refresh(sessionID: nil, breakUntil: nil) == false, "Idle hides timer")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir), now = Date().timeIntervalSince1970
        let model = AppModel(store: store)
        try check(!model.startFromShortcut() && model.state.session == nil && model.error != nil, "No task must prompt instead of starting")
        _ = try store.transact(command: Command("addTask", title: "独立测试任务"), now: now)
        model.refresh(); model.minutes = 30
        let taskID = model.state.tasks[0].id
        model.selectedTask = nil
        try check(!model.startFromShortcut() && model.state.session == nil, "A valid task still requires a current selection")
        model.selectTask(taskID)
        try check(model.startFromShortcut() && model.state.session?.endAt == model.state.session!.startAt + 1800, "Selected task and duration must be used")
        let active = model.state.session!
        try check(!model.startFromShortcut() && model.state.session == active, "Repeated shortcut must preserve session and deadline")
        _ = try store.transact(command: Command("requestEnd"), now: now + 1); model.refresh()
        let pending = model.state.pending
        try check(!model.startFromShortcut() && model.state.pending == pending && model.state.session == active, "End confirmation cannot be bypassed")
        _ = try store.transact(now: active.endAt + 1)
        _ = try store.transact(command: Command("startBreak"), now: active.endAt + 1); model.refresh()
        let rest = model.state.breakUntil
        try check(!model.startFromShortcut() && model.state.breakUntil == rest && model.state.session == nil, "Rest cannot be bypassed")
        var resting = try store.transact()
        var restRejected = false
        do { try resting.apply(Command("startShortcut", taskID: taskID, minutes: 15), now: now) } catch { restRejected = true }
        try check(restRejected && resting.breakUntil == rest && resting.session == nil, "Core must atomically reject a shortcut during rest")
        var state = try store.transact(command: Command("endBreak"))
        _ = try store.transact(command: Command("appendSubtasks", taskID: state.tasks[0].id, subtaskTitles: ["小步骤甲", "小步骤乙"]))
        model.refresh(); let step = model.state.tasks[0].steps[1]
        model.selectTask(model.state.tasks[0].id, subtaskID: step.id); model.minutes = 25
        try check(model.startFromShortcut() && model.state.session?.subtaskID == step.id && model.state.session?.endAt == model.state.session!.startAt + 1500, "Chosen subtask must start")
        state = model.state
        var rejected = false
        do { try state.apply(Command("startShortcut", taskID: state.tasks[0].id, minutes: 15), now: now) } catch { rejected = true }
        try check(rejected && state.session == model.state.session, "Core must atomically reject already active session")
        print("PASS: five shortcut migration, disabled/colliding defaults, duplicates, timer visibility, selected start, repeat, rest and confirmation guards")
    }
}
