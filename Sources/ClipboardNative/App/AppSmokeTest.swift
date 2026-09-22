import AppKit
import SwiftUI

@MainActor
enum AppSmokeTest {
    enum Failure: Error { case identity, preferences, resources, localization, window }

    /// Exercises a relocated package including real settings initialization,
    /// without changing saved settings or starting history, capture, or hotkeys.
    /// No production AppDelegate is constructed.
    static func run() throws {
        guard Bundle.main.bundleIdentifier == AppEnvironment.current.bundleIdentifier else { throw Failure.identity }
        let defaults = AppEnvironment.current.defaults
        guard defaults === UserDefaults.standard else { throw Failure.preferences }
        _ = AppSettings(defaults: defaults)
        guard let bundle = AppResources.packagedBundle,
            bundle.url(forResource: "AppIcon", withExtension: "png") != nil
        else { throw Failure.resources }
        guard L10n.tr("Copy to Clipboard", language: .simplifiedChinese) == "复制到剪贴板",
            L10n.tr("Copy to Clipboard", language: .english) == "Copy to Clipboard"
        else { throw Failure.localization }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppBrandIcon(size: 32))
        window.contentView?.layoutSubtreeIfNeeded()
        guard window.contentView != nil else { throw Failure.window }
        window.close()
        print("Cliplet package smoke test passed (\(AppEnvironment.current.bundleIdentifier))")
    }
}
