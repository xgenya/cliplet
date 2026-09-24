import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show(settings: AppSettings, store: ClipboardStore) {
        if shared == nil { shared = SettingsWindowController(settings: settings, store: store) }
        shared?.showWindow(nil)
    }

    private init(settings: AppSettings, store: ClipboardStore) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 960, height: 650)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = L10n.tr("Settings")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, store: store))
        // Hosting initially adopts the root view's minimum size; restore the
        // reference proportions after installing the content controller.
        window.setContentSize(NSSize(width: 960, height: 650))
        if !UIPreview.enabled {
            window.setFrameAutosaveName("ClipboardNativeSettingsWindow.v3")
        }
        if UIPreview.enabled || !window.setFrameUsingName("ClipboardNativeSettingsWindow.v3") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if !wasVisible { AppActivationPolicy.enter() }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
