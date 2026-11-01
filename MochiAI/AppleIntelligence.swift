import Foundation
import FoundationModels

// MARK: - Engine mode

/// The two ways Muse can answer: a cloud provider via the user's own
/// API key, or Apple's on-device model (FoundationModels) — no key,
/// no network. Persisted in UserDefaults by the store.
enum EngineMode: String, CaseIterable, Identifiable {
    case apiKey
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apiKey:
            // v3.0.0: in the normal build this mode IS the Nova Cloud
            // proxy (no user key exists there); only the admin build
            // still speaks of an API key.
            #if ADMIN_BUILD
            return "API-Key"
            #else
            return "Nova Cloud"
            #endif
        case .appleIntelligence: return "Apple KI"
        }
    }
}

// MARK: - Availability

/// Plain-language snapshot of `SystemLanguageModel.default.availability`.
enum AppleAvailability: Equatable {
    case available
    case notEnabled      // Apple Intelligence is off in system settings
    case notEligible     // device/region not eligible
    case modelNotReady   // model still downloading / preparing
    case unknown

    var isAvailable: Bool { self == .available }

    /// Short German status for the settings row.
    var statusText: String {
        switch self {
        case .available: return "Verfügbar auf diesem iPhone"
        case .notEnabled: return "Apple Intelligence ist auf diesem iPhone nicht aktiviert"
        case .notEligible: return "Dieses iPhone ist für Apple Intelligence nicht freigegeben"
        case .modelNotReady: return "Das Modell wird noch vorbereitet (Download läuft)"
        case .unknown: return "Apple Intelligence ist gerade nicht verfügbar"
        }
    }

    /// Longer German reason used in the in-chat fallback note.
    var reasonText: String {
        switch self {
        case .available: return ""
        case .notEnabled:
            return "Aktiviere Apple Intelligence in den iPhone-Einstellungen (Einstellungen → Apple Intelligence & Siri), dann läuft der Chat komplett lokal."
        case .notEligible:
            return "Dieses Gerät oder diese Region ist für Apple Intelligence nicht freigegeben."
        case .modelNotReady:
            return "Das Sprachmodell wird noch heruntergeladen bzw. vorbereitet — versuch es in ein paar Minuten wieder."
        case .unknown:
            return "Der genaue Grund steht gerade nicht fest — prüf die Apple-Intelligence-Einstellungen deines iPhones."
        }
    }

    static var current: AppleAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .notEligible
            case .appleIntelligenceNotEnabled:
                return .notEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unknown
            }
        @unknown default:
            return .unknown
        }
    }
}

// MARK: - On-device engine

/// Apple-KI chat engine on top of FoundationModels.
///
/// One `LanguageModelSession` per conversation (instructions = the Muse
/// persona built from the profile), kept for the app's lifetime so the
/// on-device model remembers the thread. When a session is created for a
/// conversation that already has history (app restart, conversation
/// re-opened), the first prompt carries a compact preamble with the last
/// exchanges. If the model reports an exceeded context window, the
/// session is rebuilt with that preamble and the request retried once.
/// Every failure is returned as a friendly in-chat note — never a throw —
/// so the store's send queue can never jam on this engine.
@MainActor
final class AppleIntelligenceEngine {
    private var sessions: [UUID: LanguageModelSession] = [:]
    /// Conversations whose session has already exchanged at least one
    /// turn (no preamble needed anymore).
    private var warmedConversations: Set<UUID> = []

    /// Drops the session of a deleted conversation.
    func dropSession(conversationID: UUID) {
        sessions[conversationID] = nil
        warmedConversations.remove(conversationID)
    }

    /// Drops all sessions (e.g. profile reset — instructions change).
    func dropAllSessions() {
        sessions.removeAll()
        warmedConversations.removeAll()
    }

    /// Warms up a conversation's session ahead of its first question
    /// (the on-device model loads/compiles in the background), so the
    /// first real answer starts faster. Called when the chat appears in
    /// Apple-KI mode and on conversation switches. No-op when Apple
    /// Intelligence is not available on this device.
    func prewarm(conversationID: UUID, profile: UserProfile?) {
        guard AppleAvailability.current.isAvailable else { return }
        let activeSession = session(for: conversationID, profile: profile)
        activeSession.prewarm()
    }

