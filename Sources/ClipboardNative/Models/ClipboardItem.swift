import CryptoKit
import Foundation

enum ClipboardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, link, email, color, image, file

    var id: String { rawValue }

}

struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var lastUsedAt: Date
    var kind: ClipboardKind
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    var imageData: Data?
    var fileURLs: [URL]
    var sourceBundleIdentifier: String?
    var sourceApplicationName: String?
    var isPinned: Bool
    var useCount: Int
    var contentHash: String
    var customName: String?
    var payloadReferences: [String: String]? = nil
    // Nil is an older or newly captured image whose recognition has not finished.
    var recognitionCompleted: Bool? = nil
    // Runtime location is injected by the repository, never trusted from JSON.
    var payloadDirectory: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, createdAt, lastUsedAt, kind, text, rtfData, htmlData, imageData, fileURLs
        case sourceBundleIdentifier, sourceApplicationName, isPinned, useCount, contentHash, customName
        case payloadReferences, recognitionCompleted
    }

    var searchableText: String {
        ([customName, text, sourceApplicationName] + fileURLs.map(\.path)).compactMap { $0 }.joined(separator: " ")
    }

    static func hash(parts: [Data]) -> String {
        var hasher = SHA256()
        parts.forEach { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var normalizedForClipboard: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detectedClipboardKind: ClipboardKind {
        let value = normalizedForClipboard
        if value.range(of: #"^#[0-9a-fA-F]{3,8}$"#, options: .regularExpression) != nil { return .color }
        if value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil { return .email }
        if let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return .link
        }
        return .text
    }
}
