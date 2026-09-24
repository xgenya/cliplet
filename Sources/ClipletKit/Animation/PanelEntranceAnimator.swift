import AppKit
import QuartzCore

/// Plays a panel's entrance: spring keyframes on its glass surface, or the
/// Genie window warp. The panel owns presentation; this owns the motion.
@MainActor
final class PanelEntranceAnimator {
    private weak var window: NSWindow?
    private weak var surface: NSView?
    private weak var content: NSView?
    private var genieTimer: Timer?

    /// `surface` is the layer-backed view that scales; `content` is the hosting
    /// view the Genie cover is drawn behind.
    init(window: NSWindow, surface: NSView, content: NSView) {
        self.window = window
        self.surface = surface
        self.content = content
    }

    /// Springs the glass surface back from the entrance pose, scaling around its
    /// center, without resizing the window or reflowing the SwiftUI content.
    /// Sampled from the same springs SwiftUI uses, so the settings preview
    /// matches, and so width and height can follow different springs.
    func playSpring(_ entrance: PanelEntrance) {
        guard entrance.moves, let layer = surface?.layer else { return }
        let horizontal = entrance.horizontal
        let vertical = entrance.verticalSpring
        let duration = max(horizontal.settlingTime, vertical.settlingTime)
        let frameCount = max(Int(duration * 120), 2)
        let bounds = layer.bounds
        let anchor = layer.anchorPoint
        let values = (0...frameCount).map { frame -> NSValue in
            let time = duration * Double(frame) / Double(frameCount)
            let x = horizontal.remaining(at: time)
            let scaleX = 1 + (horizontal.scale - 1) * x
            let scaleY = 1 + (vertical.scale - 1) * vertical.remaining(at: time)
            var transform = CATransform3DMakeScale(scaleX, scaleY, 1)
            transform.m41 = bounds.width * (0.5 - anchor.x) * (1 - scaleX)
            // Layer coordinates point up, so starting below means a negative offset.
            transform.m42 = bounds.height * (0.5 - anchor.y) * (1 - scaleY) - entrance.offset * x
            return NSValue(caTransform3D: transform)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.duration = duration
        animation.calculationMode = .linear
        layer.add(animation, forKey: "panelPresentation")
    }

    /// Collapses the window into `origin` before it is shown, then unwarps it
    /// frame by frame. Returns false when the window server refuses the warp.
    func startGenie(from origin: NSRect) -> Bool {
        guard let window, WindowWarp.isAvailable, let primaryHeight = NSScreen.screens.first?.frame.height else {
            return false
        }
        stopGenie()
        let frame = window.frame
        let windowRect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let neck = CGRect(x: origin.midX - 14, y: primaryHeight - origin.maxY, width: 28, height: origin.height)
        let rows = 48
        let mesh: @Sendable (Double) -> [WindowWarp.MeshPoint] = { collapse in
            WindowWarp.genieMesh(window: windowRect, neck: neck, collapse: collapse, rows: rows)
        }
        guard WindowWarp.apply(mesh(1), columns: 2, rows: rows, to: window) else { return false }
        // The window server draws the shadow unwarped, as a slab at the final frame.
        window.hasShadow = false
        // A warped window gets no backdrop, so the glass falls back to flat gray;
        // a window-colored cover stands in until the warp ends.
        var cover: CGColor?
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            cover = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)?.cgColor
        }
        content?.layer?.removeAnimation(forKey: "genieCover")
        content?.layer?.backgroundColor = cover
        let start = CACurrentMediaTime()
        let duration = 0.5
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                let progress = min((CACurrentMediaTime() - start) / duration, 1)
                guard progress < 1 else { self.stopGenie(); return }
                // Ease-in-out cubic, as the Dock's own minimize runs.
                let eased =
                    progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(-2 * progress + 2, 3) / 2
                WindowWarp.apply(mesh(1 - eased), columns: 2, rows: rows, to: window)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        genieTimer = timer
        return true
    }

    /// Ends a running Genie warp and restores the shadow and glass.
    func stopGenie() {
        guard let genieTimer else { return }
        genieTimer.invalidate()
        self.genieTimer = nil
        guard let window else { return }
        WindowWarp.reset(window)
        window.hasShadow = true
        window.invalidateShadow()
        if let layer = content?.layer, let cover = layer.backgroundColor {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = cover
            fade.duration = window.isVisible ? 0.25 : 0
            layer.backgroundColor = nil
            layer.add(fade, forKey: "genieCover")
        }
    }
}
