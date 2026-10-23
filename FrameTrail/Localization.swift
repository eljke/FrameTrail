import Foundation

enum L10n {
    static var language: String {
        UserDefaults.standard.string(forKey: "app.language")
            ?? (Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en")
    }

    static var locale: Locale { Locale(identifier: language == "ru" ? "ru_RU" : "en_US") }

    static func text(_ key: String, _ arguments: String...) -> String {
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments.map { $0 as CVarArg })
    }
}
