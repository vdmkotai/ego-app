import Foundation

/// Uses the native iOS per-app language, including system-owned dialogs and extensions.
enum EgoLocale {
    static var language: String { Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en" }
    static var current: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        return Locale(components: components)
    }
    static var weekdaySymbols: [String] {
        let formatter = DateFormatter(); formatter.locale = current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols!
        return Array(symbols.dropFirst()) + [symbols[0]]
    }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, locale: EgoLocale.current, arguments: arguments)
}

extension Date {
    func egoFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(EgoLocale.current))
    }
}
