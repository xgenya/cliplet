import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {
    nonisolated static let cornerRadius: CGFloat = 28
    /// Room for entrance offsets and spring overshoot inside the window bounds.
    nonisolated static let animationInset: CGFloat = 56
    private weak var glassView: NSView?
    private weak var tintView: PanelTintView?
    private var entranceAnimator: PanelEntranceAnimator?
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Deferred so a modal alert or sheet has already taken key status; those
        // return to the panel, while any other window dismisses it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow, self.attachedSheet == nil,
                NSApp.modalWindow == nil
            else { return }
            self.onResignKey?()
        }
    }

    /// `origin` is where the Genie effect emerges from, in screen coordinates.
    func presentAnimated(_ animation: PanelAnimation, from origin: NSRect) {
        guard !isVisible else { makeKeyAndOrderFront(nil); return }
        var animation = animation
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, animation != .none { animation = .fade }
        if animation == .genie, entranceAnimator?.startGenie(from: origin) != true { animation = .scale }
        let entrance = animation.entrance
        contentView?.layoutSubtreeIfNeeded()
        entranceAnimator?.playSpring(entrance)
        alphaValue = animation == .none ? 1 : 0
        makeKeyAndOrderFront(nil)
        // Focusing the search field on open shows the input-method indicator, which
        // flashes as a large block; the first typed character focuses it instead.
        makeFirstResponder(nil)
        guard animation != .none else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = entrance.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    override func orderOut(_ sender: Any?) {
        entranceAnimator?.stopGenie()
        super.orderOut(sender)
    }

    func setGlass(legibility: Double, unrestricted: Bool) {
        let look = PanelGlass.look(legibility: legibility, unrestricted: unrestricted)
        let tint = look.tint
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.style = look.clear ? .clear : .regular
            // Resolve against the panel's appearance; the glass would otherwise
            // capture the light variant and turn a dark panel white.
            var color: NSColor?
            effectiveAppearance.performAsCurrentDrawingAppearance {
                color = NSColor.windowBackgroundColor.withAlphaComponent(tint).usingColorSpace(.sRGB)
            }
            glass.tintColor = tint > 0 ? color : nil
        }
        tintView?.opacity = CGFloat(tint)
    }

    func installContent<Content: View>(_ root: Content) {
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
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
            let content = NSView()
            let tint = PanelTintView()
            for view in [tint, hosting] {
                view.frame = content.bounds
                view.autoresizingMask = [.width, .height]
                content.addSubview(view)
            }
            tintView = tint
            content.translatesAutoresizingMaskIntoConstraints = false
            legacy.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: legacy.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: legacy.trailingAnchor),
                content.topAnchor.constraint(equalTo: legacy.topAnchor),
                content.bottomAnchor.constraint(equalTo: legacy.bottomAnchor),
            ])
            material = legacy
        }
        material.frame = surface.bounds
        material.autoresizingMask = [.width, .height]
        surface.addSubview(material)
        container.addSubview(surface)
        entranceAnimator = PanelEntranceAnimator(window: self, surface: surface, content: hosting)
        glassView = material
        contentView = container
        initialFirstResponder = container
    }
}

/// By default the range runs from standard glass to a half-opaque window-colored
/// tint. The clear glass variant barely blurs, so text behind the panel can
/// collide with its content; it and a fully opaque tint are opt-in only.
enum PanelGlass {
    struct Look: Equatable {
        var clear: Bool
        var tint: Double
    }

    @MainActor static func look(legibility: Double, unrestricted: Bool) -> Look {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return Look(clear: false, tint: 0.5) }
        guard unrestricted else { return Look(clear: false, tint: legibility * 0.5) }
        if #available(macOS 26.0, *), legibility < 0.5 { return Look(clear: true, tint: legibility * 0.6) }
        return Look(clear: false, tint: max(legibility - 0.5, 0) * 2)
    }
}

private final class PanelTintView: NSView {
    var opacity: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(opacity).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
