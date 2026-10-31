import Foundation

/// One row of the invite backend's list_invites RPC.
struct InviteCodeRow: Identifiable {
    var code: String
    var used: Bool
    var createdAt: Date
    var usedAt: Date?

    var id: String { code }
}

// MARK: - Errors (with user-facing German text)

enum InviteBackendError: Error {
    /// No route to the backend at all (DNS, offline, timeout …).
    case offline
    /// Any HTTP failure, with the status code.
    case http(Int)
    /// Payload did not have the expected shape.
    case badPayload

    var german: String {
        switch self {
        case .offline:
            return "Keine Verbindung zum Server. Prüfe deine Internetverbindung und versuch es erneut."
        case .http(let status):
            return "Der Server meldet einen Fehler (HTTP \(status)). Bitte versuch es später erneut."
        case .badPayload:
            return "Der Server hat unerwartet geantwortet. Bitte versuch es später erneut."
        }
    }
}

// MARK: - Client

/// Slim hand-rolled client for the three invite RPCs (PostgREST)
/// over URLSession. There are deliberately NO auth accounts: an
/// install is identified by its Keychain UUID (AppStore.installID),
/// and the RPCs are the only surface granted to the public anon key
/// (the invite_codes table itself has RLS with no client policies).
enum InviteBackend {
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// redeem_invite(p_code, p_install) → true when the code was
    /// open and is now bound to this install; false when the code
    /// does not exist or was already redeemed.
    static func redeemInvite(code: String, installID: String) async throws -> Bool {
        let data = try await rpc("redeem_invite", body: [
            "p_code": code,
            "p_install": installID,
        ])
        return try parseBool(data)
    }

    /// create_invite(p_code) → true when the row was inserted.
    static func createInvite(code: String) async throws -> Bool {
        let data = try await rpc("create_invite", body: ["p_code": code])
        return try parseBool(data)
    }

    /// list_invites() → all codes, newest first (the RPC orders).
    static func listInvites() async throws -> [InviteCodeRow] {
        let data = try await rpc("list_invites", body: [:])
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let rows = value as? [[String: Any]] else {
            throw InviteBackendError.badPayload
        }
        return rows.map { row in
            InviteCodeRow(
                code: (row["code"] as? String) ?? "",
                used: (row["used"] as? Bool) ?? false,
                createdAt: parseServerDate((row["created_at"] as? String) ?? "") ?? Date(),
                usedAt: parseServerDate((row["used_at"] as? String) ?? "")
            )
        }
    }

    // MARK: Plumbing

    private static func rpc(_ name: String, body: [String: Any]) async throws -> Data {
        guard BackendConfig.isConfigured,
              let url = URL(string: BackendConfig.endpoint + "/rest/v1/rpc/" + name) else {
            throw InviteBackendError.offline
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(BackendConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(BackendConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InviteBackendError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw InviteBackendError.http(status) }
        return data
    }

    private static func parseBool(_ data: Data) throws -> Bool {
        let value = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        throw InviteBackendError.badPayload
    }

    /// Supabase timestamps arrive as ISO-8601 with up to 6
    /// fractional digits and a +00:00 offset — try the formatters
    /// in order of likelihood (same chain as GlassGram's client).
    private static func parseServerDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = formatter.date(from: string) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: string)
    }
}
