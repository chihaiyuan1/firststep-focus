import SwiftUI
import AppKit
import FocusCore

@MainActor final class AppModel: ObservableObject {
    @Published var state = FocusCore.FocusState()
    @Published var now = Date().timeIntervalSince1970
    @Published var selectedTask: String?
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
    let timeLogStore: TimeLogStore
    private var timeLogModified: Date?
    let store: StateStore
    private var timer: Timer?
    var onRefresh: (() -> Void)?
    var showMain: (() -> Void)?
    var toggleFloat: (() -> Void)?
    init(store: StateStore = StateStore()) { self.store = store; self.timeLogStore = TimeLogStore(directory: store.directory); refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    var extensionConnected: Bool { now - (state.lastExtensionSeen ?? 0) < 8 && state.extensionError == nil && state.extensionProtocol == 2 }
    var blockedSites: [BlockedSite] { state.effectiveBlockedSites }
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
    var todayTasks: [FocusTask] { state.tasks.filter { !$0.completed || $0.day == FocusCore.FocusState.day(at: now) } }
    var todayRecords: [FocusRecord] { state.history.filter { FocusCore.FocusState.day(at: $0.startAt) == FocusCore.FocusState.day(at: now) } }
    var todayMinutes: Int { Int(todayRecords.reduce(0) { $0 + $1.focusSeconds } / 60) }
    func refresh() {
        now = Date().timeIntervalSince1970
        do {
            accept(try store.transact(now: now))
            if !state.tasks.contains(where: { $0.id == selectedTask && !$0.completed }) { selectedTask = state.tasks.first(where: { !$0.completed })?.id }
            refreshTimeLog(); onRefresh?()
        } catch { self.error = error.localizedDescription }
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
    private func accept(_ updated: FocusCore.FocusState) {
        let previousID = state.session?.id
        state = updated
        if let previousID, updated.session?.id != previousID,
           let record = updated.history.first(where: { $0.id == previousID }) {
            completion = record
            if record.finished { NSSound(named: "Glass")?.play() }
        }
    }
    @discardableResult func send(_ command: Command) -> Bool {
        do { accept(try store.transact(command: command)); now = Date().timeIntervalSince1970; error = nil; refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func start() { guard let id = selectedTask else { return }; completion = nil; _ = send(Command("start", taskID: id, minutes: minutes)) }
    func requestEnd(quit: Bool = false) { wantsQuit = quit; showMain?(); _ = send(Command("requestEnd")) }
    func confirmEnd() {
        if send(Command("confirmEnd", requestID: state.pending?.id)), wantsQuit { NSApp.terminate(nil) }
    }
    func cancelEnd() { wantsQuit = false; _ = send(Command("cancelRequest")) }
}
func clockText(_ value: Double) -> String { let s = max(0, Int(ceil(value))); return String(format: "%02d:%02d", s / 60, s % 60) }
