import AppKit

@MainActor
extension ClipboardKind {
    var title: String {
        switch self {
        case .text: return L10n.tr("Text")
        case .link: return L10n.tr("Links")
        case .email: return L10n.tr("Emails")
        case .color: return L10n.tr("Colors")
        case .image: return L10n.tr("Images")
        case .file: return L10n.tr("Files")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .email: return "envelope"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

@MainActor
extension ClipboardItem {
    var displayTitle: String {
        if let customName, !customName.isEmpty { return customName }
        if kind == .file {
            if fileURLs.count == 1 { return fileURLs[0].lastPathComponent }
            return L10n.format("%d files", fileURLs.count)
        }
        if kind == .image { return L10n.tr("Image") }
        let firstLine =
            text?.prefix(200).split(maxSplits: 1, whereSeparator: \.isNewline).first.map(String.init) ?? kind.title
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detail: String {
        switch kind {
        case .image:
            if let imageData = resolvedImageData, let image = NSImage(data: imageData) {
                return "\(Int(image.size.width)) × \(Int(image.size.height))"
            }
            return L10n.tr("Image")
        case .file:
            return fileURLs.count == 1 ? fileURLs[0].path : L10n.format("%d files", fileURLs.count)
        default:
            return text ?? ""
        }
    }

}
