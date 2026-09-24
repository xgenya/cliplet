import AppKit

/// Deterministic, in-memory content for screenshot review; never reads or writes real history.
enum UIPreview {
    static var enabled: Bool {
        #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
            return false
        #endif
    }

    static var items: [ClipboardItem] {
        let samples: [(ClipboardKind, String, String, String, Bool, TimeInterval)] = [
            (
                .text, "把灵感留住，让工作继续。\n\n复制过的文字、链接、图片和文件，都可以在这里快速找回。\n\n↑ ↓ 选择条目\n↵ 粘贴到当前应用\n⌘ K 打开更多操作", "备忘录",
                "com.apple.Notes", true, 60
            ),
            (.link, "https://developer.apple.com/design/", "Safari", "com.apple.Safari", false, 120),
            (.text, "Less, but better.", "备忘录", "com.apple.Notes", false, 300),
            (.color, "#E85D75", "Safari", "com.apple.Safari", false, 600),
            (.text, "设计是一种让复杂变得清晰的方式。", "备忘录", "com.apple.Notes", false, 900),
            (.email, "hello@example.com", "邮件", "com.apple.mail", false, 1200),
            (.text, "swift build -c release", "终端", "com.apple.Terminal", false, 1500),
            (.link, "https://www.raycast.com", "Safari", "com.apple.Safari", false, 86400),
            (.text, "Stay curious. Keep creating.", "备忘录", "com.apple.Notes", false, 86500),
            (.color, "#5E9E89", "Safari", "com.apple.Safari", false, 86600),
            (.text, "今天也要留一点时间给好点子。", "备忘录", "com.apple.Notes", false, 172800),
        ]
        let textItems = samples.enumerated().map { index, sample in
            ClipboardItem(
                id: UUID(), createdAt: Date().addingTimeInterval(-sample.5),
                lastUsedAt: Date().addingTimeInterval(-sample.5), kind: sample.0,
                text: sample.1, fileURLs: [], sourceBundleIdentifier: sample.3,
                sourceApplicationName: sample.2, isPinned: sample.4, useCount: 0,
                contentHash: "preview-\(index)")
        }
        let appURL = Bundle.main.bundleURL
        let documents = ["Notes.txt", "Design.pdf", "Photo.png", "Archive.zip"].map {
            URL(fileURLWithPath: "/tmp/Cliplet Preview/" + $0)
        }
        let fileGroups = [[appURL], [appURL, documents[0]], [appURL] + documents, [documents[1]]]
        let fileItems = fileGroups.enumerated().map { index, urls in
            ClipboardItem(
                id: UUID(), createdAt: Date().addingTimeInterval(-Double(index)),
                lastUsedAt: Date(), kind: .file, text: nil, fileURLs: urls,
                sourceBundleIdentifier: "com.apple.finder", sourceApplicationName: "Finder",
                isPinned: false, useCount: 0, contentHash: "preview-files-\(index)")
        }
        let samplesForHistory = textItems + fileItems
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--stress-history") {
                let image = AppResources.bundle.url(forResource: "AppIcon", withExtension: "png")
                    .flatMap { try? Data(contentsOf: $0) }
                return (0..<10_000).map { index in
                    var item = samplesForHistory[index % samplesForHistory.count]
                    item.id = UUID()
                    item.createdAt = Date().addingTimeInterval(-Double(index * 60))
                    item.isPinned = index % 97 == 0
                    item.customName = "Preview \(index) · " + (item.text?.prefix(40).description ?? "Files")
                    item.contentHash = "stress-\(index)"
                    if index % 4 == 0, let image {
                        item.kind = .image
                        item.imageData = image
                        item.text = nil
                        item.fileURLs = []
                    }
                    return item
                }
            }
        #endif
        return samplesForHistory
    }
}
