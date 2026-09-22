import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
final class PasteService {
    weak var monitor: ClipboardMonitor?
    private let settings: AppSettings
    private let pasteboard: ClipboardAccess

    init(settings: AppSettings = .shared, pasteboard: ClipboardAccess = SystemClipboard()) {
        self.settings = settings
        self.pasteboard = pasteboard
    }
    private struct PendingPaste {
        let item: ClipboardItem
        let application: NSRunningApplication
        let completion: (Bool) -> Void
    }

    private var pendingPaste: PendingPaste?
    private var permissionTimer: Timer?
    private var permissionDeadline: Date?
    private var hasRequestedAccessibilityPermission = false

    func write(_ item: ClipboardItem, plainText: Bool = false) -> Bool {
        // Read all required payloads before altering the user's clipboard.
        let usePlainText = plainText && item.text != nil
        let imageData: Data?
        let rtfData: Data?
        let htmlData: Data?
        do {
            imageData = usePlainText ? nil : try item.payloadData(for: "image")
            rtfData = usePlainText ? nil : try item.payloadData(for: "rtf")
            htmlData = usePlainText ? nil : try item.payloadData(for: "html")
        } catch { return false }
        let image = imageData.flatMap(NSImage.init(data:))
        if item.kind == .image, !usePlainText, image == nil { return false }
        if item.kind != .image, item.kind != .file, item.text == nil { return false }
        defer { monitor?.ignoreCurrentChange() }
        pasteboard.clear()
        if usePlainText, let text = item.text { return pasteboard.writeText(text, rtf: nil, html: nil) }
        switch item.kind {
        case .image:
            guard let image else { return false }
            return pasteboard.writeImage(image)
        case .file:
            return pasteboard.writeFiles(item.fileURLs)
        default:
            guard let text = item.text else { return false }
            return pasteboard.writeText(text, rtf: rtfData, html: htmlData)
        }
    }

    func paste(_ item: ClipboardItem, into application: NSRunningApplication?, completion: @escaping (Bool) -> Void) {
        guard write(item, plainText: settings.preferPlainText) else { completion(false); return }
        guard settings.pasteAutomatically, let application else { completion(true); return }
        guard AXIsProcessTrusted() else {
            pendingPaste?.completion(false)
            pendingPaste = PendingPaste(item: item, application: application, completion: completion)
            requestAccessibilityPermissionOnce()
            waitForAccessibilityPermission()
            return
        }

        performPaste(into: application, completion: completion)
    }

    private func requestAccessibilityPermissionOnce() {
        guard !hasRequestedAccessibilityPermission else { return }
        hasRequestedAccessibilityPermission = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func waitForAccessibilityPermission() {
        permissionDeadline = Date().addingTimeInterval(60)
        guard permissionTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAccessibilityPermission() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func checkAccessibilityPermission() {
        guard let pendingPaste else {
            stopPermissionTimer()
            return
        }
        if AXIsProcessTrusted() {
            self.pendingPaste = nil
            hasRequestedAccessibilityPermission = false
            stopPermissionTimer()
            guard write(pendingPaste.item, plainText: settings.preferPlainText) else {
                pendingPaste.completion(false)
                return
            }
            performPaste(into: pendingPaste.application, completion: pendingPaste.completion)
        } else if permissionDeadline.map({ Date() >= $0 }) == true {
            self.pendingPaste = nil
            stopPermissionTimer()
            pendingPaste.completion(false)
        }
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionDeadline = nil
    }

    private func performPaste(into application: NSRunningApplication, completion: @escaping (Bool) -> Void) {
        guard !application.isTerminated else { completion(false); return }
        application.activate()
        deliverPaste(into: application, attempt: 0, completion: completion)
    }

    private func deliverPaste(
        into application: NSRunningApplication, attempt: Int, completion: @escaping (Bool) -> Void
    ) {
        guard !application.isTerminated else { completion(false); return }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        if !isFrontmost {
            guard attempt < 12 else { completion(false); return }
            application.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.deliverPaste(into: application, attempt: attempt + 1, completion: completion)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            guard let down, let up else { completion(false); return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            completion(true)
        }
    }

    isolated deinit {
        permissionTimer?.invalidate()
    }
}
