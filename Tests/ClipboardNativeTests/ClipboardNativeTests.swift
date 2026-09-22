import XCTest
@testable import ClipboardNative

final class ClipboardNativeTests: XCTestCase {
    func testContentClassification() {
        XCTAssertEqual("https://example.com/path".detectedClipboardKind, .link)
        XCTAssertEqual("hello@example.com".detectedClipboardKind, .email)
        XCTAssertEqual("#ff006e".detectedClipboardKind, .color)
        XCTAssertEqual("hello world".detectedClipboardKind, .text)
    }

    func testNormalization() {
        XCTAssertEqual("  hello\r\nworld  ".normalizedForClipboard, "hello\nworld")
    }

    func testHashIsStableAndSensitiveToContent() {
        let one = ClipboardItem.hash(parts: [Data("one".utf8)])
        XCTAssertEqual(one, ClipboardItem.hash(parts: [Data("one".utf8)]))
        XCTAssertNotEqual(one, ClipboardItem.hash(parts: [Data("two".utf8)]))
    }

    func testDefaultGlobalHotkeyIsOptionV() {
        let shortcut = GlobalHotkey.defaultValue
        XCTAssertEqual(shortcut.displayString, "⌥V")
        XCTAssertEqual(shortcut.keyEquivalent, "v")
        XCTAssertTrue(shortcut.appKitModifiers.contains(.option))
        XCTAssertEqual(shortcut.appKitModifiers.intersection([.command, .control, .shift]), [])
    }
}

@MainActor
final class LocalizationTests: XCTestCase {
    func testLanguageResolutionAndFallback() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: []), "en")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "en")
        XCTAssertEqual(L10n.tr("Copy to Clipboard", language: .simplifiedChinese), "复制到剪贴板")
        XCTAssertEqual(L10n.tr("Copy to Clipboard", language: .english), "Copy to Clipboard")
        XCTAssertEqual(L10n.tr("missing.key", language: .simplifiedChinese), "missing.key")
    }

    func testCatalogsHaveMatchingKeysAndFormatArguments() throws {
        func catalog(_ identifier: String) throws -> [String: String] {
            let url = try XCTUnwrap(
                L10n.bundle(for: identifier).url(forResource: "Localizable", withExtension: "strings"))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try catalog("en")
        let chinese = try catalog("zh-Hans")
        XCTAssertGreaterThan(english.count, 100)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: "%[@d]")
        func arguments(_ value: String) -> [String] {
            pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                String(value[Range($0.range, in: value)!])
            }
        }
        for (key, value) in english {
            let translation = try XCTUnwrap(chinese[key])
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertEqual(arguments(value), arguments(translation), key)
        }
    }
}
