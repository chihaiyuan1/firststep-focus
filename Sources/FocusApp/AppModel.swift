import SwiftUI
import AppKit
import FocusCore

@MainActor final class AppModel: ObservableObject {
    @Published var state = FocusCore.FocusState()
    @Published var now = Date().timeIntervalSince1970
    @Published var selectedTask: String?
    @Published var selectedSubtask: String?
    @Published var aiTaskID: String?
    @Published var minutes = 15
    @Published var page = "today"
    @Published var error: String?
    @Published var completion: FocusRecord?
    @Published var wantsQuit = false
    @Published var timeEntries: [TimeEntry] = []
    @Published var selectedLogDate = Date()
    @Published var logScope = "week"
    @Published var timeLogError: String?
    @Published var lastDeletedTimeID: String?
    @Published var lastDeletedInboxID: String?
    @Published var reflections: [SessionReflection] = []
    @Published var reflectionError: String?
    @Published var reflectionIsPresented = false
    let timeLogStore: TimeLogStore
    let reflectionStore: SessionReflectionStore
    private var timeLogModified: Date?
    private var reflectionModified: Date?
    private var reflectionsLoaded = false
    private var notifiedSessions = Set<String>()
    private(set) var stateUnavailable = false
    let store: StateStore
    private var timer: Timer?
    var onRefresh: (() -> Void)?
    var showMain: (() -> Void)?
    var toggleFloat: (() -> Void)?
    var onSessionEnded: ((FocusRecord, Bool) -> Void)?
    var showReflection: ((FocusRecord) -> Void)?
    init(store: StateStore = StateStore()) {
        self.store = store
        self.timeLogStore = TimeLogStore(directory: store.directory)
        self.reflectionStore = SessionReflectionStore(directory: store.directory)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    var extensionConnected: Bool { now - (state.lastExtensionSeen ?? 0) < 8 && state.extensionError == nil && state.extensionProtocol == 2 }
    var blockedSites: [BlockedSite] { state.effectiveBlockedSites }
    var inboxItems: [InboxItem] { Array(state.activeInboxItems.reversed()) }
    @discardableResult func moveInboxToToday(_ id: String) -> Bool {
        guard send(Command("moveInboxToday", taskID: id)) else { return false }
        if state.session == nil { selectedTask = id }
        page = "today"
        return true
    }
    func removeInboxItem(_ id: String) {
        if send(Command("deleteInbox", taskID: id)) { lastDeletedInboxID = id }
    }
    func undoInboxDeletion() {
        if let id = lastDeletedInboxID, send(Command("restoreInbox", taskID: id)) { lastDeletedInboxID = nil }
    }
    var extensionConnectionLabel: String {
        if state.lastExtensionSeen != nil && state.extensionProtocol != 2 { return "Chrome 扩展待更新" }
        if state.extensionError != nil { return "Chrome 连接异常" }
        return extensionConnected ? "Chrome 已连接" : "Chrome 未连接"
    }
    var extensionConnectionHint: String {
        if state.lastExtensionSeen != nil && state.extensionProtocol != 2 { return "Chrome 扩展需要更新：请在 chrome://extensions 重新加载「先做一刻」，并允许访问所有网站。完成前仅计时，无法保证自定义网站已屏蔽。" }
        if let error = state.extensionError { return error + "。当前仅计时，请先完成 Chrome 连接。" }
        return "Chrome 未连接，目前仅计时，不会屏蔽网站。请检查扩展是否启用，首次安装见「安装说明.md」。"
    }
    var remaining: Double { max(0, (state.session?.endAt ?? state.breakUntil ?? now) - now) }
    var canStart: Bool {
        guard !reflectionIsPresented else { return false }
        guard let task = todayTasks.first(where: {$0.id == selectedTask}) else { return false }
        return task.steps.isEmpty || task.steps.contains(where: {$0.id == selectedSubtask && !$0.completed})
    }
    func selectTask(_ id: String, subtaskID: String? = nil) {
        guard state.session == nil else { return }
        selectedTask = id
        let steps = state.tasks.first(where: {$0.id == id})?.steps ?? []
        selectedSubtask = steps.first(where: {$0.id == subtaskID && !$0.completed})?.id ?? steps.first(where: {!$0.completed})?.id
    }
    func openAI(taskID: String? = nil) { aiTaskID = taskID; page = "ai" }
    func completeFocusedTask() {
        guard let record=completion, let task=state.tasks.first(where:{$0.id==record.taskID}) else { completion=nil; return }
        if let stepID=record.subtaskID {
            if task.steps.first(where:{$0.id==stepID})?.completed == false { _=send(Command("completeSubtask",taskID:task.id,subtaskID:stepID)) }
        } else if !task.completed { _=send(Command("completeTask",taskID:task.id)) }
        completion=nil
    }
    var todayTasks: [FocusTask] { state.visibleTasks(day: FocusCore.FocusState.day(at: now)) }
    var todayRecords: [FocusRecord] { state.history.filter { FocusCore.FocusState.day(at: $0.startAt) == FocusCore.FocusState.day(at: now) } }
    var todayMinutes: Int { Int(todayRecords.reduce(0) { $0 + $1.focusSeconds } / 60) }
    func refresh() {
        now = Date().timeIntervalSince1970
        do {
            accept(try store.transact(now: now))
            stateUnavailable = false
            if !todayTasks.contains(where: { $0.id == selectedTask }) { selectedTask = todayTasks.first?.id }
            let steps=state.tasks.first(where:{$0.id == selectedTask})?.steps ?? []
            if !steps.contains(where:{$0.id == selectedSubtask && !$0.completed}) { selectedSubtask=steps.first(where:{!$0.completed})?.id }
            refreshTimeLog(); refreshReflections(); onRefresh?()
        } catch { stateUnavailable = true; self.error = error.localizedDescription }
    }
    func refreshTimeLog(force: Bool = false) {
        let file = store.directory.appendingPathComponent("time-records.json")
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        guard force || modified != timeLogModified else { return }
        do { timeEntries = try timeLogStore.read(); timeLogModified = modified; timeLogError = nil }
        catch { timeLogError = error.localizedDescription }
    }
    @discardableResult func saveTimeEntry(_ entry: TimeEntry) -> Bool {
        do { timeEntries = try timeLogStore.upsert(entry); timeLogError = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func removeTimeEntry(_ id: String) -> Bool {
        do { timeEntries = try timeLogStore.remove(id: id); lastDeletedTimeID = id; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func undoTimeDeletion() {
        guard let id = lastDeletedTimeID else { return }
        do { timeEntries = try timeLogStore.restore(id: id); lastDeletedTimeID = nil }
        catch { self.error = error.localizedDescription }
    }
    func refreshReflections(force: Bool = false) {
        let file = store.directory.appendingPathComponent("focus-reflections.json")
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        guard force || !reflectionsLoaded || modified != reflectionModified else { return }
        do {
            let result = try reflectionStore.read()
            if result != reflections { reflections = result }
            reflectionModified = modified; reflectionsLoaded = true; reflectionError = nil
        } catch { reflectionError = error.localizedDescription }
    }
    func reflection(for recordID: String) -> SessionReflection? { reflections.first { $0.recordID == recordID } }
    func reflectionsForAI() throws -> [SessionReflection] {
        refreshReflections(force: true)
        if let reflectionError { throw FocusError(reflectionError) }
        return reflections
    }
    @discardableResult func saveReflection(recordID: String, text: String) -> Bool {
        changeReflection(recordID: recordID) { try reflectionStore.save(recordID: recordID, text: text) }
    }
    @discardableResult func saveReflectionDraft(recordID: String, text: String) -> Bool {
        changeReflection(recordID: recordID) { try reflectionStore.saveDraft(recordID: recordID, text: text) }
    }
    @discardableResult func dismissReflection(recordID: String) -> Bool {
        changeReflection(recordID: recordID) { try reflectionStore.dismiss(recordID: recordID) }
    }
    private func changeReflection(recordID: String, _ change: () throws -> [SessionReflection]) -> Bool {
        guard state.history.contains(where: { $0.id == recordID }) else {
            reflectionError = "这轮专注记录已不存在，想法尚未保存。"; return false
        }
        do {
            reflections = try change(); reflectionError = nil; reflectionsLoaded = true
            reflectionModified = (try? FileManager.default.attributesOfItem(atPath: store.directory.appendingPathComponent("focus-reflections.json").path)[.modificationDate]) as? Date
            return true
        } catch { reflectionError = error.localizedDescription; return false }
    }
    private func accept(_ updated: FocusCore.FocusState) {
        let previousID = state.session?.id
        state = updated
        if let previousID, updated.session?.id != previousID,
           let record = updated.history.first(where: { $0.id == previousID }), notifiedSessions.insert(previousID).inserted {
            completion = record
            onSessionEnded?(record, wantsQuit)
        }
    }
    @discardableResult func send(_ command: Command) -> Bool {
        do { accept(try store.transact(command: command)); now = Date().timeIntervalSince1970; error = nil; refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func start() { guard let id = selectedTask, canStart else { return }; completion = nil; _ = send(Command("start", taskID: id, minutes: minutes, subtaskID: selectedSubtask)) }
    @discardableResult func startFromShortcut() -> Bool {
        guard state.session == nil, !reflectionIsPresented else { return false }
        guard let id = selectedTask, canStart else {
            page = "today"; error = "请先选择一个未完成的任务或小任务，再开始专注。"; return false
        }
        let started = send(Command("startShortcut", taskID: id, minutes: minutes, subtaskID: selectedSubtask))
        if started { completion = nil }
        return started
    }
    func capture(_ title: String, to destination: CaptureDestination) throws {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw FocusError("先写下一件事。") }
        guard normalized.count <= 120 else { throw FocusError("标题最多 120 个字，请稍微缩短一点。") }
        let updated = try store.transact(command: Command(destination == .today ? "addTask" : "addInbox", title: normalized))
        accept(updated)
        if destination == .today, updated.session == nil, let task = updated.tasks.last { selectTask(task.id) }
        refresh()
    }
    func requestEnd(quit: Bool = false) { wantsQuit = quit; showMain?(); _ = send(Command("requestEnd")) }
    func confirmEnd() {
        // The native reflection controller performs a requested quit after save/skip.
        _ = send(Command("confirmEnd", requestID: state.pending?.id))
    }
    func cancelEnd() { wantsQuit = false; _ = send(Command("cancelRequest")) }
}
func clockText(_ value: Double) -> String { let s = max(0, Int(ceil(value))); return String(format: "%02d:%02d", s / 60, s % 60) }
