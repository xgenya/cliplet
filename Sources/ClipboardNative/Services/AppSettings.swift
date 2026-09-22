import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared: AppSettings = {
        if UIPreview.enabled {
            let defaults = UserDefaults(suiteName: "ClipboardNative.UIPreview")!
            defaults.removePersistentDomain(forName: "ClipboardNative.UIPreview")
            defaults.set("zh-Hans", forKey: "appLanguage")
            return AppSettings(defaults: defaults)
        }
        return AppSettings(defaults: AppEnvironment.current.defaults)
    }()

    private enum Key {
        static let isPaused = "isPaused"
        static let retentionDays = "retentionDays"
        static let maximumItems = "maximumItems"
        static let pasteAutomatically = "pasteAutomatically"
        static let preferPlainText = "preferPlainText"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyEquivalent = "hotkeyKeyEquivalent"
        static let hotkeyKeyDisplay = "hotkeyKeyDisplay"
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "appLanguage") }
    }
    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: Key.retentionDays) } }
    @Published var maximumItems: Int { didSet { defaults.set(maximumItems, forKey: Key.maximumItems) } }
    @Published var pasteAutomatically: Bool {
        didSet { defaults.set(pasteAutomatically, forKey: Key.pasteAutomatically) }
    }
    @Published var preferPlainText: Bool { didSet { defaults.set(preferPlainText, forKey: Key.preferPlainText) } }
    @Published var globalHotkey: GlobalHotkey {
        didSet {
            defaults.set(Int(globalHotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(globalHotkey.carbonModifiers), forKey: Key.hotkeyModifiers)
            defaults.set(globalHotkey.keyEquivalent, forKey: Key.hotkeyKeyEquivalent)
            defaults.set(globalHotkey.keyDisplay, forKey: Key.hotkeyKeyDisplay)
        }
    }
    @Published private(set) var hotkeyRegistrationSucceeded = true
    @Published private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @Published var excludedBundleIDsText: String {
        didSet {
            let values = excludedBundleIDsText.split(whereSeparator: { $0 == "\n" || $0 == "," }).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            defaults.set(values, forKey: Key.excludedBundleIDs)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.retentionDays: 90,
            Key.maximumItems: 10_000,
            Key.pasteAutomatically: true,
            Key.preferPlainText: false,
            Key.hotkeyKeyCode: Int(GlobalHotkey.defaultValue.keyCode),
            Key.hotkeyModifiers: Int(GlobalHotkey.defaultValue.carbonModifiers),
            Key.hotkeyKeyEquivalent: GlobalHotkey.defaultValue.keyEquivalent,
            Key.hotkeyKeyDisplay: GlobalHotkey.defaultValue.keyDisplay,
            Key.excludedBundleIDs: [
                "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
                "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
            ],
        ])
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "system") ?? .system
        isPaused = defaults.bool(forKey: Key.isPaused)
        retentionDays = defaults.integer(forKey: Key.retentionDays)
        maximumItems = defaults.integer(forKey: Key.maximumItems)
        pasteAutomatically = defaults.bool(forKey: Key.pasteAutomatically)
        preferPlainText = defaults.bool(forKey: Key.preferPlainText)
        globalHotkey = GlobalHotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
            carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers)),
            keyEquivalent: defaults.string(forKey: Key.hotkeyKeyEquivalent) ?? GlobalHotkey.defaultValue.keyEquivalent,
            keyDisplay: defaults.string(forKey: Key.hotkeyKeyDisplay) ?? GlobalHotkey.defaultValue.keyDisplay
        )
        excludedBundleIDsText = (defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []).joined(separator: "\n")
    }

    var excludedBundleIDs: Set<String> {
        Set(
            excludedBundleIDsText.split(whereSeparator: { $0 == "\n" || $0 == "," }).map {
                String($0).trimmingCharacters(in: .whitespaces)
            })
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func setHotkeyRegistrationSucceeded(_ succeeded: Bool) {
        hotkeyRegistrationSucceeded = succeeded
    }
}
