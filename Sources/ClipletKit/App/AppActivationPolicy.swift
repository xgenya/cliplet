import AppKit

@MainActor
enum AppActivationPolicy {
    private static var windowCount = 0

    static func enter() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        windowCount = max(0, windowCount - 1)
        guard windowCount == 0 else { return }
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}
