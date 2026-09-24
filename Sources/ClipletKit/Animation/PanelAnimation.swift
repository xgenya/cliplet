import Foundation

enum PanelAnimation: String, CaseIterable, Identifiable {
    case none, fade, spotlight, scale, bounce, slide, drop, genie

    /// The presets offered in Settings. Genie depends on a private window-server
    /// API and is withheld for now.
    static let offered: [PanelAnimation] = allCases.filter { $0 != .genie }

    /// A stored preset that is no longer offered falls back to the default.
    var resolved: PanelAnimation { Self.offered.contains(self) ? self : .spotlight }

    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .none: return L10n.tr("None")
        case .fade: return L10n.tr("Fade")
        case .spotlight: return L10n.tr("Spotlight")
        case .scale: return L10n.tr("Zoom")
        case .bounce: return L10n.tr("Bounce")
        case .slide: return L10n.tr("Slide Up")
        case .drop: return L10n.tr("Drop In")
        case .genie: return L10n.tr("Genie")
        }
    }

    var entrance: PanelEntrance {
        switch self {
        case .none: return PanelEntrance(fadeDuration: 0)
        case .fade: return PanelEntrance(fadeDuration: 0.12)
        case .spotlight:
            return PanelEntrance(scale: 0.85, blur: 14, response: 0.32, dampingFraction: 0.7, fadeDuration: 0.14)
        case .scale: return PanelEntrance(scale: 0.9, response: 0.24, dampingFraction: 0.88, fadeDuration: 0.12)
        case .bounce:
            // Out-of-phase axes: height overshoots while width is still catching
            // up, so the glass stretches and settles like a liquid.
            return PanelEntrance(
                scale: 0.82, response: 0.4, dampingFraction: 0.5,
                vertical: PanelSpring(scale: 0.7, response: 0.32, dampingFraction: 0.42), fadeDuration: 0.1)
        case .slide: return PanelEntrance(offset: 48, response: 0.3, dampingFraction: 0.82, fadeDuration: 0.14)
        case .drop:
            return PanelEntrance(scale: 0.95, offset: -48, response: 0.34, dampingFraction: 0.62, fadeDuration: 0.14)
        // The window warp carries the motion; the surface itself stays put.
        case .genie: return PanelEntrance(fadeDuration: 0.08)
        }
    }

    /// What the settings preview plays. SwiftUI cannot warp a mesh, so the
    /// Genie effect is approximated by a sliver that stretches down and widens.
    var previewEntrance: PanelEntrance {
        guard self == .genie else { return entrance }
        return PanelEntrance(
            scale: 0.06, offset: -240, response: 0.5, dampingFraction: 0.9,
            vertical: PanelSpring(scale: 0.04, response: 0.34, dampingFraction: 0.9), fadeDuration: 0.08)
    }
}

/// The pose a panel springs back from when it opens. A positive offset starts
/// the panel below its resting place, a negative one above it. Height follows
/// the width's spring unless `vertical` gives it its own.
struct PanelEntrance {
    var scale: CGFloat = 1
    var offset: CGFloat = 0
    var blur: CGFloat = 0
    var response: Double = 0.3
    var dampingFraction: Double = 1
    var vertical: PanelSpring?
    var fadeDuration: Double = 0.14
    var blurDuration: Double = 0.24

    var horizontal: PanelSpring { PanelSpring(scale: scale, response: response, dampingFraction: dampingFraction) }
    var verticalSpring: PanelSpring { vertical ?? horizontal }
    var moves: Bool { scale != 1 || offset != 0 || verticalSpring.scale != 1 }
}

/// A SwiftUI-style spring from `scale` back to 1, released at rest.
struct PanelSpring {
    var scale: CGFloat
    var response: Double
    var dampingFraction: Double

    /// The fraction of the starting displacement left at `time`: 1 at release,
    /// settling toward 0, negative while overshooting.
    func remaining(at time: Double) -> Double {
        let omega = 2 * Double.pi / response
        guard dampingFraction < 1 else { return exp(-omega * time) * (1 + omega * time) }
        let damped = omega * (1 - dampingFraction * dampingFraction).squareRoot()
        let decay = exp(-dampingFraction * omega * time)
        return decay * (cos(damped * time) + dampingFraction * omega / damped * sin(damped * time))
    }

    /// When the remaining displacement stays below about a thousandth, a tenth
    /// of a point on the panel. The decay bound is tightened twentyfold to cover
    /// the linear factor in a critically damped spring's tail.
    var settlingTime: Double {
        let omega = 2 * Double.pi / response
        return min(-log(0.00005) / (min(dampingFraction, 1) * omega), 1.5)
    }
}
