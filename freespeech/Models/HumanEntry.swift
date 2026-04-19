// Swift 5.0
//
//  HumanEntry.swift
//

import Foundation
import CoreGraphics

struct TargetLanguage: Identifiable, Hashable {
    let id: String  // BCP-47 locale identifier (e.g., "en-US")
    let name: String
    let flag: String

    static let supported: [TargetLanguage] = [
        TargetLanguage(id: "en-US", name: "English", flag: "🇺🇸"),
        TargetLanguage(id: "en-GB", name: "English (UK)", flag: "🇬🇧"),
        TargetLanguage(id: "es-ES", name: "Español", flag: "🇪🇸"),
        TargetLanguage(id: "fr-FR", name: "Français", flag: "🇫🇷"),
        TargetLanguage(id: "de-DE", name: "Deutsch", flag: "🇩🇪"),
        TargetLanguage(id: "it-IT", name: "Italiano", flag: "🇮🇹"),
        TargetLanguage(id: "pt-BR", name: "Português", flag: "🇧🇷"),
        TargetLanguage(id: "ja-JP", name: "日本語", flag: "🇯🇵"),
        TargetLanguage(id: "zh-CN", name: "中文", flag: "🇨🇳"),
        TargetLanguage(id: "ko-KR", name: "한국어", flag: "🇰🇷"),
        TargetLanguage(id: "ru-RU", name: "Русский", flag: "🇷🇺"),
        TargetLanguage(id: "ar-SA", name: "العربية", flag: "🇸🇦"),
        TargetLanguage(id: "hi-IN", name: "हिन्दी", flag: "🇮🇳"),
        TargetLanguage(id: "nl-NL", name: "Nederlands", flag: "🇳🇱"),
        TargetLanguage(id: "sv-SE", name: "Svenska", flag: "🇸🇪"),
    ]
}

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    let videoFilename: String
    var languageCode: String?  // BCP-47 locale of the recording language

    static func createVideoEntry(languageCode: String? = nil) -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)

        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[\(id)]-[\(dateString)].md",
            videoFilename: "[\(id)]-[\(dateString)].mov",
            languageCode: languageCode
        )
    }
}
