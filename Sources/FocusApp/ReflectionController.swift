import AppKit
import SwiftUI
import FocusCore

private final class ReflectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor private final class ReflectionDraft: ObservableObject {
    @Published var record: FocusRecord?
    @Published var text = ""
    @Published var error: String?
    @Published var request = UUID()
}

/// One small, independent window, so existing task or quick-capture edits are not replaced.
@MainActor final class ReflectionController: NSObject, NSWindowDelegate {
    private struct Request { let record: FocusRecord; let quitAfter: Bool }
    private let model: AppModel
    private let draft = ReflectionDraft()
    private var panel: ReflectionPanel!
    private var pending: [Request] = []
    private var quitAfter = false
    private var previousApp: NSRunningApplication?
    private var persistedText = ""
    private var autosave: Task<Void, Never>?
    var canPresent: () -> Bool = { true }
    var afterClose: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var hasPending: Bool { !pending.isEmpty }
    @discardableResult func focusIfVisible() -> Bool {
        guard panel.isVisible else { return false }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        panel = ReflectionPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 420),
                                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "先做一刻 · 本轮想法"
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false; panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: ReflectionEditor(draft: draft,
            onChange: { [weak self] in self?.scheduleDraftSave() },
            onSave: { [weak self] in self?.save() },
            onSkip: { [weak self] in _ = self?.closeKeepingDraft() }))
    }

    func enqueue(_ record: FocusRecord, quitAfter: Bool = false) {
        if draft.record?.id == record.id {
            self.quitAfter = self.quitAfter || quitAfter
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            return
        }
        if !pending.contains(where: { $0.record.id == record.id }) { pending.append(Request(record: record, quitAfter: quitAfter)) }
        model.reflectionIsPresented = true
        presentPending()
    }

    func presentPending() {
        guard !panel.isVisible, !pending.isEmpty, canPresent() else { return }
        let request = pending.removeFirst()
        model.refreshReflections(force: true)
        let entry = model.reflection(for: request.record.id)
        draft.record = request.record; draft.text = entry?.editorText ?? ""
        persistedText = draft.text; draft.error = model.reflectionError
        draft.request = UUID(); quitAfter = request.quitAfter
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        model.reflectionIsPresented = true
        panel.center(); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }

    private func scheduleDraftSave() {
        autosave?.cancel()
        guard draft.record != nil else { return }
        autosave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            _ = self?.persistDraft()
        }
    }
    @discardableResult private func persistDraft() -> Bool {
        guard let record = draft.record else { return true }
        guard draft.text != persistedText else { return true }
        guard model.saveReflectionDraft(recordID: record.id, text: draft.text) else {
            draft.error = model.reflectionError; return false
        }
        persistedText = draft.text; draft.error = nil
        return true
    }
    private func save() {
        autosave?.cancel()
        guard let record = draft.record else { return }
        guard model.saveReflection(recordID: record.id, text: draft.text) else {
            draft.error = model.reflectionError; return
        }
        persistedText = draft.text
        finish()
    }
    @discardableResult func closeKeepingDraft() -> Bool {
        autosave?.cancel()
        guard persistDraft() else { return false }
        if let record = draft.record, !model.dismissReflection(recordID: record.id) {
            draft.error = model.reflectionError; return false
        }
        finish(); return true
    }
    /// Called on application quit, including Cmd-Q while the user is typing.
    func prepareForTermination() -> Bool {
        autosave?.cancel()
        return persistDraft()
    }
    /// A queued ending still gets its input window before a requested application quit.
    func deferQuitForPending() -> Bool {
        guard !pending.isEmpty else { return false }
        let last = pending.count - 1
        pending = pending.enumerated().map { Request(record: $0.element.record, quitAfter: $0.offset == last) }
        quitAfter = false
        presentPending()
        return true
    }
    private func finish() {
        let shouldQuit = quitAfter
        panel.orderOut(nil); draft.record = nil; draft.error = nil
        quitAfter = false; model.reflectionIsPresented = !pending.isEmpty
        if !shouldQuit, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [.activateIgnoringOtherApps])
        }
        previousApp = nil
        if shouldQuit { model.wantsQuit = false; NSApp.terminate(nil) }
        else { afterClose?() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { _ = closeKeepingDraft(); return false }
}

private struct ReflectionEditor: View {
    @ObservedObject var draft: ReflectionDraft
    let onChange: () -> Void
    let onSave: () -> Void
    let onSkip: () -> Void
    @SwiftUI.FocusState private var focused: Bool
    private let sage = Color(red: 0.38, green: 0.46, blue: 0.32)
    private let quiet = Color(red: 0.50, green: 0.53, blue: 0.47)
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("给这一轮留一点想法", systemImage: "square.and.pencil").font(.system(size: 19, weight: .semibold))
                Spacer()
                Text(draft.record?.finished == true ? "完整完成" : "提前结束")
                    .font(.system(size: 10)).foregroundStyle(quiet)
            }
            if let record = draft.record {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.subtaskTitle ?? record.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    if record.subtaskTitle != nil { Text("主任务：\(record.title)").font(.system(size: 11)).foregroundStyle(quiet) }
                    Text("\(Date(timeIntervalSince1970: record.startAt).formatted(.dateTime.month().day().hour().minute())) · 净专注 \(duration(record.focusSeconds))")
                        .font(.system(size: 11)).foregroundStyle(quiet)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.text).font(.system(size: 14)).focused($focused)
                    .scrollContentBackground(.hidden).padding(6)
                    .accessibilityLabel("本轮想法，自由输入")
                    .accessibilityIdentifier("session-reflection-editor")
                if draft.text.isEmpty {
                    Text("这一轮有什么想法、发现或卡住的地方？\n想到什么就写什么，也可以稍后再写。")
                        .font(.system(size: 13)).foregroundStyle(quiet.opacity(0.75)).padding(12).allowsHitTesting(false)
                }
            }.frame(height: 170).background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(sage.opacity(0.18)))
            HStack {
                Text("回车换行 · ⌘↩ 保存").font(.system(size: 10)).foregroundStyle(quiet)
                Spacer()
                Text("\(draft.text.count)/\(SessionReflection.maxTextLength)").font(.system(size: 10)).foregroundStyle(draft.text.count > SessionReflection.maxTextLength ? .red : quiet)
            }
            if let error = draft.error { Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            HStack(alignment: .center, spacing: 10) {
                Text("关窗保留草稿。只有已保存想法会随手动 AI 提问发送。")
                    .font(.system(size: 10)).foregroundStyle(quiet).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("稍后再写", action: onSkip).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("session-reflection-skip")
                Button("保存想法", action: onSave).keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(sage)
                    .disabled(draft.text.count > SessionReflection.maxTextLength)
                    .accessibilityIdentifier("session-reflection-save")
            }
        }.padding(24).frame(width: 510)
            .background(Color(red: 0.96, green: 0.96, blue: 0.93)).preferredColorScheme(.light)
            .onAppear { focused = true }
            .onChange(of: draft.request) { _ in focused = true }
            .onChange(of: draft.text) { _ in onChange() }
    }
    private func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(max(0, Int(seconds))) 秒" }
        return "\(Int(seconds / 60)) 分钟"
    }
}
