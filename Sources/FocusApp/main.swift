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
    private var wasActive = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.showMain = { [weak self] in self?.showMain() }
        model.toggleFloat = { [weak self] in self?.panel.orderFrontRegardless() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "先做一刻"; window.titlebarAppearsTransparent = true; window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: MainView(model: model)); window.delegate = self
        window.isReleasedWhenClosed = false; window.setFrameAutosaveName("FirstStepMain"); window.center()
        panel = FocusPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 144), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "先做一刻 · 悬浮计时"
        panel.contentView = NSHostingView(rootView: FloatingView(model: model))
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true; panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.contentView?.wantsLayer = true; panel.contentView?.layer?.cornerRadius = 18; panel.contentView?.layer?.masksToBounds = true
        positionPanel()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self; status.button?.action = #selector(showMain)
        buildMenu()
        model.onRefresh = { [weak self] in self?.refreshWindows() }
        refreshWindows(); showMain()
    }
    func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let r = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: r.maxX - 330, y: r.maxY - 164))
    }
    func refreshWindows() {
        let active = model.state.session != nil || model.state.breakUntil != nil
        status.button?.title = active ? "◒ \(clockText(model.remaining))" : "◒"
        status.button?.toolTip = model.state.session?.title ?? "先做一刻"
        if active && !wasActive { positionPanel(); panel.orderFrontRegardless() }
        if !active && wasActive { panel.orderOut(nil); if model.completion != nil { showMain() } }
        wasActive = active
    }
    func buildMenu() {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "打开先做一刻", action: #selector(showMain), keyEquivalent: "1").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏先做一刻", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出先做一刻", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (name, action, key) in [("撤销", "undo:", "z"),("剪切", "cut:", "x"),("复制", "copy:", "c"),("粘贴", "paste:", "v"),("全选", "selectAll:", "a")] { edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
    @objc func showMain() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.state.session != nil { model.requestEnd(quit: true); return .terminateCancel }
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
