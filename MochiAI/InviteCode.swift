import Foundation

/// Invite codes — ONE module shared by the normal and the admin
/// build, so a code generated in the admin app always validates in
/// the normal app. The checksum is checked fully offline (client
/// side) before any network call; whether a well-formed code is
/// still open is decided server-side by the redeem_invite RPC.
///
/// Format:  MA-XXXXXX-XXXXXX
///   - group 1: payload characters 1–6
///   - group 2: payload characters 7–10 + 2 checksum characters
///
/// Alphabet (Crockford-style, 30 characters — digits 0/1 and letters
/// I, L, O, U are excluded because they are easily confused):
///   23456789ABCDEFGHJKMNPQRSTVWXYZ
///
/// Checksum: FNV-1a (32-bit) over the UTF-8 bytes of
/// (salt + payload), where salt is a fixed app constant.
///   checksum char 1 = alphabet[hash % 30]
///   checksum char 2 = alphabet[(hash / 30) % 30]
///
/// (Same construction as GlassGram's GG codes, with the MA prefix
/// and its own salt — GG and MA codes can never collide.)
enum InviteCode {
    static let alphabet: [Character] = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let salt = "MochiAI::Invite::v1::"
    private static let payloadLength = 10

    // MARK: Checksum

    private static func fnv1a(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    static func checksum(payload: String) -> String {
        let hash = fnv1a(salt + payload)
        let a = alphabet[Int(hash % 30)]
        let b = alphabet[Int((hash / 30) % 30)]
        return String([a, b])
    }

    // MARK: Construction

    /// Builds the printable code from a 10-character payload.
    static func makeCode(payload: String) -> String {
        let p = Array(payload)
        guard p.count == payloadLength else { return "" }
        let group1 = String(p[0..<6])
        let group2 = String(p[6..<10]) + checksum(payload: payload)
        return "MA-\(group1)-\(group2)"
    }

    /// A fresh random code (admin "Neuen Code erstellen").
    static func generate() -> String {
        var payload = ""
        for _ in 0..<payloadLength {
            payload.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return makeCode(payload: payload)
    }

    /// Deterministic code derived from a seed index — used for the
    /// QA screenshot seed in the admin build (two sample codes, one
    /// open, one used), so the captures show real-format codes that
    /// are valid by construction without any network.
    static func seededCode(_ index: Int) -> String {
        var state = fnv1a("MochiAI::Seed::\(index)")
        var payload = ""
        for _ in 0..<payloadLength {
            // LCG step (Numerical Recipes constants) — deterministic.
            state = state &* 1_664_525 &+ 1_013_904_223
            payload.append(alphabet[Int((state >> 8) % 30)])
        }
        return makeCode(payload: payload)
    }

    // MARK: Validation

    /// Uppercases and strips whitespace so pasted codes are forgiving.
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace }
    }

    static func isValid(_ raw: String) -> Bool {
        let code = normalize(raw)
        let parts = code.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "MA",
              parts[1].count == 6, parts[2].count == 6 else { return false }
        let payload = String(parts[1]) + String(parts[2].prefix(4))
        let check = String(parts[2].suffix(2))
        guard payload.count == payloadLength,
              payload.allSatisfy({ alphabet.contains($0) }),
              check.allSatisfy({ alphabet.contains($0) }) else { return false }
        return checksum(payload: payload) == check
    }
}
