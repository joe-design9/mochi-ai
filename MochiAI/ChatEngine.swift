import Foundation

/// Values the chat needs to reach the configured provider.
struct EngineConfig {
    let key: String
    let baseURL: String
    let model: String
    let profile: UserProfile?
}

// MARK: - OpenAI-compatible chat client

/// POST {baseURL}/chat/completions with a Bearer key. Serves the Gemini
/// preset and every generic OpenAI-compatible provider. Always returns a
/// displayable string — a real reply or a friendly in-character note.
enum APIClient {
    static func send(history: [ChatMessage], config: EngineConfig) async -> String {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmedBase + "/chat/completions") else {
            return "Die API-Adresse in den Einstellungen sieht nicht gültig aus — prüf sie kurz in der Bibliothek, dann bin ich wieder voll da."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                if http.statusCode == 401 || http.statusCode == 403 {
                    return "Hmm, der Anbieter hat meinen Key abgelehnt (Fehler \(http.statusCode)). Prüf den Key in der Bibliothek unter „Einstellungen“ — oder bleib einfach im Demo-Modus, ich bin auch so für dich da."
                }
                return "Der Anbieter hat gerade mit Fehler \(http.statusCode) geantwortet. Versuch es gleich nochmal — oder prüf Adresse und Modell in den Einstellungen."
            }
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            if let content = decoded.choices.first?.message.content,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            return "Ich habe gerade eine leere Antwort bekommen — versuch es bitte einfach nochmal."
        } catch {
            return "Ich konnte den Anbieter gerade nicht erreichen. Prüf kurz deine Internetverbindung und die API-Adresse in den Einstellungen."
        }
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
