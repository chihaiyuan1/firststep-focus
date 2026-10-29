import AppKit

struct HabitReminderPresentation: Identifiable, Equatable {
    let id: String
    let habitID: String
    let name: String
    let minimumAction: String
    let day: String

    init(id: String, habitID: String, name: String, minimumAction: String, day: String) {
        self.id = id
        self.habitID = habitID
        self.name = name
        self.minimumAction = minimumAction
        self.day = day
    }
}

private final class HabitReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accept the first click while another app remains active, without asking for typing focus.
private final class HabitReminderButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Presentation only: the caller owns eligibility, focus deferral, persistence and snooze time.
@MainActor final class HabitReminderController: NSObject {
    var onComplete: ((String) -> Void)?
    var onSnooze: ((String) -> Void)?
    var onDismiss: ((String) -> Void)?

    private let panel: HabitReminderPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let minimumLabel = NSTextField(labelWithString: "")
    private let pendingLabel = NSTextField(labelWithString: "")
    private var item: HabitReminderPresentation?
    private var pendingCount = 0
    private let taskMode: Bool
    private var horizontalOffset: CGFloat = 0

    private static let size = NSSize(width: 300, height: 170)
    private static let sage = NSColor(srgbRed: 0.38, green: 0.46, blue: 0.32, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.22, green: 0.26, blue: 0.20, alpha: 1)
    private static let quiet = NSColor(srgbRed: 0.50, green: 0.53, blue: 0.47, alpha: 1)

    init(taskMode: Bool = false) {
        self.taskMode = taskMode
        panel = HabitReminderPanel(contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = taskMode ? "先做一刻 · 任务提醒" : "先做一刻 · 习惯提醒"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = makeContentView()
    }

    func update(_ item: HabitReminderPresentation?, pendingCount: Int = 0) {
        guard let item else {
            self.item = nil
            self.pendingCount = 0
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        let newPresentation = self.item?.id != item.id
        let count = max(0, pendingCount)
        if self.item != item || self.pendingCount != count {
            self.item = item
            self.pendingCount = count
            titleLabel.stringValue = item.name
            titleLabel.toolTip = item.name
            titleLabel.setAccessibilityValue(item.name)
            minimumLabel.stringValue = item.minimumAction
            minimumLabel.toolTip = item.minimumAction
            minimumLabel.setAccessibilityValue(item.minimumAction)
            pendingLabel.stringValue = count > 0 ? "待提醒 \(count) 项" : ""
            panel.contentView?.toolTip = "\(item.day)\n\(item.name)\n\(item.minimumAction)"
        }

        // A model tick or a failed mutation must not move, raise or recreate this panel.
        guard newPresentation else { return }
        positionPanel()
        panel.orderFrontRegardless()
    }

    func stop() {
        update(nil)
    }

    func setHorizontalOffset(_ offset: CGFloat) {
        guard horizontalOffset != offset else { return }
        horizontalOffset = offset
        if panel.isVisible { positionPanel() }
    }

    private func positionPanel() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(visible.minX + 10, visible.maxX - Self.size.width - 20 - horizontalOffset),
            y: visible.maxY - Self.size.height - 20))
    }

    @objc private func complete() {
        guard let id = item?.id else { return }
        onComplete?(id)
    }

    @objc private func snooze() {
        guard let id = item?.id else { return }
        onSnooze?(id)
    }

    @objc private func dismiss() {
        guard let id = item?.id else { return }
        onDismiss?(id)
    }

    private func makeContentView() -> NSView {
        let content = NSView(frame: NSRect(origin: .zero, size: Self.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).cgColor
        content.layer?.cornerRadius = 15
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Self.sage.withAlphaComponent(0.16).cgColor
        content.setAccessibilityElement(false)
        content.setAccessibilityIdentifier("habit-reminder-panel")

        let heading = NSTextField(labelWithString: taskMode ? "任务提醒" : "习惯提醒")
        heading.font = .systemFont(ofSize: 11, weight: .medium)
        heading.textColor = Self.quiet
        pendingLabel.font = .systemFont(ofSize: 10)
        pendingLabel.textColor = Self.quiet
        pendingLabel.alignment = .right
        pendingLabel.setAccessibilityIdentifier("habit-reminder-pending")

        configureText(titleLabel, size: 14, weight: .semibold, color: Self.ink,
            identifier: "habit-reminder-name", label: taskMode ? "任务" : "习惯")
        configureText(minimumLabel, size: 12, weight: .regular, color: Self.ink,
            identifier: "habit-reminder-minimum", label: taskMode ? "计划日期" : "最低行动")

        let close = button("关闭", action: #selector(dismiss), identifier: "habit-reminder-dismiss")
        close.font = .systemFont(ofSize: 10)
        close.contentTintColor = Self.quiet
        close.toolTip = "关闭今天这条提醒"
        close.setAccessibilityLabel(taskMode ? "关闭这条任务提醒" : "关闭今天这条习惯提醒")
        let complete = button(taskMode ? "加入今天" : "完成", action: #selector(complete), identifier: "habit-reminder-complete")
        complete.wantsLayer = true
        complete.layer?.backgroundColor = Self.sage.cgColor
        complete.layer?.cornerRadius = 8
        complete.contentTintColor = .white
        complete.setAccessibilityLabel(taskMode ? "加入今天" : "完成今天的习惯")
        let snooze = button("稍后 10 分钟", action: #selector(snooze), identifier: "habit-reminder-snooze")
        snooze.wantsLayer = true
        snooze.layer?.backgroundColor = Self.sage.withAlphaComponent(0.10).cgColor
        snooze.layer?.cornerRadius = 8
        snooze.contentTintColor = Self.sage
        snooze.setAccessibilityLabel("10 分钟后再次提醒")

        for view in [heading, pendingLabel, close, titleLabel, minimumLabel, complete, snooze] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 13),
            heading.heightAnchor.constraint(equalToConstant: 24),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),
            close.widthAnchor.constraint(equalToConstant: 38),
            close.heightAnchor.constraint(equalToConstant: 30),
            pendingLabel.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -5),
            pendingLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            pendingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: heading.trailingAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
            titleLabel.heightAnchor.constraint(equalToConstant: 34),
            minimumLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            minimumLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            minimumLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            minimumLabel.heightAnchor.constraint(equalToConstant: 32),
            complete.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            complete.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            complete.widthAnchor.constraint(equalToConstant: 96),
            complete.heightAnchor.constraint(equalToConstant: 30),
            snooze.leadingAnchor.constraint(equalTo: complete.trailingAnchor, constant: 8),
            snooze.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            snooze.bottomAnchor.constraint(equalTo: complete.bottomAnchor),
            snooze.heightAnchor.constraint(equalTo: complete.heightAnchor)
        ])
        return content
    }

    private func configureText(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight,
        color: NSColor, identifier: String, label: String) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = true
        field.cell?.usesSingleLineMode = false
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(label)
    }

    private func button(_ title: String, action: Selector, identifier: String) -> HabitReminderButton {
        let button = HabitReminderButton(title: title, target: self, action: action)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.focusRingType = .none
        button.keyEquivalent = ""
        button.setAccessibilityIdentifier(identifier)
        return button
    }
}
