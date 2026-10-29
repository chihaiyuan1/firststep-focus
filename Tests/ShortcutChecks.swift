import AppKit
import Carbon
import FocusCore

@main struct ShortcutChecks {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        func check(_ value: Bool, _ reason: String) throws { if !value { throw FocusError(reason) } }
        let prefs = ShortcutPreferences.defaults
        try prefs.validate()
        var invalid = prefs; invalid.inbox = prefs.today
        do { try invalid.validate(); throw FocusError("Duplicate must fail") } catch let error as FocusError { try check(error.message != "Duplicate must fail", "Duplicate shortcuts accepted") }
        let store = ShortcutPreferencesStore(directory: dir)
        try store.save(prefs)
        try check(try store.load() == prefs, "Preferences round trip")
        let model = ShortcutSettingsModel(directory: dir)
        defer { model.shutdown() }
        try check(model.registrationErrors.isEmpty, "Default hotkeys should register exclusively")
        let blocker = GlobalShortcutRegistrar(onTrigger: {_ in})
        defer { blocker.shutdown() }
        let taken = GlobalShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey | cmdKey))
        try blocker.register(taken, for: .today)
        try check(!model.set(taken, for: .today), "Occupied shortcut must fail")
        try check(model.preferences == prefs && (try store.load()) == prefs, "Conflict must preserve old preferences")
        let probe = GlobalShortcutRegistrar(onTrigger: {_ in})
        defer { probe.shutdown() }
        for action in ShortcutAction.allCases {
            do { try probe.register(prefs[action]!, for: action); throw FocusError("Previous key unexpectedly released") }
            catch let error as FocusError { try check(error.message != "Previous key unexpectedly released", "Every old key must remain active after rejected edit") }
        }
        model.beginRecording(.today)
        for action in ShortcutAction.allCases { try probe.register(prefs[action]!, for: action) }
        probe.unregisterAll()
        model.cancelRecording()
        try check(model.registrationErrors.isEmpty && model.recording == nil, "Recording cancellation must restore registrations")
        try check(model.set(nil, for: .inbox), "Disable succeeds")
        try check(try store.load()?.inbox == nil, "Disabled key persists")
        try check(model.set(nil, for: .toggleMain), "New action can be disabled")
        try check(try store.load()?.toggleMain == nil, "New disabled action persists as null")
        try check(model.resetDefaults(), "Defaults restored")
        model.shutdown()
        let restarted = ShortcutSettingsModel(directory: dir)
        defer { restarted.shutdown() }
        try check(restarted.preferences == prefs && restarted.registrationErrors.isEmpty, "Restart restores settings")
        let damaged = Data("broken".utf8)
        try damaged.write(to: store.file)
        let corrupt = ShortcutSettingsModel(directory: dir)
        defer { corrupt.shutdown() }
        try check(corrupt.error != nil && (try Data(contentsOf: store.file)) == damaged, "Corrupt config must be reported and preserved")
        print("PASS: global shortcut conflict rollback, exclusive registration, recording restoration, disable/defaults, persistence and corruption preservation")
    }
}
