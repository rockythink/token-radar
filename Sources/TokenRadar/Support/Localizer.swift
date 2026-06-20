import Foundation
import TokenRadarCore

enum L10n {
    private static var cache: [String: [String: String]] = [:]

    static func text(_ key: String, language: AppLanguage) -> String {
        let code = resolvedLanguageCode(for: language)
        if let value = table(for: code)[key] {
            return value
        }
        if code != "en", let fallback = table(for: "en")[key] {
            return fallback
        }
        return key
    }

    private static func resolvedLanguageCode(for language: AppLanguage) -> String {
        if let code = language.localizationCode {
            return normalized(code)
        }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.contains("hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") || preferred.hasPrefix("zh-mo") {
            return "zh-hant"
        }
        if preferred.hasPrefix("zh") {
            return "zh-hans"
        }
        return "en"
    }

    private static func table(for code: String) -> [String: String] {
        let code = normalized(code)
        if let cached = cache[code] {
            return cached
        }

        let candidates = [
            code,
            code.replacingOccurrences(of: "-", with: "_"),
            code.lowercased()
        ]

        for candidate in candidates {
            if let url = Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: "\(candidate).lproj"
            ),
               let dictionary = NSDictionary(contentsOf: url) as? [String: String] {
                cache[code] = dictionary
                return dictionary
            }
        }

        cache[code] = [:]
        return [:]
    }

    private static func normalized(_ code: String) -> String {
        code.lowercased()
    }
}
