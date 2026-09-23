import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenRequests: AppReopenRequests?
    private let settings = AppSettings.shared
    private lazy var store = ClipboardStore(
        settings: settings,
        repository: UIPreview.enabled
            ? MemoryHistoryRepository(items: UIPreview.items)
            : HistoryRepository(directory: HistoryRepository.defaultDirectory),
        maintenanceInterval: UIPreview.enabled ? nil : 60
    )
    private lazy var viewState = ClipboardViewState(store: store)
    private lazy var monitor = ClipboardMonitor(store: store, settings: settings)
    private let hotkey = HotkeyService()
    private lazy var pasteService = PasteService(settings: settings)
    private var panel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var previousApplication: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var storageSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    private var hotkeySubscription: AnyCancellable?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppBrand.icon
        NSApp.setActivationPolicy(.accessory)
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.rememberExternalApplication(application) }
        }
        buildMainMenu()
        buildStatusItem()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--seed-demo-data") {
                MockDataFactory.items.forEach { store.add($0) }
            }
        #endif
        languageSubscription = settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.buildMainMenu()
            self.buildStatusItem()
            self.panel?.title = L10n.tr("Clipboard History")
            self.panel?.setAccessibilityTitle(L10n.tr("Clipboard History"))
        }
        if !UIPreview.enabled { monitor.start() }
        pasteService.monitor = monitor
        storageSubscription = store.$storageError.removeDuplicates().receive(on: RunLoop.main).sink {
            [weak self] message in
            guard let self, !self.isTerminating, let message else { return }
            let alert = NSAlert()
            alert.messageText = L10n.tr("History Storage Error")
            alert.informativeText =
                L10n.tr(
                    "History could not be read or saved. Existing data has been preserved where possible. Recent changes may only be available until you quit."
                ) + "\n\n" + message
            alert.runModal()
        }
        hotkey.onPressed = { [weak self] in self?.togglePanel() }
        if !UIPreview.enabled {
            registerHotkey(settings.globalHotkey)
            hotkeySubscription = settings.$globalHotkey.dropFirst().receive(on: RunLoop.main).sink {
                [weak self] shortcut in
                guard let self else { return }
                self.registerHotkey(shortcut)
                self.buildMainMenu()
                self.buildStatusItem()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        reopenRequests?.onRequest = { [weak self] in self?.showPanel() }
        reopenRequests?.onReplacement = { NSApp.terminate(nil) }
        if UIPreview.enabled {
            NSApp.appearance = NSAppearance(
                named: ProcessInfo.processInfo.arguments.contains("--light") ? .aqua : .darkAqua)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if ProcessInfo.processInfo.arguments.contains("--settings-preview") {
                    SettingsWindowController.show(settings: self.settings, store: self.store)
                } else {
                    self.showPanel()
                }
            }
            return
        }
        if !AppEnvironment.current.defaults.bool(forKey: "hasShownFirstLaunchWindow") {
            AppEnvironment.current.defaults.set(true, forKey: "hasShownFirstLaunchWindow")
            DispatchQueue.main.async { [weak self] in self?.showPanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        pasteService.cancelPendingPaste()
        monitor.stop()
        do {
            try store.flush()
            return .terminateNow
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.tr("History Could Not Be Saved")
            alert.informativeText = L10n.tr("Quitting now may lose recent changes. Cancel to keep the app open.")
            alert.addButton(withTitle: L10n.tr("Cancel"))
            alert.addButton(withTitle: L10n.tr("Quit Anyway"))
            if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }
            isTerminating = false
            if !UIPreview.enabled { monitor.start() }
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteService.cancelPendingPaste()
        monitor.stop()
        store.stopMaintenance()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
    }

    private func buildStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppBrand.menuBarIcon
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = L10n.tr("Clipboard History")
        let menu = NSMenu()
        let openItem = menu.addItem(
            withTitle: L10n.tr("Open Clipboard History"), action: #selector(openFromMenu),
            keyEquivalent: settings.globalHotkey.keyEquivalent)
        openItem.keyEquivalentModifierMask = settings.globalHotkey.appKitModifiers
        openItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(NSMenuItem.separator())
        let pause = NSMenuItem(
            title: L10n.tr(settings.isPaused ? "Resume Recording" : "Pause Recording"), action: #selector(togglePause),
            keyEquivalent: "")
        pause.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)
        let settingsItem = menu.addItem(
            withTitle: L10n.tr("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(NSMenuItem.separator())
        let quitItem = menu.addItem(
            withTitle: L10n.tr("Quit Cliplet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        item.menu = menu
        statusItem = item
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: AppBrand.name)
        let historyItem = appMenu.addItem(
            withTitle: L10n.tr("Open Clipboard History"), action: #selector(openFromMenu),
            keyEquivalent: settings.globalHotkey.keyEquivalent)
        historyItem.target = self
        historyItem.keyEquivalentModifierMask = settings.globalHotkey.appKitModifiers
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.tr("About Cliplet"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = appMenu.addItem(
            withTitle: L10n.tr("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: L10n.tr("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L10n.tr("Services"))
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.tr("Hide Cliplet"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: L10n.tr("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: L10n.tr("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.tr("Quit Cliplet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.tr("Edit"))
        editMenu.addItem(withTitle: L10n.tr("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.tr("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.tr("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L10n.tr("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.tr("Window"))
        windowMenu.addItem(
            withTitle: L10n.tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(
            withTitle: L10n.tr("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openFromMenu() { showPanel() }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settings.isPaused.toggle()
        sender.state = settings.isPaused ? .on : .off
        sender.title = L10n.tr(settings.isPaused ? "Resume Recording" : "Pause Recording")
    }

    @objc private func openSettings() { showSettings() }

    private func togglePanel() {
        // A panel hidden on deactivation can still report isVisible. Only
        // toggle off the focused panel; otherwise bring it back on the first press.
        if NSApp.isActive, let panel, panel.isVisible, panel.isKeyWindow {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.presentAnimated()
        viewState.selectFirstIfNeeded()
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
            application.bundleIdentifier != Bundle.main.bundleIdentifier,
            !application.isTerminated
        else { return }
        previousApplication = application
    }

    private func closePanel() {
        viewState.showActions = false
        panel?.orderOut(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(
                x: 0, y: 0, width: 860 + 2 * OverlayPanel.animationInset, height: 560 + 2 * OverlayPanel.animationInset),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.title = L10n.tr("Clipboard History")
        panel.setAccessibilityTitle(L10n.tr("Clipboard History"))
        let root = MainView(
            store: store,
            viewState: viewState,
            settings: settings,
            onPaste: { [weak self] in self?.paste($0) },
            onCopy: { [weak self] in self?.copy($0) },
            onCopyText: { [weak self] in self?.copyText($0) },
            onRename: { [weak self] in self?.rename($0) },
            onSettings: { [weak self] in self?.showSettings() }
        )
        panel.installContent(root)
        return panel
    }

    private func position(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { window.center(); return }
        let origin = NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2 + 24)
        window.setFrameOrigin(origin)
    }

    private func paste(_ item: ClipboardItem) {
        closePanel()
        pasteService.paste(item, into: previousApplication) { [weak self] succeeded in
            if succeeded { self?.store.markUsed(item.id) }
        }
    }

    private func copy(_ item: ClipboardItem) {
        if pasteService.write(item, plainText: settings.preferPlainText) {
            store.markUsed(item.id)
            closePanel()
        }
    }

    private func copyText(_ text: String) {
        pasteService.cancelPendingPaste()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        monitor.ignoreCurrentChange()
        closePanel()
    }

    private func rename(_ item: ClipboardItem) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Rename Clipboard Entry")
        alert.informativeText = L10n.tr(
            "Give this entry a searchable name. Leave it empty to restore the original title.")
        alert.addButton(withTitle: L10n.tr("Save"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        let field = NSTextField(string: item.customName ?? "")
        field.placeholderString = item.displayTitle
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn { store.rename(item.id, to: field.stringValue) }
    }

    private func registerHotkey(_ shortcut: GlobalHotkey) {
        settings.setHotkeyRegistrationSucceeded(hotkey.register(shortcut))
    }

    private func showSettings() {
        closePanel()
        SettingsWindowController.show(settings: settings, store: store)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard panel?.isKeyWindow == true else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {
            if viewState.showActions { viewState.showActions = false } else { closePanel() }
            return true
        }
        if viewState.showActions {
            if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
                viewState.showActions = false
                return true
            }
            // The focused action search owns arrows/Return and the menu's buttons
            // own their shortcuts. Never navigate or paste a history item here.
            return false
        }
        if event.keyCode == 125 { viewState.select(offset: 1); return true }
        if event.keyCode == 126 { viewState.select(offset: -1); return true }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let item = viewState.selectedItem {
                flags.contains(.command) ? copy(item) : paste(item)
            }
            return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers == ".", let id = viewState.selectedItem?.id {
            store.togglePin(id); return true
        }
        if flags.contains(.control), event.charactersIgnoringModifiers?.lowercased() == "x",
            let id = viewState.selectedItem?.id
        {
            store.delete(id); return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "o",
            let item = viewState.selectedItem
        {
            open(item); return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "e",
            let item = viewState.selectedItem
        {
            rename(item); return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers == "," { showSettings(); return true }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
            viewState.toggleActions(); return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            viewState.cycleFilter(); return true
        }
        return false
    }

    private func open(_ item: ClipboardItem) {
        if item.kind == .link, let text = item.text, let url = URL(string: text) {
            NSWorkspace.shared.open(url)
        } else if item.kind == .file, let url = item.fileURLs.first {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
