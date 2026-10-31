import Foundation

// MARK: - Profile

struct UserProfile: Codable {
    var name: String
    var relax: String
    var hobby: String
    var teleport: String
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let date = Date()
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
