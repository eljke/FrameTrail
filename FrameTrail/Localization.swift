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

    static func error(_ error: Error) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .cancelled: return text("Запрос отменён.")
            case .timedOut: return text("Сервер не ответил вовремя. Попробуй ещё раз.")
            default: return text("Нет соединения с сервером. Проверь интернет и попробуй снова.")
            }
        }
        if error is DecodingError { return text("Не удалось прочитать данные. Попробуй ещё раз или проверь формат файла.") }
        if let file = error as? CocoaError {
            switch file.code {
            case .fileReadTooLarge: return text("Файл слишком большой.")
            case .fileReadNoPermission, .fileWriteNoPermission: return text("Нет доступа к файлу. Выбери его заново.")
            default: break
            }
        }
        return error.localizedDescription
    }
}
