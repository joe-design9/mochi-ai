import SwiftUI

/// Chat tab, modeled on the Claude/ChatGPT apps: assistant answers are
/// plain text blocks with the companion beside them, user messages sit in
/// a subtle neutral bubble, and the empty state greets with the large
/// animated companion plus suggestion chips.
/// Sending runs through the store's FIFO queue: the input is never
/// disabled, messages appear instantly, calls run one at a time.
/// Engine: configured provider (API) or Demo-Modus.
struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var input = ""
    @State private var showingHistory = false
    @FocusState private var inputFocused: Bool

    /// Purely visual: the send arrow is full-strength with text present.
    /// Sending is ALWAYS possible — never gated on a running request.
    private var hasText: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)

            if store.messages.isEmpty && !store.isActiveConversationBusy {
                emptyState
            } else {
                messageList
            }

            inputBar
        }
        .sheet(isPresented: $showingHistory) {
            ChatHistorySheet()
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
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chatverlauf")
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
                            store.sendUserMessage(suggestion)
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
        .scrollDismissesKeyboard(.interactively)
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
                    if store.isActiveConversationBusy {
                        typingRow
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: store.isActiveConversationBusy) { _, _ in
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
            .focused($inputFocused)
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
            .onSubmit { sendCurrentInput() }

            Button {
                sendCurrentInput()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(hasText ? Palette.accent : Palette.secondaryText.opacity(0.4)))
            }
            .buttonStyle(.plain)
            // Deliberately never disabled: back-to-back messages queue up
            // in the store and are answered one after another.
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Logic

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if store.isActiveConversationBusy {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// Queues the current input (the message appears instantly; the call
    /// runs through the store's FIFO queue). The keyboard stays up for
    /// back-to-back typing — dragging the list dismisses it.
    private func sendCurrentInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        store.sendUserMessage(text)
    }
}

// MARK: - Chat history sheet

/// Lists all past conversations (newest first) with the first user
/// message as the title; tap to reopen, swipe to delete, and a prominent
/// "Neuer Chat" button on top.
struct ChatHistorySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    SectionTitle(text: "Chatverlauf")
                    Spacer()
                    Button {
                        store.startNewConversation()
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Neuer Chat")
                        }
                        .accentCapsule()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

                if store.historyConversations.isEmpty {
                    VStack(spacing: 10) {
                        CompanionView(character: store.companion, size: 64)
                        Text("Noch keine alten Chats. Sobald du hier schreibst, tauchen deine Unterhaltungen in dieser Liste auf.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    Spacer()
                } else {
                    List {
                        ForEach(store.historyConversations) { conversation in
                            conversationRow(conversation)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.deleteConversation(id: store.historyConversations[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let isActive = conversation.id == store.activeConversationID
        return Button {
            store.switchConversation(to: conversation.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(conversation.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                if isActive {
                    Text("Aktiv")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.subtleFill))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Palette.hairline)
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