    /// Answers the latest user message of a conversation.
    /// - Parameters:
    ///   - history: the conversation INCLUDING the latest user message
    ///     as its last element.
    func respond(conversationID: UUID,
                 history: [ChatMessage],
                 latestText: String,
                 profile: UserProfile?) async -> String {
        let availability = AppleAvailability.current
        guard availability.isAvailable else {
            return "Apple KI ist auf diesem iPhone gerade nicht verfügbar. \(availability.reasonText) Alternativ kannst du in der Bibliothek unter „KI-Einstellungen“ in den API-Key-Modus wechseln."
        }

        let session = session(for: conversationID, profile: profile)
        let needsPreamble = !warmedConversations.contains(conversationID) && history.count > 1
        let prompt = needsPreamble
            ? Self.preamble(history: history, latestText: latestText)
            : latestText

        do {
            let text = try await ask(session, prompt: prompt)
            warmedConversations.insert(conversationID)
            return text
        } catch let error as LanguageModelSession.GenerationError
                    where Self.isContextOverflow(error) {
            // Context window full: rebuild the session from a compact
            // preamble and retry exactly once.
            dropSession(conversationID: conversationID)
            let fresh = self.session(for: conversationID, profile: profile)
            do {
                let text = try await ask(
                    fresh,
                    prompt: Self.preamble(history: history, latestText: latestText)
                )
                warmedConversations.insert(conversationID)
                return text
            } catch {
                return Self.friendlyNote(for: error)
            }
        } catch {
            return Self.friendlyNote(for: error)
        }
    }

    // MARK: Session handling

    private func session(for conversationID: UUID, profile: UserProfile?) -> LanguageModelSession {
        if let existing = sessions[conversationID] {
            return existing
        }
        let created = LanguageModelSession(
            instructions: "\(Persona.systemPrompt(profile: profile))"
        )
        sessions[conversationID] = created
        return created
    }

    private func ask(_ session: LanguageModelSession, prompt: String) async throws -> String {
        let response = try await session.respond(to: "\(prompt)")
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "Apple KI hat gerade keine Antwort parat — versuch es einfach nochmal."
        }
        return text
    }

    /// Compact context for a fresh session: the last few exchanges as
    /// plain text, then the new message.
    private static func preamble(history: [ChatMessage], latestText: String) -> String {
        let prior = history.dropLast().suffix(6)
        guard !prior.isEmpty else { return latestText }
        var lines = ["So lief diese Unterhaltung bisher:"]
        for message in prior {
            lines.append("\(message.role == .user ? "Nutzer" : "Nova"): \(message.text)")
        }
        lines.append("")
        lines.append("Neue Nachricht des Nutzers: \(latestText)")
        return lines.joined(separator: "\n")
    }

    // MARK: Errors

    private static func isContextOverflow(_ error: LanguageModelSession.GenerationError) -> Bool {
        if case .exceededContextWindowSize = error { return true }
        return false
    }

    /// Maps any engine error to a calm, in-character chat note.
    private static func friendlyNote(for error: Error) -> String {
        if let generationError = error as? LanguageModelSession.GenerationError {
            if case .guardrailViolation = generationError {
                return "Apple KI hat diese Anfrage aus Sicherheitsgründen abgelehnt (Schutzregeln des Geräts). Formulier sie gern anders — oder wechsle in der Bibliothek in den API-Key-Modus."
            }
            if case .exceededContextWindowSize = generationError {
                return "Diese Unterhaltung ist für das Geräte-Modell zu lang geworden. Starte am besten einen neuen Chat (Uhr-Symbol oben im Chat → „Neuer Chat“) — dann geht es frisch weiter."
            }
        }
        return "Mit Apple KI ist gerade etwas schiefgelaufen — versuch es gleich nochmal. Wenn es bleibt, hilft oft ein neuer Chat oder der API-Key-Modus aus der Bibliothek."
    }
}
