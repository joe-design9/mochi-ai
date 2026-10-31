import SwiftUI

/// Chat tab, modeled on the Claude/ChatGPT apps: assistant answers are
/// plain text blocks with the companion beside them, user messages sit in
/// a subtle neutral bubble, and the empty state greets with the large
/// animated companion plus suggestion chips.
/// Engine: configured provider (API) or Demo-Modus.
struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var input = ""
    @State private var isThinking = false

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)

            if store.messages.isEmpty && !isThinking {
                emptyState
            } else {
                messageList
            }

            inputBar
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            CompanionView(character: store.companion, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Muse")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(store.engineLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            if !store.isConfigured {
                Button {
                    store.selectedTab = .library
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        Text("Demo-Modus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Palette.card))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                CompanionView(character: store.companion, size: 110)
                    .padding(.top, 36)
                VStack(spacing: 8) {
                    Text("Hallo, \(store.profile?.name ?? "Freund")")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("Ich bin Muse — manche nennen mich auch Mochi. Erzähl mir von deinem Tag, frag mich was oder stöber durch die Tabs: Im Feed wartet der GTA-6-Countdown.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            send(text: suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Palette.card))
                                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var suggestions: [String] {
        [
            "Wie lange noch bis GTA 6?",
            "Gib mir eine Idee für heute",
            "Was sind meine Ziele?",
        ]
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(store.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if isThinking {
                        typingRow
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .onChange(of: store.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isThinking) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                CompanionView(character: store.companion, size: 26, animated: false)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Palette.subtleFill)
                    )
            }
        }
    }

    private var typingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            CompanionView(character: store.companion, size: 26, animated: false)
            TypingDots()
            Spacer()
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "",
                text: $input,
                prompt: Text("Nachricht an Muse …").foregroundColor(Palette.secondaryText),
                axis: .vertical
            )
            .lineLimit(1...4)
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .onSubmit { send(text: input) }

            Button {
                send(text: input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? Palette.accent : Palette.secondaryText.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Logic

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if isThinking {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        store.messages.append(ChatMessage(role: .user, text: text))
        isThinking = true

        let history = store.messages
        let configured = store.isConfigured
        let config = EngineConfig(
            provider: store.provider,
            key: store.activeKey,
            baseURL: store.activeBaseURL,
            model: store.activeModel,
            profile: store.profile
        )
        let responder = LocalResponder(
            profile: store.profile,
            ideaTitles: store.visibleIdeas.map(\.title),
            goalTitles: store.goals.map(\.title)
        )

        Task {
            let reply: String
            if configured {
                reply = await APIClient.send(history: history, config: config)
            } else {
                try? await Task.sleep(nanoseconds: 700_000_000)
                reply = responder.reply(to: text)
            }
            store.messages.append(ChatMessage(role: .assistant, text: reply))
            store.bounceCompanion()
            isThinking = false
        }
    }
}

// MARK: - Typing indicator

struct TypingDots: View {
    @State private var bouncing = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.secondaryText)
                    .frame(width: 7, height: 7)
                    .offset(y: bouncing ? -3 : 2)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: bouncing
                    )
            }
        }
        .onAppear { bouncing = true }
    }
}
