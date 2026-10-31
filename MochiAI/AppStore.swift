import Combine
import Foundation

/// Central app state. Everything is local: profile, chat, saved items,
/// ideas and goals live in UserDefaults; API keys live in the Keychain,
/// one per provider.
@MainActor
final class AppStore: ObservableObject {
    enum Tab: Int, CaseIterable {
        case chat
        case feed
        case ideas
        case goals
        case library
    }

    private enum Keys {
        static let profile = "profile.v1"
        static let savedItems = "saved.items.v1"
        static let goals = "goals.v1"
        static let customIdeas = "ideas.custom.v1"
        static let dismissedIdeas = "ideas.dismissed.v1"
        static let provider = "api.provider"
        static let companion = "companionID"
    }

    @Published var selectedTab: Tab = .chat

    // MARK: Companion

    /// The currently selected animated companion (persisted as "companionID").
    @Published var companion: CompanionID = .mochi {
        didSet {
            UserDefaults.standard.set(companion.rawValue, forKey: Keys.companion)
        }
    }

    /// Bumped whenever a new assistant reply arrives — companions bounce.
    @Published private(set) var companionBounceTick = 0

    func bounceCompanion() {
        companionBounceTick += 1
    }

    @Published var profile: UserProfile? {
        didSet { saveProfile() }
    }

    @Published var messages: [ChatMessage] = []

    @Published var savedItems: [SavedItem] = [] {
        didSet { persist(savedItems, key: Keys.savedItems) }
    }

    @Published var goals: [GoalItem] = [] {
        didSet { persist(goals, key: Keys.goals) }
    }

    @Published var customIdeas: [Idea] = [] {
        didSet { persist(customIdeas, key: Keys.customIdeas) }
    }

    @Published var dismissedIdeaIDs: [String] = [] {
        didSet { persist(dismissedIdeaIDs, key: Keys.dismissedIdeas) }
    }

    // MARK: API configuration

    @Published var provider: APIProvider = .gemini {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider)
            refreshKeyState()
        }
    }

    /// True when the currently selected provider has a stored key.
    @Published private(set) var hasKey = false

    /// Incremented on any API-config change so observing views re-render.
    @Published private(set) var configTick = 0

    init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Keys.provider),
           let savedProvider = APIProvider(rawValue: raw) {
            provider = savedProvider
        }

        if let raw = defaults.string(forKey: Keys.companion),
           let savedCompanion = CompanionID(rawValue: raw) {
            companion = savedCompanion
        }

        profile = load(Keys.profile)
        savedItems = load(Keys.savedItems) ?? []
        customIdeas = load(Keys.customIdeas) ?? []
        dismissedIdeaIDs = load(Keys.dismissedIdeas) ?? []

        if let storedGoals: [GoalItem] = load(Keys.goals) {
            goals = storedGoals
        } else {
            goals = [
                GoalItem(title: "GTA 6 Release Day erleben", steps: [
                    GoalStep(title: "Preload ab 12.11. herunterladen"),
                    GoalStep(title: "Am 19.11. die Story starten"),
                ]),
                GoalItem(title: "Mehr schlafen", steps: [
                    GoalStep(title: "Handy um 23 Uhr weglegen"),
                    GoalStep(title: "7+ Stunden schlafen"),
                ]),
            ]
            persist(goals, key: Keys.goals)
        }

        hasKey = !key(for: provider).isEmpty
    }

    // MARK: Profile

    private func saveProfile() {
        if let profile {
            persist(profile, key: Keys.profile)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.profile)
        }
    }

    func resetOnboarding() {
        profile = nil
        messages = []
    }

    // MARK: Chat

    func seedGreetingIfNeeded() {
        guard messages.isEmpty, let profile else { return }
        messages.append(ChatMessage(
            role: .assistant,
            text: "Hi \(profile.name)! Ich bin Muse — manche nennen mich auch Mochi. Schön, dass du da bist. Erzähl mir von deinem Tag, frag mich was oder schau unten in die Tabs: Im Feed wartet der GTA-6-Countdown, bei den Ideen gibt's Inspiration."
        ))
    }

    // MARK: Saved items

    func isSaved(id: String) -> Bool {
        savedItems.contains { $0.id == id }
    }

    func toggleSaved(_ item: SavedItem) {
        if isSaved(id: item.id) {
            savedItems.removeAll { $0.id == item.id }
        } else {
            savedItems.append(item)
        }
    }

    func removeSaved(id: String) {
        savedItems.removeAll { $0.id == id }
    }

    // MARK: Ideas

    var visibleIdeas: [Idea] {
        (IdeaPool.all + customIdeas).filter { !dismissedIdeaIDs.contains($0.id) }
    }

    func dismissIdea(_ idea: Idea) {
        if customIdeas.contains(where: { $0.id == idea.id }) {
            customIdeas.removeAll { $0.id == idea.id }
        }
        if !dismissedIdeaIDs.contains(idea.id) {
            dismissedIdeaIDs.append(idea.id)
        }
        removeSaved(id: "idea:\(idea.id)")
    }

    // MARK: API configuration per provider

    func key(for provider: APIProvider) -> String {
        KeychainHelper.get(account: "apiKey.\(provider.rawValue)") ?? ""
    }

    func setKey(_ value: String, for provider: APIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(account: "apiKey.\(provider.rawValue)")
        } else {
            KeychainHelper.set(trimmed, account: "apiKey.\(provider.rawValue)")
        }
        refreshKeyState()
    }

    func baseURL(for provider: APIProvider) -> String {
        UserDefaults.standard.string(forKey: "api.\(provider.rawValue).baseURL") ?? provider.defaultBaseURL
    }

    func setBaseURL(_ value: String, for provider: APIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? provider.defaultBaseURL : trimmed,
                                  forKey: "api.\(provider.rawValue).baseURL")
        configTick += 1
    }

    func model(for provider: APIProvider) -> String {
        UserDefaults.standard.string(forKey: "api.\(provider.rawValue).model") ?? provider.defaultModel
    }

    func setModel(_ value: String, for provider: APIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? provider.defaultModel : trimmed,
                                  forKey: "api.\(provider.rawValue).model")
        configTick += 1
    }

    private func refreshKeyState() {
        hasKey = !key(for: provider).isEmpty
        configTick += 1
    }

    // MARK: Active engine

    var activeKey: String { key(for: provider) }
    var activeBaseURL: String { baseURL(for: provider) }
    var activeModel: String { model(for: provider) }

    var isConfigured: Bool { hasKey }

    /// Short label: "Gemini API" / "OpenAI-kompatibel" / "Demo-Modus".
    var engineLabel: String {
        isConfigured ? provider.engineLabel : "Demo-Modus"
    }

    /// Settings caption: "Gemini API (eigener Key)" or "Demo-Modus (lokal)".
    var engineCaption: String {
        isConfigured ? "\(provider.engineLabel) (eigener Key)" : "Demo-Modus (lokal)"
    }

    // MARK: Persistence helpers

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
