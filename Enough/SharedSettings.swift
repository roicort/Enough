//
//  SharedSettings.swift
//  Enough
//

import Foundation

enum SharedSettings {
    static let appGroupIdentifier = "group.xyz.unknowable.Enough"
    static let aiConfidenceThresholdKey = "aiConfidenceThreshold"
    static let appLanguageCodeKey = "appLanguageCode"
    static let showVerifiedAIC2PAKey = "showVerifiedAIC2PA"

    static let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard

    static var appLanguageCode: String {
        defaults.synchronize()
        let languageCode = defaults.string(forKey: appLanguageCodeKey) ?? "system"
        return ["en", "es"].contains(languageCode) ? languageCode : "system"
    }

    static func setAppLanguageCode(_ languageCode: String) {
        defaults.set(
            ["system", "en", "es"].contains(languageCode) ? languageCode : "system",
            forKey: appLanguageCodeKey
        )
        defaults.synchronize()
    }

    static var locale: Locale {
        locale(for: appLanguageCode)
    }

    static func locale(for languageCode: String) -> Locale {
        languageCode == "system"
            ? .autoupdatingCurrent
            : Locale(identifier: languageCode)
    }

    static var aiConfidenceThreshold: Double {
        defaults.synchronize()
        let threshold = defaults.object(forKey: aiConfidenceThresholdKey) as? Double ?? 0.65
        return min(max(threshold, 0.50), 0.95)
    }

    static func setAIConfidenceThreshold(_ threshold: Double) {
        defaults.set(
            min(max(threshold, 0.50), 0.95),
            forKey: aiConfidenceThresholdKey
        )
        defaults.synchronize()
    }

    static var showVerifiedAIC2PA: Bool {
        defaults.synchronize()
        return defaults.object(forKey: showVerifiedAIC2PAKey) as? Bool ?? true
    }

    static func setShowVerifiedAIC2PA(_ showVerifiedAIC2PA: Bool) {
        defaults.set(showVerifiedAIC2PA, forKey: showVerifiedAIC2PAKey)
        defaults.synchronize()
    }

}
