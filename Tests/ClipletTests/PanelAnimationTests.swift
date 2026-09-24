import XCTest

@testable import ClipletKit

final class PanelAnimationTests: XCTestCase {
    func testSpringStartsAtFullDisplacementAndSettles() {
        for spring in [
            PanelSpring(scale: 0.8, response: 0.4, dampingFraction: 0.45),
            PanelSpring(scale: 0.94, response: 0.3, dampingFraction: 1),
        ] {
            XCTAssertEqual(spring.remaining(at: 0), 1, accuracy: 1e-9)
            XCTAssertEqual(spring.remaining(at: spring.settlingTime), 0, accuracy: 0.001)
        }
    }

    func testUnderdampedSpringOvershootsAndCriticalDoesNot() {
        let times = stride(from: 0.0, through: 1.5, by: 0.005)
        let bouncy = PanelSpring(scale: 0.8, response: 0.4, dampingFraction: 0.45)
        let critical = PanelSpring(scale: 0.94, response: 0.3, dampingFraction: 1)
        XCTAssertLessThan(times.map(bouncy.remaining(at:)).min()!, -0.1)
        XCTAssertGreaterThanOrEqual(times.map(critical.remaining(at:)).min()!, 0)
    }

    @MainActor func testGenieIsWithheldAndFallsBackToDefault() {
        XCTAssertFalse(PanelAnimation.offered.contains(.genie))
        XCTAssertEqual(PanelAnimation.genie.resolved, .spotlight)
        XCTAssertEqual(PanelAnimation.bounce.resolved, .bounce)
        let defaults = UserDefaults(suiteName: "PanelAnimationTests")!
        defaults.removePersistentDomain(forName: "PanelAnimationTests")
        defaults.set("genie", forKey: "panelAnimation")
        XCTAssertEqual(AppSettings(defaults: defaults).panelAnimation, .spotlight)
    }

    @MainActor func testGenieMeshIsIdentityWhenOpenAndCollapsesIntoNeck() {
        let window = CGRect(x: 300, y: 200, width: 972, height: 672)
        let neck = CGRect(x: 1400, y: 0, width: 28, height: 24)
        let open = WindowWarp.genieMesh(window: window, neck: neck, collapse: 0, rows: 8)
        XCTAssertEqual(open.count, 16)
        for point in open {
            XCTAssertEqual(point.global.x, Float(window.minX) + point.local.x, accuracy: 0.01)
            XCTAssertEqual(point.global.y, Float(window.minY) + point.local.y, accuracy: 0.01)
        }
        let collapsed = WindowWarp.genieMesh(window: window, neck: neck, collapse: 1, rows: 8)
        for point in collapsed {
            XCTAssertEqual(point.global.y, Float(neck.maxY), accuracy: 0.01)
            XCTAssertTrue((Float(neck.minX) - 0.01...Float(neck.maxX) + 0.01).contains(point.global.x))
        }
    }

    /// Overshoot and offsets must stay inside the transparent room around the
    /// glass surface, or the window bounds clip the panel's edge.
    func testEveryEntranceStaysInsideAnimationInset() {
        let size = CGSize(width: 860, height: 560)
        for animation in PanelAnimation.allCases {
            let entrance = animation.entrance
            let duration = max(entrance.horizontal.settlingTime, entrance.verticalSpring.settlingTime)
            for time in stride(from: 0.0, through: duration, by: 0.002) {
                let x = entrance.horizontal.remaining(at: time)
                let scaleX = 1 + (entrance.horizontal.scale - 1) * x
                let scaleY = 1 + (entrance.verticalSpring.scale - 1) * entrance.verticalSpring.remaining(at: time)
                let spillX = (scaleX - 1) * size.width / 2
                let spillY = (scaleY - 1) * size.height / 2 + abs(entrance.offset * x)
                XCTAssertLessThanOrEqual(spillX, OverlayPanel.animationInset, "\(animation) at \(time)")
                XCTAssertLessThanOrEqual(spillY, OverlayPanel.animationInset, "\(animation) at \(time)")
            }
        }
    }
}
