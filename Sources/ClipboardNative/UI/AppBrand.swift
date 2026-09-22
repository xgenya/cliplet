import AppKit
import SwiftUI

@MainActor
enum AppBrand {
    static var name: String { L10n.tr("Cliplet") }
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
