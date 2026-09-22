import AppKit
import Carbon
import Foundation

struct GlobalHotkey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let keyDisplay: String

    static let defaultValue = GlobalHotkey(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(optionKey),
        keyEquivalent: "v",
        keyDisplay: "V"
    )

    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyDisplay
    }

    var appKitModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        return result
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyEquivalent: String, keyDisplay: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyEquivalent = keyEquivalent
        self.keyDisplay = keyDisplay
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }

        let equivalent = event.charactersIgnoringModifiers ?? ""
        guard !equivalent.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        keyEquivalent = equivalent.lowercased()
        keyDisplay = Self.displayName(keyCode: event.keyCode, characters: equivalent)
    }

    private static func displayName(keyCode: UInt16, characters: String) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: return characters.uppercased()
        }
    }
}

final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registeredShortcut: GlobalHotkey?
    var onPressed: (() -> Void)?

    @discardableResult
    func register(_ shortcut: GlobalHotkey) -> Bool {
        installHandlerIfNeeded()

        let previousShortcut = registeredShortcut
        unregisterCurrentHotkey()
        if registerCarbonHotkey(shortcut) {
            registeredShortcut = shortcut
            return true
        }

        if let previousShortcut, registerCarbonHotkey(previousShortcut) {
            registeredShortcut = previousShortcut
        }
        return false
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, pointer in
                guard let pointer else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if hotKeyID.id == 1 { service.onPressed?() }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func registerCarbonHotkey(_ shortcut: GlobalHotkey) -> Bool {
        let id = EventHotKeyID(signature: OSType(0x434C4950), id: 1)  // CLIP
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        hotKeyRef = reference
        return true
    }

    private func unregisterCurrentHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredShortcut = nil
    }

    deinit {
        unregisterCurrentHotkey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
