import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Combine

@MainActor
final class PasteService {
    weak var monitor: ClipboardMonitor?
    private let settings: AppSettings
    private let pasteboard: ClipboardAccess

    init(settings: AppSettings = .shared, pasteboard: ClipboardAccess = SystemClipboard()) {
        self.settings = settings
        self.pasteboard = pasteboard
    }
    private struct PasteRequest {
        let id: UUID
        let application: NSRunningApplication
        let clipboardChangeCount: Int
        let completion: (Bool) -> Void
    }

    private var activeRequest: PasteRequest?
    private var permissionTimer: Timer?
    private var permissionDeadline: Date?
    private var hasRequestedAccessibilityPermission = false
    private var automaticPasteSubscription: AnyCancellable?

    private func observeSettings() {
        guard automaticPasteSubscription == nil else { return }
        automaticPasteSubscription = settings.$pasteAutomatically.sink { [weak self] enabled in
            if !enabled { self?.cancelPendingPaste() }
        }
    }

    func cancelPendingPaste() {
        let request = activeRequest
        activeRequest = nil
        stopPermissionTimer()
        hasRequestedAccessibilityPermission = false
        request?.completion(false)
    }

    func write(_ item: ClipboardItem, plainText: Bool = false) -> Bool {
        cancelPendingPaste()
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
        observeSettings()
        guard write(item, plainText: settings.preferPlainText) else { completion(false); return }
        guard settings.pasteAutomatically, let application else { completion(true); return }
        let request = PasteRequest(
            id: UUID(), application: application, clipboardChangeCount: pasteboard.changeCount, completion: completion)
        activeRequest = request
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionOnce()
            waitForAccessibilityPermission()
            return
        }

        performPaste(request)
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
        guard let request = activeRequest else {
            stopPermissionTimer()
            return
        }
        guard isRequestValid(request) else { cancelPendingPaste(); return }
        if AXIsProcessTrusted() {
            hasRequestedAccessibilityPermission = false
            stopPermissionTimer()
            performPaste(request)
        } else if permissionDeadline.map({ Date() >= $0 }) == true {
            cancelPendingPaste()
        }
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionDeadline = nil
    }

    private func isRequestValid(_ request: PasteRequest) -> Bool {
        activeRequest?.id == request.id && settings.pasteAutomatically
            && pasteboard.changeCount == request.clipboardChangeCount && !request.application.isTerminated
    }

    private func finish(_ request: PasteRequest, succeeded: Bool) {
        guard activeRequest?.id == request.id else { return }
        activeRequest = nil
        stopPermissionTimer()
        request.completion(succeeded)
    }

    private func performPaste(_ request: PasteRequest) {
        guard isRequestValid(request) else { finish(request, succeeded: false); return }
        request.application.activate()
        deliverPaste(request, attempt: 0)
    }

    private func deliverPaste(_ request: PasteRequest, attempt: Int) {
        guard isRequestValid(request) else { finish(request, succeeded: false); return }
        let isFrontmost =
            NSWorkspace.shared.frontmostApplication?.processIdentifier == request.application.processIdentifier
        if !isFrontmost {
            guard attempt < 12 else { finish(request, succeeded: false); return }
            request.application.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.deliverPaste(request, attempt: attempt + 1)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            guard self.isRequestValid(request), AXIsProcessTrusted(),
                NSWorkspace.shared.frontmostApplication?.processIdentifier == request.application.processIdentifier
            else { self.finish(request, succeeded: false); return }
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            guard let down, let up else { self.finish(request, succeeded: false); return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            self.finish(request, succeeded: true)
        }
    }

    isolated deinit {
        permissionTimer?.invalidate()
    }
}
