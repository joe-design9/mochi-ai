import Foundation

/// Values the chat needs to reach the configured provider.
struct EngineConfig {
    let provider: APIProvider
    let key: String
    let baseURL: String
    let model: String
    let profile: UserProfile?
}

/// Outcome of a raw provider call: the reply text, or the provider's own
/// error message (parsed from its error JSON — never a raw stack trace).
private enum ProviderResult {
    case success(String)
    case failure(String)
}

// MARK: - Public API

enum APIClient {
    /// Chat entry point. Always returns a displayable string — the provider
    /// reply, or a friendly in-character note that quotes the provider's
    /// error message when one is available.
    static func send(history: [ChatMessage], config: EngineConfig) async -> String {
        let result: ProviderResult
        switch config.provider {
        case .gemini:
            result = await GeminiAPI.chat(history: history, config: config)
        case .openAICompatible:
            result = await OpenAIAPI.chat(history: history, config: config)
        }

        switch result {
        case .success(let text):
            return text
        case .failure(let providerMessage):
            switch config.provider {
            case .gemini:
                return "Da klemmt gerade was bei Google: „\(providerMessage)“ — prüf am besten Key und Modell in der Bibliothek unter „Einstellungen“. Dort gibt es jetzt auch einen „Verbindung testen“-Knopf, der dir genau zeigt, was Google antwortet."
            case .openAICompatible:
                return "Der Anbieter meldet: „\(providerMessage)“ — prüf Key, Adresse und Modell in der Bibliothek unter „Einstellungen“. Mit dem „Verbindung testen“-Knopf siehst du die Antwort des Anbieters direkt."
            }
        }
    }

    /// Minimal self-diagnosis request ("Antworte mit: OK") with the given
    /// settings. Returns the provider's reply on success, or the provider's
    /// error message (verbatim) / a short transport note on failure.
    static func testConnection(config: EngineConfig) async -> Result<String, String> {
        let result: ProviderResult
        switch config.provider {
        case .gemini:
            result = await GeminiAPI.test(config: config)
        case .openAICompatible:
            result = await OpenAIAPI.test(config: config)
        }
        switch result {
        case .success(let text): return .success(text)
        case .failure(let message): return .failure(message)
        }
    }
}

// MARK: - Shared helpers

private enum HTTPHelper {
    /// Performs a JSON POST and hands back (data, statusCode) or a short
    /// human-readable transport error.
    static func postJSON(url: URL, headers: [String: String], body: [String: Any]) async -> Result<(Data, Int), String> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return .success((data, status))
        } catch {
            return .failure("Verbindung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Extracts `error.message` (the shape both Google and OpenAI-style APIs
    /// use). Falls back to a status-code note when the body has none.
    static func errorMessage(from data: Data, status: Int) -> String {
        if let decoded = try? JSONDecoder().decode(ProviderErrorResponse.self, from: data),
           let message = decoded.error.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "HTTP-Fehler \(status) (keine Fehlermeldung vom Anbieter)"
    }
}

private struct ProviderErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let message: String?
    }

    let error: ErrorBody
}

// MARK: - Gemini (native REST API)

