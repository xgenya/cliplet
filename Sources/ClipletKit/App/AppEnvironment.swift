import Foundation

/// Build identity is decided at compile time. A release invocation cannot opt into
/// development paths (or vice versa) by inheriting a shell environment variable.
enum AppEnvironment: Sendable {
    case development, production

    static var current: AppEnvironment {
        #if DEBUG
            return .development
        #else
            return .production
        #endif
    }

    var bundleIdentifier: String {
        self == .development ? "com.clipboardnative.macos.dev" : "com.clipboardnative.macos"
    }

    var dataDirectoryName: String {
        self == .development ? "Cliplet-Development" : "Cliplet"
    }

    var legacyDataDirectoryName: String {
        self == .development ? "ClipboardNative-Development" : "ClipboardNative"
    }

    var defaults: UserDefaults {
        // The application's own domain is already the standard store. Foundation
        // can reject an explicit suite with the current bundle identifier.
        if Bundle.main.bundleIdentifier == bundleIdentifier { return .standard }
        return UserDefaults(suiteName: bundleIdentifier) ?? .standard
    }
}
