import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .system: return L10n.tr("Follow System")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .system: return preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        default: return rawValue
        }
    }
}

@MainActor
enum L10n {
    static var locale: Locale { Locale(identifier: AppSettings.shared.language.resolvedIdentifier()) }

    static func tr(_ key: String, language: AppLanguage? = nil) -> String {
        let identifier = (language ?? AppSettings.shared.language).resolvedIdentifier()
        return bundle(for: identifier).localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func bundle(for identifier: String) -> Bundle {
        guard let path = AppResources.bundle.path(forResource: identifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return AppResources.bundle }
        return bundle
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: arguments)
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }
}
