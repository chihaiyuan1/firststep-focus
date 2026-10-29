import AppKit
import Carbon
import FocusCore

struct GlobalShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let letterKeys: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",25:"9",26:"7",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"]
    static let modifierMask = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    func validate() throws {
        let primary = [controlKey, optionKey, cmdKey].filter { modifiers & UInt32($0) != 0 }.count
        guard primary >= 2, modifiers & ~Self.modifierMask == 0, Self.letterKeys[keyCode] != nil else {
            throw FocusError("请选择字母或数字，并搭配 Command、Control、Option 中至少两个键；Shift 可选。")
        }
    }
    var displayName: String {
        var prefix = ""
        for (mask, glyph) in [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")] {
            if modifiers & UInt32(mask) != 0 { prefix += glyph }
        }
        return prefix + keyName
    }
    private var keyName: String {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = unsafeBitCast(pointer, to: CFData.self)
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0
            var count: Int = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 8, &count, &chars)
            if result == noErr, count > 0 { return String(utf16CodeUnits: chars, count: count).uppercased() }
        }
        return Self.letterKeys[keyCode] ?? "?"
    }
}

struct ShortcutPreferences: Codable, Equatable {
    var today: GlobalShortcutBinding?
    var inbox: GlobalShortcutBinding?
    var toggleMain: GlobalShortcutBinding?
    var startFocus: GlobalShortcutBinding?
    var toggleFloat: GlobalShortcutBinding?
    static func defaultBinding(_ action: ShortcutAction) -> GlobalShortcutBinding {
        let key: Int
        switch action { case .today: key = kVK_ANSI_N; case .inbox: key = kVK_ANSI_I; case .toggleMain: key = kVK_ANSI_O; case .startFocus: key = kVK_ANSI_S; case .toggleFloat: key = kVK_ANSI_F }
        return GlobalShortcutBinding(keyCode: UInt32(key), modifiers: UInt32(controlKey | optionKey | cmdKey))
    }
    static let defaults = ShortcutPreferences(today: defaultBinding(.today), inbox: defaultBinding(.inbox), toggleMain: defaultBinding(.toggleMain), startFocus: defaultBinding(.startFocus), toggleFloat: defaultBinding(.toggleFloat))
    init(today: GlobalShortcutBinding?, inbox: GlobalShortcutBinding?, toggleMain: GlobalShortcutBinding? = nil, startFocus: GlobalShortcutBinding? = nil, toggleFloat: GlobalShortcutBinding? = nil) {
        self.today = today; self.inbox = inbox; self.toggleMain = toggleMain; self.startFocus = startFocus; self.toggleFloat = toggleFloat
    }
    subscript(_ action: ShortcutAction) -> GlobalShortcutBinding? {
        get { switch action { case .today: return today; case .inbox: return inbox; case .toggleMain: return toggleMain; case .startFocus: return startFocus; case .toggleFloat: return toggleFloat } }
        set { switch action { case .today: today = newValue; case .inbox: inbox = newValue; case .toggleMain: toggleMain = newValue; case .startFocus: startFocus = newValue; case .toggleFloat: toggleFloat = newValue } }
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: ShortcutAction.self)
        today = try values.decodeIfPresent(GlobalShortcutBinding.self, forKey: .today)
        inbox = try values.decodeIfPresent(GlobalShortcutBinding.self, forKey: .inbox)
        toggleMain = nil; startFocus = nil; toggleFloat = nil
        // Explicit new values take precedence over defaults of other missing fields.
        let additions: [ShortcutAction] = [.toggleMain, .startFocus, .toggleFloat]
        for action in additions where values.contains(action) { self[action] = try values.decodeIfPresent(GlobalShortcutBinding.self, forKey: action) }
        for action in additions where !values.contains(action) {
            let candidate = Self.defaultBinding(action)
            if !ShortcutAction.allCases.contains(where: { self[$0] == candidate }) { self[action] = candidate }
        }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: ShortcutAction.self)
        for action in ShortcutAction.allCases {
            if let binding = self[action] { try values.encode(binding, forKey: action) }
            else { try values.encodeNil(forKey: action) }
        }
    }
    func validate() throws {
        var used: [GlobalShortcutBinding] = []
        for action in ShortcutAction.allCases {
            if let binding = self[action] {
                try binding.validate()
                guard !used.contains(binding) else { throw FocusError("不同操作需要使用不同的快捷键。") }
                used.append(binding)
            }
        }
    }
}

