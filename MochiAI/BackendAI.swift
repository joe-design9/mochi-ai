import Foundation

/// Nova v3.0.0 — the backend AI client. In the normal build there is
/// NO user API key anymore: text chat runs through the `chat` Edge
/// Function on the existing Supabase project ("mochiai"), which
/// verifies that this install redeemed an invite code
/// (invite_codes.used_by_install = install_id) and only then calls
/// Gemini with the server-side GEMINI_API_KEY secret. Phone calls
/// fetch a short-lived Gemini Live ephemeral token from the
/// `live-token` function the same way, so the secret never ships in
/// the app and never touches the device.
///
/// Contract mirrors APIClient.send: `chatReply` always returns a
/// displayable string — the reply, or a friendly in-character note
/// for every failure mode (offline, not activated, server not
/// configured yet, HTTP error). The send queue can never jam on it.
///
/// QA builds (-QAProxyMock): both endpoints answer locally with a
/// canned stub — no network, no secret — so the UI flows (send flow,
/// call screen connect attempt) are testable in CI before the real
/// functions are deployed.
enum BackendAI {
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    #if QA
    /// True when launched with `-QAProxyMock` (QA configuration
    /// only — the flag does not exist in release builds).
    private static var qaMockEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-QAProxyMock")
    }
    #endif

    // MARK: Text chat

    /// Sends the conversation (same window rule as the direct API
    /// path: newest 12 turns, starting with a user turn) plus the
    /// rendered system prompt to the `chat` function and returns the
    /// model's reply text — or a German in-chat note on any failure.
    static func chatReply(history: [ChatMessage], profile: UserProfile?, installID: String) async -> String {
        #if QA
        if qaMockEnabled {
            try? await Task.sleep(nanoseconds: 700_000_000)
            return "Nova läuft — das ist eine Test-Antwort aus dem QA-Mock-Proxy. Der echte Server antwortet, sobald die Edge Functions deployed sind."
        }
        #endif
        let turns = proxyTurns(from: history)
        guard !turns.isEmpty else {
            return "Da ist etwas schiefgelaufen — die Nachricht war leer."
        }
        let body: [String: Any] = [
            "install_id": installID,
            "system_prompt": Persona.systemPrompt(profile: profile),
            "messages": turns,
        ]
        switch await postFunction("chat", body: body) {
        case .success(let object):
            if let reply = object["reply"] as? String,
               !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return reply
            }
            return "Der Server hat eine leere Antwort geschickt — versuch es einfach nochmal."
        case .failure(let note):
            return note
        }
    }

    /// Fetches a Gemini Live ephemeral token from the `live-token`
    /// function. Returns nil on any failure — the call controller
    /// then falls back to the speech pipeline, exactly like a failed
    /// direct Live setup.
    static func liveToken(installID: String) async -> String? {
        #if QA
        if qaMockEnabled {
            // A deliberately invalid token: the Live engine's setup
            // fails against it and the controller's fallback cascade
            // (pipeline mode) is what the QA run exercises.
            return "qa-mock-token"
        }
        #endif
        let result = await postFunction("live-token", body: ["install_id": installID])
        guard case .success(let object) = result,
              let token = object["token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    // MARK: Plumbing

    private enum FunctionResult {
        case success([String: Any])
        case failure(String) // displayable German note
    }

    private static func postFunction(_ name: String, body: [String: Any]) async -> FunctionResult {
        guard BackendConfig.isConfigured,
              let url = URL(string: BackendConfig.endpoint + "/functions/v1/" + name) else {
            return .failure("Der Nova-Server ist noch nicht eingerichtet. Versuch es später nochmal.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(BackendConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(BackendConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            return .failure("Keine Verbindung zum Nova-Server. Prüfe deine Internetverbindung und versuch es nochmal.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 200 {
            return .success(object)
        }
        // Structured error from the function: {"error": "<code>",
        // "message": "<german text>"} — prefer its message.
        let code = object["error"] as? String ?? ""
        let message = object["message"] as? String
        switch code {
        case "not_activated":
            return .failure("Diese Installation ist noch nicht aktiviert. Nova wird persönlich weitergegeben — ein Invite-Code schaltet den Zugang frei.")
        case "server_not_configured":
            return .failure("Der Nova-Server ist noch nicht fertig eingerichtet (API-Key fehlt). Versuch es später nochmal.")
        default:
            if let message, !message.isEmpty {
                return .failure(message)
            }
            return .failure("Der Nova-Server meldet einen Fehler (HTTP \(status)). Versuch es später nochmal.")
        }
    }

    /// The proxy payload window — identical trimming to the direct
    /// Gemini path so both transports see the same conversation.
    private static func proxyTurns(from history: [ChatMessage]) -> [[String: String]] {
        var turns: [[String: String]] = []
        for message in history.suffix(12) {
            turns.append([
                "role": message.role == .user ? "user" : "model",
                "text": message.text,
            ])
        }
        while let first = turns.first, first["role"] != "user" {
            turns.removeFirst()
        }
        if turns.isEmpty, let lastUser = history.last(where: { $0.role == .user }) {
            turns = [["role": "user", "text": lastUser.text]]
        }
        return turns
    }
}
