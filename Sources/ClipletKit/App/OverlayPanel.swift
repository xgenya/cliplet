import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {
    nonisolated static let cornerRadius: CGFloat = 28
    nonisolated static let animationInset: CGFloat = 12
    private weak var presentationSurface: NSView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func presentAnimated() {
        guard !isVisible else { makeKeyAndOrderFront(nil); return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = 0.12
        let timing = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        contentView?.layoutSubtreeIfNeeded()
        if let layer = presentationSurface?.layer {
            layer.removeAnimation(forKey: "panelPresentation")
            if !reduceMotion {
                // Scale the complete glass surface around its center without
                // resizing the window or reflowing the SwiftUI content.
                let scale: CGFloat = 0.92
                var transform = CATransform3DMakeScale(scale, scale, 1)
                transform.m41 = layer.bounds.width * (0.5 - layer.anchorPoint.x) * (1 - scale)
                transform.m42 = layer.bounds.height * (0.5 - layer.anchorPoint.y) * (1 - scale)
                let animation = CASpringAnimation(keyPath: "transform")
                animation.mass = 1
                animation.stiffness = 520
                animation.damping = 24
                animation.initialVelocity = 0
                animation.fromValue = NSValue(caTransform3D: transform)
                animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                animation.duration = animation.settlingDuration
                layer.add(animation, forKey: "panelPresentation")
            }
        }
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
        // Transparent room around the surface lets the spring overshoot without
        // clipping the glass rim against the native window's rectangular bounds.
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
        presentationSurface = surface
        contentView = container
        initialFirstResponder = container
    }
}
