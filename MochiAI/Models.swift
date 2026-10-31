import Foundation

// MARK: - Profile

struct UserProfile: Codable {
    var name: String
    var relax: String
    var hobby: String
    var teleport: String
}

// MARK: - App info

enum AppInfo {
    /// Shown in the library's About card; keep in sync with MARKETING_VERSION.
    static let version = "2.0.0"
}

// MARK: - Chat

struct ChatMessage: Codable, Identifiable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let date: Date

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// One chat thread. Conversations are persisted as JSON in UserDefaults
/// and shown in the chat's history list.
struct Conversation: Codable, Identifiable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// History-list title: the first user message, truncated.
    var title: String {
        guard let firstUser = messages.first(where: { $0.role == .user }) else {
            return "Neuer Chat"
        }
        let text = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Neuer Chat" }
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    /// History-list subtitle: "31. Okt 2026, 14:02 · 5 Nachrichten".
    var subtitle: String {
        let dateText = Self.dateFormatter.string(from: updatedAt)
        let count = messages.count
        return "\(dateText) · \(count) \(count == 1 ? "Nachricht" : "Nachrichten")"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM yyyy, HH:mm"
        return formatter
    }()
}

// MARK: - Library

struct SavedItem: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var kind: String // "Feed" oder "Idee"
}

// MARK: - Ideas

struct Idea: Codable, Identifiable {
    var id: String
    var title: String
    var text: String
    var category: String
}

// MARK: - Goals

struct GoalStep: Codable, Identifiable {
    var id = UUID()
    var title: String
    var done: Bool = false
}

struct GoalItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var steps: [GoalStep]

    var doneCount: Int { steps.filter { $0.done }.count }
    var progress: Double {
        steps.isEmpty ? 0 : Double(doneCount) / Double(steps.count)
    }
}

// MARK: - GTA 6 dates

enum GTA {
    static var releaseDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 0, minute: 0)) ?? Date()
    }

    static func daysRemaining(from date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let start = calendar.startOfDay(for: date)
        let target = calendar.startOfDay(for: releaseDate)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }
}
