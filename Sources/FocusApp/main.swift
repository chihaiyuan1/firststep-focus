import AppKit
import SwiftUI
import FocusCore

final class FocusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var window: NSWindow!
    var panel: FocusPanel!
    var status: NSStatusItem!
    var shortcuts: ShortcutSettingsModel!
    var quickCapture: QuickCaptureController!
    var reflections: ReflectionController!
    var reminders: CompletionReminderModel!
    var habits: HabitModel!
    var habitReminder: HabitReminderController!
    var taskReminder: HabitReminderController!
    private var wakeObserver: NSObjectProtocol?
    private var habitTimer: Timer?
    private var timerVisibility = TimerPanelVisibility()
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        habits = HabitModel(directory: model.store.directory)
        habitReminder = HabitReminderController()
        taskReminder = HabitReminderController(taskMode: true)
        taskReminder.onComplete = { [weak self] id in self?.handleTaskReminder(id: id, action: "today") }
        taskReminder.onSnooze = { [weak self] id in self?.handleTaskReminder(id: id, action: "snooze") }
        taskReminder.onDismiss = { [weak self] id in self?.handleTaskReminder(id: id, action: "dismiss") }
        habitReminder.onComplete = { [weak self] id in self?.habits.completeFromReminder(id); self?.showHabitErrorIfNeeded() }
        habitReminder.onSnooze = { [weak self] id in self?.habits.snoozeReminder(id); self?.showHabitErrorIfNeeded() }
        habitReminder.onDismiss = { [weak self] id in self?.habits.dismissReminder(id); self?.showHabitErrorIfNeeded() }
        habits.onChange = { [weak self] in self?.refreshHabitReminder() }
        reminders = CompletionReminderModel(directory: model.store.directory)
        shortcuts = ShortcutSettingsModel(directory: model.store.directory)
        quickCapture = QuickCaptureController(model: model)
        reflections = ReflectionController(model: model)
        reflections.canPresent = { [weak self] in
            guard let self else { return false }
            return self.window?.attachedSheet == nil && !self.quickCapture.isVisible && NSApp.modalWindow == nil
        }
        model.onSessionEnded = { [weak self] record, quitAfter in
            guard let self else { return }
            self.shortcuts.cancelRecording()
            self.reminders.playEnd()
            self.reflections.enqueue(record, quitAfter: quitAfter)
        }
        model.showReflection = { [weak self] record in self?.reflections.enqueue(record) }
        shortcuts.onTrigger = { [weak self] action in self?.performShortcut(action) }
        model.showMain = { [weak self] in self?.showMain() }
        model.toggleFloat = { [weak self] in self?.showFloatingWindow() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "先做一刻"; window.titlebarAppearsTransparent = true; window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: MainView(model: model, shortcuts: shortcuts, reminders: reminders, habits: habits)); window.delegate = self
        window.isReleasedWhenClosed = false; window.setFrameAutosaveName("FirstStepMain"); window.center()
        panel = FocusPanel(contentRect: NSRect(x: 0, y: 0, width: FloatingTimerMetrics.side, height: FloatingTimerMetrics.side), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "先做一刻 · 悬浮计时"
        panel.contentView = NSHostingView(rootView: FloatingView(model: model))
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true; panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.contentView?.wantsLayer = true; panel.contentView?.layer?.cornerRadius = FloatingTimerMetrics.cornerRadius; panel.contentView?.layer?.masksToBounds = true
        positionPanel()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self; status.button?.action = #selector(showMain)
        buildMenu()
        model.onRefresh = { [weak self] in self?.refreshWindows() }
        habitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHabitReminder() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.refresh()
                    self.habits.refresh(now: Date().timeIntervalSince1970, force: true)
                    self.refreshHabitReminder()
                }
            }
        refreshWindows(); showMain()
    }
    func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let r = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: r.maxX - panel.frame.width - FloatingTimerMetrics.screenInset,
                                    y: r.maxY - panel.frame.height - FloatingTimerMetrics.screenInset))
    }
    func refreshWindows() {
        let active = model.state.session != nil || model.state.breakUntil != nil
        status.button?.title = active ? "◒ \(clockText(model.remaining))" : "◒"
        status.button?.toolTip = model.state.session?.displayTitle ?? "先做一刻"
        if let visible = timerVisibility.refresh(sessionID: model.state.session?.id, breakUntil: model.state.breakUntil) {
            if visible { positionPanel(); panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
        reflections.presentPending()
        refreshHabitReminder()
    }
    func refreshHabitReminder() {
        habits.refresh(now: Date().timeIntervalSince1970)
        let item = habits.reminderPresentation(focusActive: model.state.session != nil,
                                               focusStateAvailable: !model.stateUnavailable)
        habitReminder.update(item, pendingCount: habits.pendingReminderCount > 1 ? habits.pendingReminderCount : 0)
        taskReminder.setHorizontalOffset(item == nil ? 0 : 315)
        let due = model.stateUnavailable ? [] : model.state.dueTaskReminders(now: model.now, focusActive: model.state.session != nil)
        guard let task = due.first else {
            taskReminder.update(nil); return
        }
        taskReminder.update(HabitReminderPresentation(id: task.id, habitID: task.id, name: task.title,
            minimumAction: "计划日期：\(task.day)", day: task.day), pendingCount: due.count > 1 ? due.count : 0)
    }
    func handleTaskReminder(id: String, action: String) {
        guard let item = model.state.nextTaskReminder(now: model.now, focusActive: model.state.session != nil), item.id == id else { return }
        let actionName: String
        if action == "today" { actionName = item.isInbox ? "moveInboxToday" : "moveToday" }
        else if action == "snooze" { actionName = item.isInbox ? "scheduleInbox" : "scheduleTask" }
        else { actionName = item.isInbox ? "dismissInboxReminder" : "dismissTaskReminder" }
        let command = Command(actionName, taskID: id, scheduledDay: action == "snooze" ? item.day : nil,
                              reminderAt: action == "snooze" ? model.now + 600 : nil, consumeReminder: action == "today")
        if model.send(command), action == "today" { model.page = "today"; model.selectTask(id); showMain() }
    }
    func showHabitErrorIfNeeded() {
        guard habits.error != nil else { return }
        model.page = "habits"; showMain()
    }
    func buildMenu() {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "打开先做一刻", action: #selector(showMain), keyEquivalent: "1").target = self
        appMenu.addItem(withTitle: "快速添加今日任务", action: #selector(captureToday), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "快速添加收集箱事项", action: #selector(captureInbox), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "显示／隐藏主窗口", action: #selector(toggleMainWindow), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "开始当前选中的任务", action: #selector(startSelectedFocus), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "显示／隐藏悬浮计时窗", action: #selector(toggleFloatingWindow), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏先做一刻", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出先做一刻", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (name, action, key) in [("撤销", "undo:", "z"),("剪切", "cut:", "x"),("复制", "copy:", "c"),("粘贴", "paste:", "v"),("全选", "selectAll:", "a")] { edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
    @objc func showMain() {
        if reflections?.focusIfVisible() == true { return }
        if window?.isMiniaturized == true { window.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func performShortcut(_ action: ShortcutAction) {
        if let destination = action.captureDestination {
            guard !model.reflectionIsPresented else { return }
            quickCapture.show(destination); return
        }
        switch action {
        case .toggleMain: toggleMainWindow()
        case .startFocus: startSelectedFocus()
        case .toggleFloat: toggleFloatingWindow()
        default: break
        }
    }
    @objc func toggleMainWindow() {
        if NSApp.isActive, window.isVisible, !window.isMiniaturized, NSApp.keyWindow === window, window.attachedSheet == nil {
            window.orderOut(nil)
        } else { showMain() }
    }
    @objc func startSelectedFocus() {
        guard model.state.session == nil else { return }
        let editing = NSApp.isActive && NSApp.keyWindow === window && window.firstResponder is NSTextView
        guard shortcuts.recording == nil, !model.reflectionIsPresented, !quickCapture.isVisible, window.attachedSheet == nil, NSApp.modalWindow == nil, !editing else { NSSound.beep(); return }
        if !model.startFromShortcut() { model.page = "today"; showMain() }
    }
    func showFloatingWindow() {
        guard model.state.session != nil || model.state.breakUntil != nil else { return }
        positionPanel(); panel.orderFrontRegardless()
    }
    @objc func toggleFloatingWindow() {
        guard model.state.session != nil || model.state.breakUntil != nil else { model.page = "today"; showMain(); return }
        if panel.isVisible { panel.orderOut(nil) } else { showFloatingWindow() }
    }
    @objc func showSettings() { model.page = "settings"; showMain() }
    @objc func captureToday() { if !model.reflectionIsPresented { quickCapture.show(.today) } }
    @objc func captureInbox() { if !model.reflectionIsPresented { quickCapture.show(.inbox) } }
    func applicationWillTerminate(_ notification: Notification) {
        _ = reflections?.prepareForTermination(); reminders?.stop(); shortcuts?.shutdown()
        habitReminder?.stop()
        taskReminder?.stop()
        habitTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.state.session != nil { model.requestEnd(quit: true); return .terminateCancel }
        if reflections?.deferQuitForPending() == true { return .terminateCancel }
        if reflections?.prepareForTermination() == false { return .terminateCancel }
        return .terminateNow
    }
}
if CommandLine.arguments.contains("--native-host") || URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "FirstStepNative" {
    runNativeHost()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        app.run()
    }
}
