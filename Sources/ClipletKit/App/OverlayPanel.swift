import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {
    nonisolated static let cornerRadius: CGFloat = 28
    nonisolated static let animationInset: CGFloat = 12
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func presentAnimated() {
        guard !isVisible else { makeKeyAndOrderFront(nil); return }
        let duration = 0.12
        let timing = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        contentView?.layoutSubtreeIfNeeded()
        // Only fade: a layer transform on the glass surface drops text-field
        // vibrancy until it settles, so the search text renders pale.
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        // Focusing the search field on open shows the input-method indicator, which
        // flashes as a large block; the first typed character focuses it instead.
        makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            animator().alphaValue = 1
        }
    }

    func installContent<Content: View>(_ root: Content) {
        let hosting = NSHostingView(rootView: root)
        // One native mask trims both the material and its content. A second
        // SwiftUI mask used a different curve and exposed footer corners.
        // Transparent room around the surface keeps the glass rim from clipping
        // against the native window's rectangular bounds.
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let surface = NSView(frame: container.bounds.insetBy(dx: Self.animationInset, dy: Self.animationInset))
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
        surface.layer?.cornerRadius = Self.cornerRadius
        surface.layer?.masksToBounds = true
        let material: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = hosting
            material = glass
        } else {
            let legacy = NSVisualEffectView()
            legacy.material = .hudWindow
            legacy.blendingMode = .behindWindow
            legacy.state = .active
            hosting.translatesAutoresizingMaskIntoConstraints = false
            legacy.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: legacy.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: legacy.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: legacy.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: legacy.bottomAnchor),
            ])
            material = legacy
        }
        material.frame = surface.bounds
        material.autoresizingMask = [.width, .height]
        surface.addSubview(material)
        container.addSubview(surface)
        contentView = container
        initialFirstResponder = container
    }
}
