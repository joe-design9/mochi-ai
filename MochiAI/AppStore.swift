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
        static let engineMode = "engine.mode.v1"
        static let companion = "companionID"
        static let conversations = "chat.conversations.v1"
        static let activeConversation = "chat.activeConversation.v1"
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

    // MARK: Conversations (chat history)

    /// All persisted conversations that contain at least one message,
    /// newest activity first. The active conversation is matched by ID.
    @Published private(set) var conversations: [Conversation] = [] {
        didSet { persist(conversations, key: Keys.conversations) }
    }

    /// ID of the conversation the chat currently shows and writes into.
    @Published private(set) var activeConversationID: UUID? {
        didSet {
            if let activeConversationID,
               conversations.contains(where: { $0.id == activeConversationID }) {
                UserDefaults.standard.set(activeConversationID.uuidString,
                                          forKey: Keys.activeConversation)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.activeConversation)
            }
        }
    }

    /// Backing store for a brand-new, still-empty draft conversation
    /// (kept out of `conversations` until its first message arrives).
    private var activeDraft = Conversation()

    /// Messages of the active conversation.
    ///
    /// Bridge over the conversation model: reading returns the active
    /// conversation's messages, writing replaces them (stamping
    /// `updatedAt`, inserting the conversation into the persisted list
    /// once it has content, removing it again when emptied). didSet fires
    /// on every write, so views keep observing message changes as before.
    @Published var messages: [ChatMessage] = [] {
        didSet { syncActiveConversation() }
    }

    /// Conversations for the history sheet, newest first.
    var historyConversations: [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Send queue

    /// One queued outgoing request: the user text plus the conversation
    /// it belongs to (replies always land in their origin conversation,
    /// even if the user switches chats while waiting). The `id` token
    /// identifies the RUNNING call unambiguously: deleting a conversation
    /// must never clear another call's slot (that would let two calls
    /// run concurrently and race their replies).
    private struct QueuedSend {
        let id = UUID()
        let conversationID: UUID
        let text: String
    }

    /// FIFO of user messages waiting for their provider/demo call.
    private var sendQueue: [QueuedSend] = []

    /// The queue item whose call is currently running, if any.
    private var currentSend: QueuedSend?

    /// True from enqueue until the queue has fully drained — drives the
    /// typing indicator.
    @Published private(set) var isChatBusy = false

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

    /// Engine mode: cloud provider via API key, or Apple's on-device
    /// model. Persisted; defaults to the API-key mode.
    @Published var engineMode: EngineMode = .apiKey {
        didSet {
            UserDefaults.standard.set(engineMode.rawValue, forKey: Keys.engineMode)
            configTick += 1
        }
    }

    /// Apple's on-device engine (FoundationModels). Sessions live here
    /// so they survive conversation switches within an app run.
    let appleEngine = AppleIntelligenceEngine()

    /// Current FoundationModels availability (read live on each access).
    var appleAvailability: AppleAvailability { AppleAvailability.current }

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

        if let raw = defaults.string(forKey: Keys.engineMode),
           let savedMode = EngineMode(rawValue: raw) {
            engineMode = savedMode
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

        // Gemini model migration (one-time, mirrors the v1.1.0 base-URL
        // fix): Google retired "gemini-2.5-flash" for new users and its
        // API error points to "gemini-3.8-flash" — upgrade a persisted
        // old value so existing installs keep working untouched.
        let geminiModelKey = "api.\(APIProvider.gemini.rawValue).model"
        if defaults.string(forKey: geminiModelKey) == "gemini-2.5-flash" {
            defaults.set(APIProvider.gemini.defaultModel, forKey: geminiModelKey)
        }

        // Chat history: restore persisted conversations and reopen the
        // last active one (or the most recently updated as a fallback)
        // so no chat is ever lost across a restart.
        let storedConversations: [Conversation] = load(Keys.conversations) ?? []
        conversations = storedConversations.filter { !$0.messages.isEmpty }
        if let rawID = defaults.string(forKey: Keys.activeConversation),
           let uuid = UUID(uuidString: rawID),
           conversations.contains(where: { $0.id == uuid }) {
            activeConversationID = uuid
        } else {
            activeConversationID = historyConversations.first?.id
        }
        if let activeConversationID,
           let active = conversations.first(where: { $0.id == activeConversationID }) {
            messages = active.messages
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
        // Persona instructions change with the profile — drop the
        // Apple-KI sessions so they are rebuilt with fresh instructions.
        appleEngine.dropAllSessions()
    }

    // MARK: Chat — conversation management

    /// Writes the current `messages` back into the active conversation.
    /// A conversation joins the persisted list with its first message
    /// and leaves it again when emptied (e.g. onboarding reset).
    private func syncActiveConversation() {
        if let activeConversationID,
           let index = conversations.firstIndex(where: { $0.id == activeConversationID }) {
            if messages.isEmpty {
                conversations.remove(at: index)
                activeDraft = Conversation(id: activeConversationID)
            } else {
                conversations[index].messages = messages
                conversations[index].updatedAt = Date()
            }
        } else if !messages.isEmpty {
            let now = Date()
            let conversation = Conversation(
                id: activeDraft.id,
                createdAt: activeDraft.createdAt,
                updatedAt: now,
                messages: messages
            )
            conversations.insert(conversation, at: 0)
            activeConversationID = conversation.id
        } else {
            activeDraft.messages = messages
        }
    }

    /// Appends a message (and a fresh `updatedAt`) to any conversation —
    /// used by the send queue so replies land in the conversation they
    /// were asked in, even when it is not the visible one. Replies for a
    /// conversation that was deleted mid-flight are dropped instead of
    /// leaking into a fresh draft.
    private func appendMessage(_ message: ChatMessage, to conversationID: UUID) {
        if conversationID == activeConversationID,
           conversations.contains(where: { $0.id == conversationID }) {
            messages.append(message)
        } else if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].messages.append(message)
            conversations[index].updatedAt = Date()
        }
    }

    /// Starts a fresh, empty conversation. It only appears in the
    /// history list once it contains a message.
    func startNewConversation() {
        persistActiveMessages()
        activeConversationID = nil
        activeDraft = Conversation()
        messages = []
        prewarmActiveAppleSessionIfNeeded()
    }

    /// Makes the given conversation the active one and loads its messages.
    func switchConversation(to id: UUID) {
        guard id != activeConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        persistActiveMessages()
        activeConversationID = id
        messages = conversation.messages
        prewarmActiveAppleSessionIfNeeded()
    }

    /// In Apple-KI mode, warms up the on-device session of the
    /// conversation currently on screen so its first answer starts
    /// faster (chat appearing, conversation switches). No-op in
    /// API-Key mode and when Apple Intelligence is unavailable.
    func prewarmActiveAppleSessionIfNeeded() {
        guard engineMode == .appleIntelligence else { return }
        appleEngine.prewarm(conversationID: currentConversationID, profile: profile)
    }

    /// Flushes the visible messages into the active conversation before
    /// the active pointer moves elsewhere.
    private func persistActiveMessages() {
        if !messages.isEmpty {
            // Re-assigning triggers the didSet sync.
            messages = messages
        }
    }

    /// Removes a conversation (and any of its still-queued sends).
    /// Deleting the active one falls back to the most recent other
    /// conversation, or to a fresh draft when none is left.
    ///
    /// A send for this conversation that is ALREADY running is left to
    /// finish on its own: its reply is dropped by `appendMessage`
    /// (target gone), and its completion only clears its own queue slot
    /// (matched by send ID, never by conversation). Clearing the slot
    /// here instead would let a second call start concurrently.
    func deleteConversation(id: UUID) {
        sendQueue.removeAll { $0.conversationID == id }
        appleEngine.dropSession(conversationID: id)
        conversations.removeAll { $0.id == id }
        if id == activeConversationID {
            if let fallback = historyConversations.first {
                switchConversation(to: fallback.id)
            } else {
                startNewConversation()
            }
        }
        updateChatBusy()
    }

    // MARK: Chat — send queue (FIFO, one call at a time)

    /// Sends a user message: it appears in the chat immediately and the
    /// input stays free — the actual provider/demo call runs through
    /// the queue, so several messages can be fired off back-to-back.
    func sendUserMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Resolve the target first: appending the first message flips
        // the fresh draft into a persisted conversation (and its ID
        // becomes the active one) via the messages didSet sync.
        let conversationID = activeConversationID ?? activeDraft.id
        messages.append(ChatMessage(role: .user, text: text))

        sendQueue.append(QueuedSend(conversationID: conversationID, text: text))
        updateChatBusy()
        drainSendQueue()
    }

    /// True while the given conversation has a queued or running call.
    func isBusy(conversationID: UUID?) -> Bool {
        guard let conversationID else { return false }
        if currentSend?.conversationID == conversationID { return true }
        return sendQueue.contains { $0.conversationID == conversationID }
    }

    /// The conversation the chat currently writes into: the active one,
    /// or the still-unpersisted draft's ID.
    var currentConversationID: UUID { activeConversationID ?? activeDraft.id }

    /// Typing-indicator state for the chat: busy only when a queued or
    /// running call belongs to the conversation on screen (it used to
    /// mirror the GLOBAL queue, so other chats showed phantom typing).
    var isActiveConversationBusy: Bool { isBusy(conversationID: currentConversationID) }

    private func updateChatBusy() {
        isChatBusy = currentSend != nil || !sendQueue.isEmpty
    }

    /// Starts the next queued call when idle. Each call snapshots the
    /// conversation history and the engine config as they stand when
    /// the call starts, so earlier queued exchanges are included.
    private func drainSendQueue() {
        guard currentSend == nil, !sendQueue.isEmpty else { return }
        let item = sendQueue.removeFirst()
        currentSend = item
        updateChatBusy()
        Task { await performSend(item) }
    }

    private func performSend(_ item: QueuedSend) async {
        let history: [ChatMessage]
        if item.conversationID == activeConversationID {
            history = messages
        } else {
            history = conversations.first(where: { $0.id == item.conversationID })?.messages ?? []
        }

        let reply: String
        switch engineMode {
        case .appleIntelligence:
            // On-device model. The engine itself converts every failure
            // (unavailable, context overflow, guardrails) into a clear
            // in-chat note, so the queue always moves on.
            reply = await appleEngine.respond(
                conversationID: item.conversationID,
                history: history,
                latestText: item.text,
                profile: profile
            )
        case .apiKey:
            if hasKey, !history.isEmpty {
                let config = EngineConfig(
                    provider: provider,
                    key: activeKey,
                    baseURL: activeBaseURL,
                    model: activeModel,
                    profile: profile
                )
                // APIClient.send converts provider failures into an
                // in-character error note — the queue can never jam.
                reply = await APIClient.send(history: history, config: config)
            } else {
                // Demo-Modus: the fallback when neither a key nor
                // Apple KI is usable.
                let responder = LocalResponder(
                    profile: profile,
                    ideaTitles: visibleIdeas.map(\.title),
                    goalTitles: goals.map(\.title)
                )
                try? await Task.sleep(nanoseconds: 700_000_000)
                reply = responder.reply(to: item.text)
            }
        }

        appendMessage(ChatMessage(role: .assistant, text: reply), to: item.conversationID)
        bounceCompanion()

        // Only ever clear OUR OWN slot (matched by send ID): another
        // conversation's bookkeeping must not unleash a second call.
        if currentSend?.id == item.id {
            currentSend = nil
        }
        updateChatBusy()
        drainSendQueue()
    }

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

    /// True when the SELECTED mode can actually answer: API-Key mode
    /// needs a stored key; Apple-KI mode needs the model available.
    var isConfigured: Bool {
        switch engineMode {
        case .apiKey: return hasKey
        case .appleIntelligence: return appleAvailability.isAvailable
        }
    }

    /// Short label for the chat header: the active engine, or Demo.
    var engineLabel: String {
        switch engineMode {
        case .apiKey:
            return hasKey ? provider.engineLabel : "Demo-Modus"
        case .appleIntelligence:
            return appleAvailability.isAvailable ? "Apple KI (lokal)" : "Apple KI nicht verfügbar"
        }
    }

    /// Settings caption describing the active engine.
    var engineCaption: String {
        switch engineMode {
        case .apiKey:
            return hasKey ? "\(provider.engineLabel) (eigener Key)" : "Demo-Modus (lokal)"
        case .appleIntelligence:
            return appleAvailability.isAvailable
                ? "Apple KI (lokal)"
                : "Apple KI — \(appleAvailability.statusText)"
        }
    }

    /// Header chip text when no real engine is active.
    var fallbackChipLabel: String {
        engineMode == .appleIntelligence ? "Apple KI aus" : "Demo-Modus"
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
