import AppKit
import Foundation

enum MockDataFactory {
    static var items: [ClipboardItem] {
        let now = Date()
        var result: [ClipboardItem] = []

        func add(
            _ kind: ClipboardKind,
            text: String? = nil,
            imageData: Data? = nil,
            files: [URL] = [],
            app: String,
            bundleID: String,
            age: TimeInterval,
            pinned: Bool = false,
            uses: Int = 0,
            name: String? = nil,
            key: String
        ) {
            let date = now.addingTimeInterval(-age)
            result.append(
                ClipboardItem(
                    id: stableUUID(key),
                    createdAt: date,
                    lastUsedAt: date,
                    kind: kind,
                    text: text,
                    imageData: imageData,
                    fileURLs: files,
                    sourceBundleIdentifier: bundleID,
                    sourceApplicationName: app,
                    isPinned: pinned,
                    useCount: uses,
                    contentHash: "cliplet-demo-v1-\(key)",
                    customName: name
                ))
        }

        add(
            .text, text: "把灵感留住，让工作继续。", app: "备忘录", bundleID: "com.apple.Notes",
            age: 45, pinned: true, uses: 8, name: "产品标语", key: "tagline")
        add(
            .link, text: "https://developer.apple.com/design/human-interface-guidelines/", app: "Safari",
            bundleID: "com.apple.Safari", age: 95, pinned: true, uses: 4, name: "Apple HIG", key: "hig-link")
        add(
            .text, text: "Less, but better.\n\nGood design is as little design as possible.", app: "备忘录",
            bundleID: "com.apple.Notes", age: 180, uses: 2, key: "design-quote")
        add(
            .image,
            imageData: demoImage(size: NSSize(width: 720, height: 420), title: "Dashboard", accent: .systemPurple),
            app: "截屏", bundleID: "com.apple.screencaptureui", age: 260, name: "Dashboard concept", key: "wide-image")
        add(.color, text: "#7C5CFC", app: "Safari", bundleID: "com.apple.Safari", age: 360, key: "purple")
        add(.email, text: "design-team@example.com", app: "邮件", bundleID: "com.apple.mail", age: 480, key: "email")
        add(
            .text, text: "swift build -c release && ./scripts/build-app.sh release", app: "终端",
            bundleID: "com.apple.Terminal", age: 620, uses: 3, name: "Release command", key: "command")
        add(
            .link, text: "https://www.swift.org/documentation/", app: "Google Chrome",
            bundleID: "com.google.Chrome", age: 780, key: "swift-link")
        add(
            .image, imageData: demoImage(size: NSSize(width: 420, height: 720), title: "Mobile", accent: .systemBlue),
            app: "访达", bundleID: "com.apple.finder", age: 1_000, key: "tall-image")
        add(
            .text, text: "今天要完成：\n• 调整剪贴板缩略图\n• 检查明暗模式\n• 验证键盘操作", app: "提醒事项",
            bundleID: "com.apple.reminders", age: 1_400, key: "tasks")
        add(
            .file, files: [URL(fileURLWithPath: "/Applications/Safari.app")], app: "访达",
            bundleID: "com.apple.finder", age: 1_800, key: "single-file")
        add(.color, text: "#FF9F0A", app: "Safari", bundleID: "com.apple.Safari", age: 2_400, key: "orange")

        add(
            .text, text: "这是一段用于检查长文本截断效果的模拟内容。列表中应该只显示第一行，并在空间不足时自然显示省略号。",
            app: "ChatGPT", bundleID: "com.openai.codex", age: 90_000, key: "long-text")
        add(
            .image, imageData: demoImage(size: NSSize(width: 600, height: 600), title: "Square", accent: .systemPink),
            app: "预览", bundleID: "com.apple.Preview", age: 94_000, key: "square-image")
        add(
            .link, text: "https://github.com/example/cliplet", app: "Arc", bundleID: "company.thebrowser.Browser",
            age: 98_000, uses: 1, key: "repo-link")
        add(
            .file,
            files: [
                URL(fileURLWithPath: "/Users/Shared/Project-Brief.pdf"),
                URL(fileURLWithPath: "/Users/Shared/Research-Notes.md"),
                URL(fileURLWithPath: "/Users/Shared/Wireframes.fig"),
            ], app: "访达", bundleID: "com.apple.finder", age: 103_000, key: "multi-file")
        add(
            .text, text: "SELECT id, title, created_at\nFROM clipboard_items\nORDER BY created_at DESC\nLIMIT 50;",
            app: "DataGrip", bundleID: "com.jetbrains.datagrip", age: 109_000, name: "Recent items query", key: "sql")
        add(.email, text: "hello@cliplet.app", app: "邮件", bundleID: "com.apple.mail", age: 115_000, key: "second-email")

        add(
            .text, text: "Ship small improvements every day.", app: "备忘录", bundleID: "com.apple.Notes",
            age: 260_000, uses: 5, key: "ship-small")
        add(.color, text: "#34C759", app: "Safari", bundleID: "com.apple.Safari", age: 350_000, key: "green")
        add(
            .image,
            imageData: demoImage(size: NSSize(width: 1_000, height: 500), title: "Release 1.0", accent: .systemGreen),
            app: "Keynote", bundleID: "com.apple.iWork.Keynote", age: 440_000, name: "Release banner",
            key: "banner-image")
        add(
            .link, text: "https://support.apple.com/guide/mac-help/", app: "Safari", bundleID: "com.apple.Safari",
            age: 530_000, key: "support-link")
        add(
            .text, text: "键盘优先，鼠标友好，隐私默认。", app: "备忘录", bundleID: "com.apple.Notes",
            age: 620_000, pinned: true, uses: 12, name: "设计原则", key: "principles")
        add(
            .text, text: "Mock data only — no personal clipboard content was used.", app: "Cliplet",
            bundleID: "com.clipboardnative.macos", age: 710_000, key: "privacy-note")

        return result.sorted { $0.createdAt < $1.createdAt }
    }

    private static func stableUUID(_ key: String) -> UUID {
        let digest = ClipboardItem.hash(parts: [Data(key.utf8)])
        let raw = String(digest.prefix(32))
        let value =
            "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-4\(raw.dropFirst(13).prefix(3))-a\(raw.dropFirst(17).prefix(3))-\(raw.dropFirst(20).prefix(12))"
        return UUID(uuidString: value) ?? UUID()
    }

    private static func demoImage(size: NSSize, title: String, accent: NSColor) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        let inset = min(size.width, size.height) * 0.08
        let card = NSBezierPath(
            roundedRect: NSRect(
                x: inset, y: inset, width: size.width - inset * 2,
                height: size.height - inset * 2),
            xRadius: inset * 0.35, yRadius: inset * 0.35)
        accent.withAlphaComponent(0.18).setFill()
        card.fill()

        accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: inset * 1.55, y: size.height * 0.28,
                width: size.width * 0.12, height: size.height * 0.44),
            xRadius: inset * 0.2, yRadius: inset * 0.2
        ).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(size.width, size.height) * 0.11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        NSString(string: title).draw(
            at: NSPoint(x: size.width * 0.26, y: size.height * 0.44), withAttributes: attributes)
        image.unlockFocus()
        return image.tiffRepresentation
    }
}
