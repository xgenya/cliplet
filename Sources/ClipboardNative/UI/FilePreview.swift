import AppKit
import SwiftUI

/// Finder artwork remains the focus; paths belong in the information area.
struct FilePreview: View {
    let urls: [URL]

    var body: some View {
        FileIconStack(urls: urls, maximumIconSize: 224, showsCount: true)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                urls.count == 1 ? urls[0].lastPathComponent : L10n.format("%d files", urls.count)
            )
            .accessibilityValue(urls.prefix(3).map(\.lastPathComponent).joined(separator: ", "))
    }
}

/// The first file stays in front, with at most two offset files behind it.
/// The same composition is used for the list thumbnail and the large preview.
struct FileIconStack: View {
    let urls: [URL]
    let maximumIconSize: CGFloat
    var showsCount = false

    var body: some View {
        GeometryReader { geometry in
            let stacked = urls.count > 1
            // Allow room for rotated corners and offsets without clipping small panels.
            let extent = min(geometry.size.width, geometry.size.height)
            let side = max(0, min(maximumIconSize, extent / (stacked ? 1.4 : 1)))
            ZStack {
                if urls.isEmpty {
                    Image(systemName: "doc")
                        .resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: side, height: side)
                } else {
                    ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().scaledToFit()
                            .frame(width: side, height: side)
                            .shadow(color: .black.opacity(stacked ? 0.14 : 0), radius: side * 0.025, y: side * 0.02)
                            .rotationEffect(.degrees(index == 0 ? 0 : (index == 1 ? -12 : 10)))
                            .offset(
                                x: index == 0 ? 0 : side * (index == 1 ? -0.12 : 0.12),
                                y: index == 0 ? 0 : -side * 0.045)
                    }
                }
                if showsCount && stacked {
                    Text(urls.count.formatted(.number.locale(L10n.locale)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(.separator.opacity(0.5)) }
                        .offset(x: side * 0.4, y: side * 0.43)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
