import Foundation

/// Supported languages for STT, TTS, and LLM responses.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// Display name
    var name: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .russian: return "Русский"
        }
    }

    /// Flag emoji
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .spanish: return "🇪🇸"
        case .russian: return "🇷🇺"
        }
    }

    /// Locale for SFSpeechRecognizer
    var sttLocale: String {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .russian: return "ru-RU"
        }
    }

    /// Language code for TTS voice lookup
    var ttsLanguage: String {
        sttLocale
    }

    /// Instruction for the LLM to respond in this language
    var llmInstruction: String {
        switch self {
        case .english: return "You MUST respond in English."
        case .spanish: return "DEBES responder en español. Siempre en español."
        case .russian: return "Ты ДОЛЖЕН отвечать на русском языке. Всегда на русском."
        }
    }

    /// Persist / restore
    static func saved() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: "appLanguage"),
              let lang = AppLanguage(rawValue: raw) else {
            return .english
        }
        return lang
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "appLanguage")
    }
}
