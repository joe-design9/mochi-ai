import SwiftUI
import UIKit

/// Light haptic taps for the send/reply moments (premium feel, cheap).
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Chat tab in the Muse identity — full Liquid Glass like the real
/// Muse app: a glass header bar, assistant answers on neutral glass
/// cards with the companion beside them, user messages in brighter
/// smoky-glass bubbles, and the empty state greets with the large
/// companion plus glass suggestion chips. All monochrome over black.
/// Sending runs through the store's FIFO queue: the input is never
/// disabled, messages appear instantly, calls run one at a time.
/// Engine: API-Key mode, Apple KI (on-device), or Demo-Modus fallback.
struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var input = ""
    @State private var showingHistory = false
    @State private var showingCall = false
    @FocusState private var inputFocused: Bool

    /// Tracks whether the user is scrolled to (near) the newest
    /// message — used only for following the typing indicator.
    /// Incoming REPLIES no longer depend on it: they are anchored by
    /// the anchoring machine below so their start is on screen.
    @State private var isNearBottom = true

    /// Height of the visible message area, captured from the scroll
    /// geometry — the reply anchoring compares the reply's measured
    /// height against it.
    @State private var viewportHeight: CGFloat = 0

    // MARK: Reply anchoring machine (v2.2.2)
    //
    // The v2.2.0 approach fired ONE scrollTo from the messages-count
    // onChange and hoped for the best; on device it kept missing (see
    // the diagnosis in the anchoring section below). This machine
    // instead treats anchoring as a small stateful process: several
    // settle passes per reply, decisions based on the reply's
    // MEASURED height, and a hard stop the moment the user grabs the
    // list — re-armed by the next reply.

    /// ID of the assistant reply currently being anchored.
    @State private var anchorTargetID: UUID?

    /// The newest reply whose anchoring has been started. Catch-up
    /// paths (list re-appearing, call cover closing) compare against
    /// it so already-anchored replies are never yanked twice.
    @State private var handledReplyID: UUID?

    /// Conversation the anchoring machine last reconciled with. A
    /// change means the message array was swapped wholesale (history
    /// switch, new chat, delete fallback) — NOT that a reply arrived —
    /// so the arrival trigger stands down for that update.
    @State private var anchoredConversationID: UUID?

    /// Bumped on every anchoring (re)start and cancellation. Settle
    /// passes capture the generation at schedule time and die quietly
    /// when a newer generation exists.
    @State private var anchorGeneration = 0

    /// True once the user grabs the list while a reply is being
    /// anchored: settle passes stop forcing the position. Cleared by
    /// the next reply (beginAnchoring) — never by time.
    @State private var anchorSuppressed = false

    /// Measured row heights (points) per message ID, fed by each
    /// row's geometry reader — the anchor decision (top vs. bottom)
    /// uses the REAL bubble height, not a character-count estimate.
    @State private var rowHeights: [UUID: CGFloat] = [:]

    /// Last message ID at the moment the call screen was opened, so
    /// its closing can catch up on transcript replies that landed
    /// while the chat was covered.
    @State private var replyIDAtCallStart: UUID?

    /// Purely visual: the send arrow is full-strength with text present.
    /// Sending is ALWAYS possible — never gated on a running request.
    private var hasText: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.messages.isEmpty && !store.isActiveConversationBusy {
                emptyState
            } else {
                messageList
            }

            inputBar
        }
        .dismissKeyboardOnTap()
        .onAppear {
            // Apple-KI mode: warm the on-device session up in the
            // background so the first answer starts faster.
            store.prewarmActiveAppleSessionIfNeeded()
        }
        .sheet(isPresented: $showingHistory) {
            ChatHistorySheet()
        }
        .fullScreenCover(isPresented: $showingCall) {
            CallView()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            CompanionGlow(character: store.companion, size: 34)
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
                            .fill(Palette.secondaryText)
                            .frame(width: 7, height: 7)
                        Text(store.fallbackChipLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .glassEffect(
                        .regular.tint(Palette.glassTint).interactive(),
                        in: Capsule()
                    )
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
        // The header is a full-width Liquid Glass bar (Muse-app style).
        .glassEffect(
            .regular.tint(Palette.glassTint),
            in: Rectangle()
        )
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                CompanionGlow(character: store.companion, size: 110)
                    .padding(.top, 36)
                VStack(spacing: 8) {
                    Text("Hallo, \(store.profile?.name ?? "Freund")")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("Ich bin Muse — manche nennen mich auch Mochi. Erzähl mir von deinem Tag, frag mich was oder stöber durch die Tabs: Im Feed wartet der GTA-6-Countdown.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            Haptics.light()
                            store.sendUserMessage(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glassEffect(
                                    .regular.tint(Palette.glassTint).interactive(),
                                    in: Capsule()
                                )
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
                            // Feed the row's REAL height into the
                            // anchoring machine: the top/bottom
                            // decision and the settle passes run on
                            // measured sizes, and a height change of
                            // the anchor target re-fires a pass — so
                            // the final position is set once layout
                            // has stopped moving.
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { _, newHeight in
                                recordRowHeight(message, height: newHeight, proxy: proxy)
                            }
                    }
                    if store.isActiveConversationBusy {
                        typingRow
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .onAppear {
                    handleListAppear(proxy)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Keep track of whether the user is near the newest
            // message (typing indicator follows it) and how tall the
            // visible area is (reply anchoring below).
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height < 120
            } action: { _, newValue in
                isNearBottom = newValue
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, newValue in
                if abs(newValue - viewportHeight) > 1 {
                    viewportHeight = newValue
                }
            }
            // The user grabbing the list is a hard stop for the
            // anchoring machine: no settle pass may fight a human
            // hand. Programmatic scrolls report .animating, never
            // .tracking/.interacting, so our own passes don't trip
            // this. The NEXT reply re-arms the machine.
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .tracking || newPhase == .interacting
                    || newPhase == .decelerating {
                    anchorSuppressed = true
                }
            }
            // The single arrival trigger for ALL engines (API, Apple
            // KI, demo, call transcripts): the visible conversation
            // gained a new last message.
            .onChange(of: store.messages.last?.id) { _, newID in
                guard let newID, let last = store.messages.last, last.id == newID
                else { return }
                if store.currentConversationID != anchoredConversationID {
                    // Wholesale swap (history switch, new chat, delete
                    // fallback): not an arrival. Open at the newest
                    // message like before and treat a trailing reply
                    // as already handled so nothing yanks later.
                    anchoredConversationID = store.currentConversationID
                    cancelAnchoring()
                    if last.role == .assistant { handledReplyID = last.id }
                    scrollToBottom(proxy)
                    return
                }
                if last.role == .user {
                    // The user's own message always scrolls into view
                    // and supersedes any anchoring in flight.
                    cancelAnchoring()
                    scrollToBottom(proxy)
                } else if store.messages.contains(where: { $0.role == .user }) {
                    // A REPLY arrived: it must be readable WITHOUT
                    // scrolling (unless it's already the handled one —
                    // e.g. a duplicate trigger for the same append).
                    if last.id != handledReplyID {
                        beginAnchoring(last, with: proxy)
                    }
                } else {
                    // A lone assistant message with no user message
                    // before it is the seeded greeting — never yank.
                    handledReplyID = last.id
                }
            }
            .onChange(of: store.isActiveConversationBusy) { _, isBusy in
                if isBusy && isNearBottom {
                    scrollToBottom(proxy)
                }
            }
            // Call transcripts land while the chat is covered by the
            // call screen; their onChange passes may not take effect
            // under the cover. When the cover closes, catch up on a
            // reply that arrived during the call — decisively, once.
            .onChange(of: showingCall) { _, isShowing in
                if !isShowing,
                   let last = store.messages.last,
                   last.role == .assistant,
                   last.id != replyIDAtCallStart,
                   store.messages.contains(where: { $0.role == .user }) {
                    beginAnchoring(last, with: proxy)
                }
            }
        }
    }

    /// First appearance of the list (cold start, first chat after
    /// onboarding): if the conversation ends in a reply that was never
    /// anchored on screen — e.g. it arrived while the app was away —
    /// anchor it now; otherwise open at the newest message as before.
    private func handleListAppear(_ proxy: ScrollViewProxy) {
        anchoredConversationID = store.currentConversationID
        if let last = store.messages.last,
           last.role == .assistant,
           last.id != handledReplyID,
           store.messages.contains(where: { $0.role == .user }) {
            beginAnchoring(last, with: proxy)
        } else if store.isActiveConversationBusy {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        } else if let last = store.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                CompanionView(character: store.companion, size: 26, animated: false)
                // Assistant answers sit on a neutral Liquid Glass card
                // (full Muse-app look).
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 18)
            } else {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(
                        .regular.tint(Palette.userBubbleTint),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        }
    }

    private var typingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            CompanionView(character: store.companion, size: 26, animated: false)
            TypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassEffect(
                    .regular.tint(Palette.glassTint),
                    in: Capsule()
                )
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
                    .fill(Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .onSubmit { sendCurrentInput() }

            if hasText {
                Button {
                    sendCurrentInput()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.primaryFill))
                }
                .buttonStyle(.plain)
                // Deliberately never disabled: back-to-back messages
                // queue up in the store and are answered one after
                // another.
            } else {
                // Empty field: the send button becomes the call button
                // (phone glyph in a glass circle) — tap to start a real
                // phone call with Muse (CallView).
                Button {
                    inputFocused = false
                    // Remember the newest message so the chat can
                    // catch up on transcript replies when the call
                    // screen closes again.
                    replyIDAtCallStart = store.messages.last?.id
                    showingCall = true
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 36, height: 36)
                        .glassEffect(
                            .regular.tint(Palette.glassTint).interactive(),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anrufen")
            }
        }
        .padding(10)
        .glassEffect(
            .regular.tint(Palette.glassTint),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
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

    // MARK: Reply anchoring (v2.2.2)
    //
    // Why v2.2.0's anchoring missed on device — three compounding
    // defects:
    // 1. SINGLE SHOT INTO A LAZY STACK. The old code fired exactly one
    //    scrollTo from the messages-count onChange. At that moment the
    //    new row of the LazyVStack has not been realized yet, so the
    //    scroll is clamped against the stack's stale/estimated content
    //    height (or quietly dropped) — and nothing ever retried.
    // 2. TYPING-ROW RACE. The scroll was computed while the typing
    //    indicator still occupied the list; the store clears the busy
    //    flag a beat AFTER appending the reply, the indicator row
    //    vanished, the content shrank, and the bottom-anchored
    //    position ended up short of the real bottom.
    // 3. ESTIMATE-BASED DECISION. Top vs. bottom was decided by a
    //    character-count guess (chars / 38 × 23pt) that ignored the
    //    avatar column and card insets; borderline replies judged
    //    "fits whole" got the bottom anchor while their real bubble
    //    was taller than the viewport — start off-screen, user scrolls
    //    up. Exactly the reported bug.
    // Plus: nothing re-anchored replies that arrived while the chat
    // was covered (call screen) or not yet on screen.
    //
    // The machine below fixes all of it: anchor decisively on arrival,
    // repeat the pass as layout settles (150 ms / 450 ms + whenever
    // the reply's measured height changes), decide top vs. bottom from
    // the MEASURED height, and stop forcing the moment the user grabs
    // the list — until the next reply arrives.

    /// Starts anchoring a freshly arrived reply: one animated pass
    /// now, then unanimated settle passes once the LazyVStack has
    /// realized the row and the typing indicator is gone.
    private func beginAnchoring(_ reply: ChatMessage, with proxy: ScrollViewProxy) {
        anchorGeneration += 1
        let generation = anchorGeneration
        anchorTargetID = reply.id
        anchorSuppressed = false
        handledReplyID = reply.id
        Haptics.light()
        performAnchorPass(reply, proxy: proxy, animated: true)
        for delayMilliseconds in [150, 450] {
            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: UInt64(delayMilliseconds) * 1_000_000
                )
                guard generation == anchorGeneration,
                      !anchorSuppressed,
                      store.messages.last?.id == reply.id else { return }
                performAnchorPass(reply, proxy: proxy, animated: false)
            }
        }
    }

    /// Stops all anchoring activity for the current target (a newer
    /// message or a conversation swap superseded it). Outstanding
    /// settle tasks die on their generation check.
    private func cancelAnchoring() {
        anchorGeneration += 1
        anchorTargetID = nil
        anchorSuppressed = false
    }

    /// One anchoring pass: replies that fit the visible area whole
    /// are bottom-anchored (fully visible, start included); longer
    /// replies are top-anchored so their FIRST line sits at the top
    /// of the message area and the user reads downward from there.
    /// The height is the row's measured height once the geometry
    /// reader has reported it, the text estimate only before that.
    private func performAnchorPass(
        _ reply: ChatMessage,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let height = rowHeights[reply.id] ?? estimatedReplyHeight(reply.text)
        let fitsWhole = viewportHeight > 0 && height <= viewportHeight - 16
        let scroll = {
            if fitsWhole {
                proxy.scrollTo(reply.id, anchor: .bottom)
            } else {
                proxy.scrollTo(reply.id, anchor: .top)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25), scroll)
        } else {
            scroll()
        }
    }

    /// Records a row's measured height. When the row is the current
    /// anchor target, a material change re-fires a (unanimated) pass:
    /// passes keep landing while the reply's rendered height moves —
    /// e.g. the stack realizing the row, or a bubble still growing —
    /// and the last change leaves the settled position in place.
    private func recordRowHeight(
        _ message: ChatMessage,
        height: CGFloat,
        proxy: ScrollViewProxy
    ) {
        if let previous = rowHeights[message.id] {
            guard abs(previous - height) > 1 else { return }
        }
        rowHeights[message.id] = height
        if message.id == anchorTargetID, !anchorSuppressed {
            performAnchorPass(message, proxy: proxy, animated: false)
        }
    }

    /// Rough height estimate for an assistant bubble (body font, ~23pt
    /// line height, 20pt vertical padding, ~38 characters per line at
    /// the chat's bubble width). Used ONLY until the row's measured
    /// height arrives (first settle passes); deliberately a touch
    /// generous: when in doubt the top anchor wins, because the one
    /// hard rule is that the reply's start must be visible.
    private func estimatedReplyHeight(_ text: String) -> CGFloat {
        let explicitBreaks = text.filter { $0 == "\n" }.count
        let wrappedLines = Double(text.count) / 38.0
        let lines = max(1.0, ceil(wrappedLines) + Double(explicitBreaks))
        return CGFloat(lines) * 23 + 20
    }

    /// Queues the current input (the message appears instantly; the call
    /// runs through the store's FIFO queue). The keyboard stays up for
    /// back-to-back typing — dragging the list dismisses it.
    private func sendCurrentInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        Haptics.light()
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
            AppBackdrop()
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
                    // Explicit close (swipe-down works too — nobody gets trapped).
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 32, height: 32)
                            .glassEffect(
                                .regular.tint(Palette.glassTint).interactive(),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
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
        .dismissKeyboardOnTap()
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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