struct ShortcutPreferencesStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }
    func load() throws -> ShortcutPreferences? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do { let value = try JSONDecoder().decode(ShortcutPreferences.self, from: Data(contentsOf: file)); try value.validate(); return value }
        catch { throw FocusError("快捷键设置无法读取，原文件已保留。当前使用默认快捷键；你可以在这里重新设置。") }
    }
    func save(_ value: ShortcutPreferences) throws {
        try value.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

@MainActor final class GlobalShortcutRegistrar {
    private static var nextSignature: UInt32 = 0x46535450
    private let signature: UInt32
    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    var onTrigger: (ShortcutAction) -> Void
    init(onTrigger: @escaping (ShortcutAction) -> Void) {
        self.onTrigger = onTrigger
        signature = Self.nextSignature; Self.nextSignature &+= 1
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<GlobalShortcutRegistrar>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard result == noErr, id.signature == signature,
              let action = ShortcutAction.allCases.first(where: {$0.hotKeyID == id.id}), refs[action] != nil else { return OSStatus(eventNotHandledErr) }
        onTrigger(action); return noErr
    }
    func register(_ binding: GlobalShortcutBinding, for action: ShortcutAction) throws {
        try binding.validate()
        guard handlerStatus == noErr, handler != nil else { throw FocusError("系统快捷键服务暂时不可用（\(handlerStatus)），请重启应用后再试。") }
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: signature, id: action.hotKeyID), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard result == noErr, let ref else {
            throw FocusError(result == eventHotKeyExistsErr ? "\(binding.displayName) 已被其他快捷键占用，请换一个组合。" : "无法启用 \(binding.displayName)（\(result)），请换一个组合。")
        }
        if let old = refs[action] { UnregisterEventHotKey(old) }
        refs[action] = ref
    }
    func unregisterAll() { for ref in refs.values { UnregisterEventHotKey(ref) }; refs.removeAll() }
    func shutdown() { unregisterAll(); if let handler { RemoveEventHandler(handler) }; handler = nil }
    deinit { for ref in refs.values { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}

@MainActor final class ShortcutSettingsModel: ObservableObject {
    @Published private(set) var preferences = ShortcutPreferences.defaults
    @Published var error: String?
    @Published private(set) var registrationErrors: [ShortcutAction: String] = [:]
    @Published private(set) var recording: ShortcutAction?
    let store: ShortcutPreferencesStore
    private let registrar: GlobalShortcutRegistrar
    var onTrigger: ((ShortcutAction) -> Void)?
    init(directory: URL) {
        store = ShortcutPreferencesStore(directory: directory)
        registrar = GlobalShortcutRegistrar(onTrigger: {_ in})
        do { preferences = try store.load() ?? .defaults } catch { self.error = error.localizedDescription }
        registrar.onTrigger = { [weak self] action in self?.onTrigger?(action) }
        resume()
    }
    private func resume() {
        registrar.unregisterAll(); registrationErrors = [:]
        for action in ShortcutAction.allCases {
            if let binding = preferences[action] {
                do { try registrar.register(binding, for: action) } catch { registrationErrors[action] = error.localizedDescription }
            }
        }
    }
    func beginRecording(_ action: ShortcutAction) { registrar.unregisterAll(); recording = action; error = nil }
    func cancelRecording() { guard recording != nil else { return }; recording = nil; resume() }
    func record(_ event: NSEvent, for action: ShortcutAction) {
        guard recording == action, !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) { _ = set(nil, for: action); return }
        _ = set(GlobalShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: GlobalShortcutBinding.modifiers(from: event.modifierFlags)), for: action)
    }
    @discardableResult func set(_ binding: GlobalShortcutBinding?, for action: ShortcutAction) -> Bool {
        var candidate = preferences; candidate[action] = binding
        return apply(candidate)
    }
    @discardableResult func resetDefaults() -> Bool { apply(.defaults) }
    private func apply(_ candidate: ShortcutPreferences) -> Bool {
        do { try candidate.validate() } catch { self.error = error.localizedDescription; return false }
        registrar.unregisterAll()
        do {
            for action in ShortcutAction.allCases {
                if let binding = candidate[action] { try registrar.register(binding, for: action) }
            }
            try store.save(candidate)
            preferences = candidate; recording = nil; error = nil; registrationErrors = [:]
            return true
        } catch {
            self.error = error.localizedDescription
            recording = nil; resume()
            return false
        }
    }
    func shutdown() { recording = nil; registrar.shutdown() }
}
