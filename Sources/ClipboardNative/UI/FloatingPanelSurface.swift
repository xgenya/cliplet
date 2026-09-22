import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func floatingPanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            // Keep text and controls above the material rather than including
            // the entire content subtree in the glass compositing pass.
            self.clipShape(shape).background { Color.clear.glassEffect(.regular, in: shape) }
        } else {
            self.clipShape(shape).background(LegacyPanelMaterial().clipShape(shape))
                .overlay { shape.strokeBorder(.separator.opacity(0.5)) }
        }
    }
}

private struct LegacyPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
