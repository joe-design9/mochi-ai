import Foundation

/// Selectable API providers. Gemini and the generic provider both speak the
/// OpenAI-compatible chat-completions protocol (Bearer key, /chat/completions).
enum APIProvider: String, CaseIterable, Identifiable {
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini (Google) — gratis Key"
        case .openAICompatible: return "OpenAI-kompatibel"
        }
    }

    /// Short label shown in the chat header, chip and settings caption.
    var engineLabel: String {
        switch self {
        case .gemini: return "Gemini API"
        case .openAICompatible: return "OpenAI-kompatibel"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .openAICompatible: return "gpt-4o-mini"
        }
    }

    var baseURLPlaceholder: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .openAICompatible: return "z. B. https://api.openai.com/v1, https://api.groq.com/openai/v1, https://openrouter.ai/api/v1"
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .gemini: return "z. B. gemini-2.5-flash"
        case .openAICompatible: return "z. B. gpt-4o-mini, llama-3.3-70b-versatile, openai/gpt-4o-mini"
        }
    }

    var keyHint: String {
        switch self {
        case .gemini:
            return "Gratis-Key: aistudio.google.com → Get API key — nur Google-Login, keine Kreditkarte nötig."
        case .openAICompatible:
            return "Funktioniert mit jedem OpenAI-kompatiblen Anbieter (z. B. OpenAI, Groq, OpenRouter). Adresse und Modell unten anpassen."
        }
    }
}
