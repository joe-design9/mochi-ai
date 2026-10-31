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

/// Typed failure for `Result` (a bare `String` cannot be a `Failure` type).
struct EngineFailure: Error {
    let message: String
    /// True only for `URLError.timedOut` — HTTPHelper retries those once.
    var isTimeout: Bool = false
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
    static func testConnection(config: EngineConfig) async -> Result<String, EngineFailure> {
        let result: ProviderResult
        switch config.provider {
        case .gemini:
            result = await GeminiAPI.test(config: config)
        case .openAICompatible:
            result = await OpenAIAPI.test(config: config)
        }
        switch result {
        case .success(let text): return .success(text)
        case .failure(let message): return .failure(EngineFailure(message: message))
        }
    }
}

// MARK: - Shared helpers

private enum HTTPHelper {
    /// Performs a JSON POST and hands back (data, statusCode) or a short
    /// human-readable transport error.
    ///
    /// Timeout/retry are PER-CALL policy (v2.1.0 — no more endless
    /// hangs): chat sends pass 60s and no timeout retry (a failed send
    /// lands as a clear note fast; the user can resend), the connection
    /// test passes 30s and no retry (it must tell the truth quickly).
    /// Real API answers (any HTTP status) are never retried here — the
    /// Gemini HTTP-error fallback lives one level up, in GeminiAPI.
    static func postJSON(url: URL, headers: [String: String], body: [String: Any],
                         timeout: TimeInterval, retryOnTimeout: Bool = false) async -> Result<(Data, Int), EngineFailure> {
        let result = await attempt(url: url, headers: headers, body: body, timeout: timeout)
        if retryOnTimeout, case .failure(let failure) = result, failure.isTimeout {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return await attempt(url: url, headers: headers, body: body, timeout: timeout)
        }
        return result
    }

