import Foundation

/// Prefer resources actually shipped in the app. SwiftPM's development fallback
/// is only used when running the standalone executable from its build directory.
enum AppResources {
    static var packagedBundle: Bundle? {
        guard let directory = Bundle.main.resourceURL else { return nil }
        return Bundle(url: directory.appendingPathComponent("Cliplet_ClipletKit.bundle"))
    }
    static let bundle: Bundle = packagedBundle ?? .module
}
