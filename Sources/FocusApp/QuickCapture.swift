import AppKit
import SwiftUI
import FocusCore

@MainActor final class QuickCaptureDraft: ObservableObject {
    @Published var destination: CaptureDestination = .today
    @Published var title = ""
    @Published var error: String?
    @Published var request = UUID()
}

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class QuickCaptureController: NSObject, NSWindowDelegate {
    var isVisible: Bool { panel?.isVisible == true }
    private let model: AppModel
    private let draft = QuickCaptureDraft()
    private var panel: QuickCapturePanel!
    private var previousApp: NSRunningApplication?
    private var saving = false
    init(model: AppModel) {
        self.model = model
        super.init()
        panel = QuickCapturePanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 250), styleMask: [.titled,.closable,.utilityWindow], backing: .buffered, defer: false)
        panel.title = "先做一刻 · 快速添加"
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false; panel.hidesOnDeactivate = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: QuickCaptureView(draft: draft, onSave: { [weak self] in self?.save() }, onCancel: { [weak self] in self?.finish() }))
    }
    func show(_ destination: CaptureDestination) {
        if !panel.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            panel.center()
        }
        draft.destination = destination; draft.error = nil; draft.request = UUID()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func save() {
        guard panel.isVisible, !saving else { return }
        saving = true; defer { saving = false }
        do { try model.capture(draft.title, to: draft.destination); finish() }
        catch { draft.error = error.localizedDescription }
    }
    private func finish() {
        draft.title = ""; draft.error = nil
        panel.orderOut(nil)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [.activateIgnoringOtherApps])
        }
        previousApp = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(); return false }
}

private struct QuickCaptureView: View {
    @ObservedObject var draft: QuickCaptureDraft
    let onSave: () -> Void
    let onCancel: () -> Void
    @SwiftUI.FocusState private var focused: Bool
    private let sage = Color(red: 0.38, green: 0.46, blue: 0.32)
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("快速记一件事", systemImage: "square.and.pencil").font(.system(size: 19, weight: .semibold))
                Spacer()
                Picker("保存位置", selection: $draft.destination) {
                    ForEach(CaptureDestination.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 176)
            }
            TextField("写下标题就好", text: $draft.title)
                .textFieldStyle(.roundedBorder).font(.system(size: 16)).focused($focused)
                .accessibilityLabel("事情标题").accessibilityIdentifier("quick-capture-title")
                .onSubmit { onSave() }
            if let error = draft.error { Text(error).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("回车保存 · Esc 取消").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("收进\(draft.destination.title)", action: onSave)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(sage)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("quick-capture-save")
            }
        }.padding(24).frame(width: 480).frame(minHeight: 220)
            .background(Color(red: 0.96, green: 0.96, blue: 0.93))
            .preferredColorScheme(.light)
            .onAppear { focused = true }
            .onChange(of: draft.request) { _ in focused = true }
    }
}
