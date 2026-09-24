import AppKit
import SwiftUI

struct SourceAppIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier {
            WorkspaceIconView(source: .application(bundleIdentifier), pixels: 64, fallback: "square.dashed")
        } else {
            Image(systemName: "square.dashed")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}
