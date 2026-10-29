import AppKit
import SwiftUI
import FocusCore

private let shortcutInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let shortcutQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let shortcutSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let shortcutWarning = Color(red: 0.65, green: 0.35, blue: 0.24)

struct ShortcutSettingsView: View {
    @ObservedObject var settings: ShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("快捷键").font(.system(size: 26, weight: .semibold))
                Text("快速记录、开始专注，也能随时查看进度。")
                    .font(.system(size: 13)).foregroundStyle(shortcutQuiet)
            }

            Label("先做一刻运行时，在其他软件中也能使用以下快捷键。", systemImage: "keyboard")
                .font(.system(size: 12)).foregroundStyle(shortcutSage)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(shortcutSage.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 8) {
                ForEach(ShortcutAction.allCases, id: \.rawValue) { action in
                    shortcutRow(action)
                }
            }

            if let error = settings.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(shortcutWarning).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                Text("点击按钮录制字母或数字，搭配 Command、Control、Option 中至少两个键。按 Esc 放弃修改。")
                    .font(.system(size: 11)).foregroundStyle(shortcutQuiet).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("恢复默认") { settings.cancelRecording(); _ = settings.resetDefaults() }
                    .buttonStyle(SoftButton())
            }
        }.foregroundStyle(shortcutInk)
            .onDisappear { settings.cancelRecording() }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 16)).foregroundStyle(shortcutSage)
                    .frame(width: 30, height: 30)
                    .background(shortcutSage.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.shortcutTitle).font(.system(size: 13, weight: .medium))
                    Text(action.subtitle)
                        .font(.system(size: 11)).foregroundStyle(shortcutQuiet)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ShortcutRecorderButton(
                    label: action.shortcutTitle,
                    bindingName: settings.preferences[action]?.displayName,
                    isRecording: settings.recording == action,
                    onActivate: {
                        settings.beginRecording(action)
                        return settings.recording == action
                    },
                    onCancel: {
                        if settings.recording == action { settings.cancelRecording() }
                    },
                    onRecord: { settings.record($0, for: action) }
                ).frame(width: 148, height: 32)
                Button("停用") {
                    settings.cancelRecording()
                    _ = settings.set(nil, for: action)
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(shortcutQuiet)
                    .disabled(settings.preferences[action] == nil)
                    .accessibilityLabel("停用\(action.shortcutTitle)快捷键")
            }
            if let error = settings.registrationErrors[action] {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(shortcutWarning).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ShortcutRecorderButton: NSViewRepresentable {
    let label: String
    let bindingName: String?
    let isRecording: Bool
    let onActivate: () -> Bool
    let onCancel: () -> Void
    let onRecord: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let button = ShortcutRecorderControl()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        button.focusRingType = .exterior
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderControl, context: Context) {
        button.onActivate = onActivate
        button.onCancel = onCancel
        button.onRecord = onRecord
        button.isRecording = isRecording
        button.title = isRecording ? "请按下快捷键…" : (bindingName ?? "设置快捷键")
        button.bezelColor = isRecording ? NSColor(red: 0.38, green: 0.46, blue: 0.32, alpha: 0.15) : nil
        button.contentTintColor = NSColor(red: 0.17, green: 0.20, blue: 0.16, alpha: 1)
        button.toolTip = isRecording ? "按下组合键，或按 Esc 取消" : "点击以设置快捷键"
        button.setAccessibilityLabel("\(label)快捷键")
        button.setAccessibilityValue(isRecording ? "正在录制" : (bindingName ?? "未设置"))
    }

    static func dismantleNSView(_ button: ShortcutRecorderControl, coordinator: ()) {
        button.cancelIfRecording()
        button.onActivate = nil
        button.onCancel = nil
        button.onRecord = nil
    }
}

/// Captures keys only while this control owns keyboard focus. No event monitor is installed.
private final class ShortcutRecorderControl: NSButton {
    var isRecording = false
    var onActivate: (() -> Bool)?
    var onCancel: (() -> Void)?
    var onRecord: ((NSEvent) -> Void)?
    private var windowFocusObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = windowFocusObserver { NotificationCenter.default.removeObserver(observer) }
        windowFocusObserver = nil
        guard let window else { cancelIfRecording(); return }
        windowFocusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in self?.cancelIfRecording() }
    }

    deinit {
        if let observer = windowFocusObserver { NotificationCenter.default.removeObserver(observer) }
    }

    @objc private func startRecording() {
        isRecording = onActivate?() ?? false
        if isRecording, window?.makeFirstResponder(self) != true { cancelIfRecording() }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, window?.firstResponder === self else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handle(event)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording { cancelIfRecording() } else { super.cancelOperation(sender) }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { cancelIfRecording() }
        return resigned
    }

    func cancelIfRecording() {
        guard isRecording else { return }
        isRecording = false
        onCancel?()
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { cancelIfRecording() }
        else { onRecord?(event) }
    }
}