    private static func attempt(url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval) async -> Result<(Data, Int), EngineFailure> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return .success((data, status))
        } catch let urlError as URLError where urlError.code == .timedOut {
            return .failure(EngineFailure(
                message: "Verbindung fehlgeschlagen: \(urlError.localizedDescription)",
                isTimeout: true
            ))
        } catch {
            return .failure(EngineFailure(message: "Verbindung fehlgeschlagen: \(error.localizedDescription)"))
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

// MARK: - Gemini (Interactions API primary, generateContent fallback)

/// Gemini 3.x models are routed via Google's Interactions API — on the
/// legacy generateContent path they hang (thinking on by default, free
/// tier). Primary transport is therefore POST {base}/interactions; if
/// that returns an HTTP error status, the SAME request gets one second
/// chance via the legacy generateContent endpoint (with thinking set
/// low there too). Transport failures (incl. timeouts) never fall back.
/// Both bodies pin the thinking level to "low" for fast answers.
/// Chat timeout: 60s. Connection-test timeout: 30s. Neither retries a
/// timeout (per-call policy in HTTPHelper).
private enum GeminiAPI {
    /// Timeout for real chat sends.
    private static let chatTimeout: TimeInterval = 60
    /// Timeout for the "Verbindung testen" self-check.
    private static let testTimeout: TimeInterval = 30

    static func chat(history: [ChatMessage], config: EngineConfig) async -> ProviderResult {
        let systemPrompt = Persona.systemPrompt(profile: config.profile)
        let interactionsBody: [String: Any] = [
            "model": config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "store": false,
            "input": interactionTurns(from: history),
            "system_instruction": systemPrompt,
            "generation_config": ["thinking_level": "low", "max_output_tokens": 1024],
        ]
        let legacyBody: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": legacyContents(from: history),
            "generationConfig": [
                "maxOutputTokens": 1024,
                "thinkingConfig": ["thinkingLevel": "low"],
            ],
        ]
        return await performChain(
            config: config,
            interactionsBody: interactionsBody,
            legacyBody: legacyBody,
            timeout: chatTimeout
        )
    }

    static func test(config: EngineConfig) async -> ProviderResult {
        let systemPrompt = Persona.systemPrompt(profile: config.profile)
        let interactionsBody: [String: Any] = [
            "model": config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "store": false,
            "input": [["role": "user", "content": [["type": "text", "text": "Antworte mit: OK"]]]],
            "system_instruction": systemPrompt,
            "generation_config": ["thinking_level": "low", "max_output_tokens": 256],
        ]
        let legacyBody: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": "Antworte mit: OK"]]]],
            "generationConfig": [
                "maxOutputTokens": 256,
                "thinkingConfig": ["thinkingLevel": "low"],
            ],
        ]
        // The test runs the same transport chain as chat (Interactions
        // first, legacy fallback on HTTP errors) — just faster.
        return await performChain(
            config: config,
            interactionsBody: interactionsBody,
            legacyBody: legacyBody,
            timeout: testTimeout
        )
    }

    // MARK: Transport chain

    /// Interactions first. HTTP 200 → parse the Interactions reply.
    /// Any other HTTP status → one legacy generateContent attempt.
    /// Transport failure → surfaced immediately (no fallback, no retry).
    private static func performChain(config: EngineConfig,
                                     interactionsBody: [String: Any],
                                     legacyBody: [String: Any],
                                     timeout: TimeInterval) async -> ProviderResult {
        guard let url = interactionsURL(config: config) else {
            return .failure("Die API-Adresse in den Einstellungen sieht nicht gültig aus.")
        }
        let outcome = await HTTPHelper.postJSON(
            url: url,
            headers: ["x-goog-api-key": config.key],
            body: interactionsBody,
            timeout: timeout
        )
        switch outcome {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let (data, status)):
            guard status == 200 else {
                return await performLegacy(config: config, body: legacyBody, timeout: timeout)
            }
            guard let rawText = parseInteractionsText(from: data) else {
                return .failure("Unerwartetes Antwortformat von Google.")
            }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return .failure("Google hat eine leere Antwort geschickt — versuch es einfach nochmal.")
            }
            return .success(text)
        }
    }

    /// The legacy generateContent call (fallback chance, and the shape
    /// the pre-2.1.0 app used as its only transport).
    private static func performLegacy(config: EngineConfig, body: [String: Any], timeout: TimeInterval) async -> ProviderResult {
        guard let url = legacyURL(config: config) else {
            return .failure("Die API-Adresse in den Einstellungen sieht nicht gültig aus.")
        }
        let outcome = await HTTPHelper.postJSON(
            url: url,
            headers: ["x-goog-api-key": config.key],
            body: body,
            timeout: timeout
        )
        switch outcome {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let (data, status)):
            guard status == 200 else {
                return .failure(HTTPHelper.errorMessage(from: data, status: status))
            }
            guard let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
                return .failure("Unerwartetes Antwortformat von Google.")
            }
            let parts: [GeminiResponse.Candidate.Content.Part] = decoded.candidates?.first?.content?.parts ?? []
            let text = parts
                .compactMap { $0.text }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return .failure("Google hat eine leere Antwort geschickt — versuch es einfach nochmal.")
            }
            return .success(text)
        }
    }

    // MARK: Request shapes

    /// Interactions-API turns: {"role": "user"|"model", "content":
    /// [{"type": "text", "text": …}]} — newest 12 messages, and the
    /// conversation must start with a user turn.
    private static func interactionTurns(from history: [ChatMessage]) -> [[String: Any]] {
        var turns: [[String: Any]] = []
        for message in history.suffix(12) {
            turns.append([
                "role": message.role == .user ? "user" : "model",
                "content": [["type": "text", "text": message.text]],
            ])
        }
        while let first = turns.first, (first["role"] as? String) != "user" {
            turns.removeFirst()
        }
        if turns.isEmpty, let lastUser = history.last(where: { $0.role == .user }) {
            turns = [["role": "user", "content": [["type": "text", "text": lastUser.text]]]]
        }
        return turns
    }

    /// Legacy generateContent contents: same window/trimming, "parts"
    /// shape instead of "content".
    private static func legacyContents(from history: [ChatMessage]) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        for message in history.suffix(12) {
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": message.text]],
            ])
        }
        while let first = contents.first, (first["role"] as? String) != "user" {
            contents.removeFirst()
        }
        if contents.isEmpty, let lastUser = history.last(where: { $0.role == .user }) {
            contents = [["role": "user", "parts": [["text": lastUser.text]]]]
        }
        return contents
    }

    // MARK: Response parsing (liberal — explicit typed locals only;
    // the v1.1.0 Decodable key-path chain bug is the cautionary tale)

    /// Extracts the reply text from an Interactions response. Accepts,
    /// in order: (a) a top-level "output_text" string; (b) the "steps"
    /// array's "model_output" step and its content text items; (c) an
    /// "output" array of content items. Returns nil when none matches.
    private static func parseInteractionsText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return nil
        }

        // (a) Direct output_text.
        if let direct = root["output_text"] as? String, !direct.isEmpty {
            return direct
        }

        // Joins the "text" values of a content-item array.
        func textFromContentItems(_ value: Any?) -> String {
            guard let items = value as? [[String: Any]] else { return "" }
            var collected = ""
            for item in items {
                if let text = item["text"] as? String {
                    collected += text
                }
            }
            return collected
        }

        // (b) Steps → the model_output step.
        if let steps = root["steps"] as? [[String: Any]] {
            for step in steps {
                guard (step["type"] as? String) == "model_output" else { continue }
                if let stepText = step["text"] as? String, !stepText.isEmpty {
                    return stepText
                }
                let contentText = textFromContentItems(step["content"])
                if !contentText.isEmpty {
                    return contentText
                }
            }
        }

        // (c) Output array of content items.
        if let output = root["output"] as? [[String: Any]] {
            var collected = ""
            for item in output {
                if let text = item["text"] as? String {
                    collected += text
                }
                collected += textFromContentItems(item["content"])
            }
            if !collected.isEmpty {
                return collected
            }
        }

        return nil
    }

    // MARK: URLs

    /// The normalized API base, guaranteed to end in "/v1beta": the
    /// stored default already includes it, a bare host (as in Google's
    /// own examples) gets it appended — never doubled. Bases saved by
    /// v1.0.0 could still end in "/openai" (the old compatible
    /// endpoint) — that suffix is stripped like before.
    private static func apiBase(config: EngineConfig) -> String {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.hasSuffix("/openai") {
            base = String(base.dropLast("/openai".count))
            while base.hasSuffix("/") { base = String(base.dropLast()) }
        }
        if base.isEmpty {
            base = APIProvider.gemini.defaultBaseURL
        }
        if !base.hasSuffix("/v1beta") {
            base += "/v1beta"
        }
        return base
    }

    private static func interactionsURL(config: EngineConfig) -> URL? {
        URL(string: apiBase(config: config) + "/interactions")
    }

    private static func legacyURL(config: EngineConfig) -> URL? {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        return URL(string: "\(apiBase(config: config))/models/\(encodedModel):generateContent")
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
        return await perform(config: config, body: body, timeout: 60)
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
        return await perform(config: config, body: body, timeout: 30)
    }

    private static func perform(config: EngineConfig, body: [String: Any], timeout: TimeInterval) async -> ProviderResult {
        guard let url = endpointURL(config: config) else {
            return .failure("Die API-Adresse in den Einstellungen sieht nicht gültig aus.")
        }
        let outcome = await HTTPHelper.postJSON(
            url: url,
            headers: ["Authorization": "Bearer \(config.key)"],
            body: body,
            timeout: timeout
        )
        switch outcome {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let (data, status)):
            guard status == 200 else {
                return .failure(HTTPHelper.errorMessage(from: data, status: status))
            }
            guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
                return .failure("Unerwartetes Antwortformat vom Anbieter.")
            }
            let rawContent: String = decoded.choices.first?.message.content ?? ""
            let text = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
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
