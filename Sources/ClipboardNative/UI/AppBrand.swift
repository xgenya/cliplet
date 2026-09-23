import AppKit
import SwiftUI

@MainActor
enum AppBrand {
    static var name: String { L10n.tr("Cliplet") }
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let board = NSBezierPath(
                roundedRect: NSRect(x: 3, y: 2, width: 12, height: 13), xRadius: 2, yRadius: 2)
            board.lineWidth = 1.6
            board.stroke()
            let clip = NSBezierPath(
                roundedRect: NSRect(x: 6, y: 13, width: 6, height: 3), xRadius: 1, yRadius: 1)
            clip.lineWidth = 1.6
            clip.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
    static let icon: NSImage = {
        guard let url = AppResources.bundle.url(forResource: "AppIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)!
        }
        return image
    }()
}

struct AppBrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: AppBrand.icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