/// POST {base}/models/{model}:generateContent with an `x-goog-api-key`
/// header — Google's native API (the OpenAI-compatible endpoint proved
/// unreliable, hence the switch).
private enum GeminiAPI {
    static func chat(history: [ChatMessage], config: EngineConfig) async -> ProviderResult {
        var contents: [[String: Any]] = []
        for message in history.suffix(12) {
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": message.text]],
            ])
        }
        // Gemini conversations must start with a user turn.
        while let first = contents.first, (first["role"] as? String) != "user" {
            contents.removeFirst()
        }
        if contents.isEmpty, let lastUser = history.last(where: { $0.role == .user }) {
            contents = [["role": "user", "parts": [["text": lastUser.text]]]]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": Persona.systemPrompt(profile: config.profile)]]],
            "contents": contents,
            "generationConfig": ["maxOutputTokens": 1024],
        ]
        return await perform(config: config, body: body)
    }

    static func test(config: EngineConfig) async -> ProviderResult {
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": Persona.systemPrompt(profile: config.profile)]]],
            "contents": [["role": "user", "parts": [["text": "Antworte mit: OK"]]]],
            "generationConfig": ["maxOutputTokens": 256],
        ]
        return await perform(config: config, body: body)
    }

    private static func perform(config: EngineConfig, body: [String: Any]) async -> ProviderResult {
        guard let url = endpointURL(config: config) else {
            return .failure("Die API-Adresse in den Einstellungen sieht nicht gültig aus.")
        }
        let outcome = await HTTPHelper.postJSON(
            url: url,
            headers: ["x-goog-api-key": config.key],
            body: body
        )
        switch outcome {
        case .failure(let message):
            return .failure(message)
        case .success(let (data, status)):
            guard status == 200 else {
                return .failure(HTTPHelper.errorMessage(from: data, status: status))
            }
            guard let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
                return .failure("Unerwartetes Antwortformat von Google.")
            }
            let text = (decoded.candidates?.first?.content?.parts ?? [])
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return .failure("Google hat eine leere Antwort geschickt — versuch es einfach nochmal.")
            }
            return .success(text)
        }
    }

    /// Builds the generateContent URL. Bases saved by v1.0.0 could still end
    /// in "/openai/" (the old compatible endpoint) — strip that suffix so
    /// existing installs keep working without touching their settings.
    private static func endpointURL(config: EngineConfig) -> URL? {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.hasSuffix("/openai") {
            base = String(base.dropLast("/openai".count))
            while base.hasSuffix("/") { base = String(base.dropLast()) }
        }
        if base.isEmpty {
            base = APIProvider.gemini.defaultBaseURL
        }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        return URL(string: "\(base)/models/\(encodedModel):generateContent")
    }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]?
        }

        let content: Content?
    }

    let candidates: [Candidate]?
}

// MARK: - OpenAI-compatible (chat completions)

/// POST {base}/chat/completions with a Bearer key (OpenAI, Groq,
/// OpenRouter, …).
private enum OpenAIAPI {
    static func chat(history: [ChatMessage], config: EngineConfig) async -> ProviderResult {
        var messages: [[String: String]] = [
            ["role": "system", "content": Persona.systemPrompt(profile: config.profile)],
        ]
        for message in history.suffix(12) {
            messages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text,
            ])
        }
        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "max_tokens": 1024,
        ]
        return await perform(config: config, body: body)
    }

    static func test(config: EngineConfig) async -> ProviderResult {
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": Persona.systemPrompt(profile: config.profile)],
                ["role": "user", "content": "Antworte mit: OK"],
            ],
            "max_tokens": 256,
        ]
        return await perform(config: config, body: body)
    }

    private static func perform(config: EngineConfig, body: [String: Any]) async -> ProviderResult {
        guard let url = endpointURL(config: config) else {
            return .failure("Die API-Adresse in den Einstellungen sieht nicht gültig aus.")
        }
        let outcome = await HTTPHelper.postJSON(
            url: url,
            headers: ["Authorization": "Bearer \(config.key)"],
            body: body
        )
        switch outcome {
        case .failure(let message):
            return .failure(message)
        case .success(let (data, status)):
            guard status == 200 else {
                return .failure(HTTPHelper.errorMessage(from: data, status: status))
            }
            guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
                return .failure("Unerwartetes Antwortformat vom Anbieter.")
            }
            let text = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                return .failure("Der Anbieter hat eine leere Antwort geschickt — versuch es einfach nochmal.")
            }
            return .success(text)
        }
    }

    /// Joins base + "/chat/completions" without ever producing double slashes.
    private static func endpointURL(config: EngineConfig) -> URL? {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.isEmpty {
            base = APIProvider.openAICompatible.defaultBaseURL
        }
        return URL(string: base + "/chat/completions")
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
