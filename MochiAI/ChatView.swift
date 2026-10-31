import SwiftUI

/// Chat tab: glass bubbles, orb avatar, typing indicator, glass input bar.
/// Engine: configured provider (OpenAI-compatible API) or Demo-Modus.
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
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
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
                .onChange(of: store.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isThinking) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            inputBar
        }
        .padding(.bottom, 96)
        .onAppear {
            store.seedGreetingIfNeeded()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            OrbView(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Muse")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(store.isConfigured ? store.provider.engineLabel : "Demo-Modus")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
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
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Messages

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                OrbView(size: 28)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(
                        .regular.tint(Color(red: 0.60, green: 0.44, blue: 0.98).opacity(0.45)),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
            }
        }
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            OrbView(size: 28)
            TypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 40)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "",
                text: $input,
                prompt: Text("Nachricht an Muse …").foregroundColor(.white.opacity(0.45)),
                axis: .vertical
            )
            .lineLimit(1...4)
            .foregroundStyle(.white)
            .tint(.white)
            .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Palette.lavender : Color.white.opacity(0.30))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 6)
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

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        store.messages.append(ChatMessage(role: .user, text: text))
        isThinking = true

        let history = store.messages
        let configured = store.isConfigured
        let config = EngineConfig(
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
                    .fill(Color.white.opacity(0.85))
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
