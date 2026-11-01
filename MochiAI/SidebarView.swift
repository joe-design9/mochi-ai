import SwiftUI

/// Nova v3.0.0 — the Muse-app-style slide-over sidebar. It replaces
/// the old bottom TabView: the chat is the home screen, and this
/// panel (opened from every section's header button or a left-edge
/// swipe) carries the navigation — agent header on top, the TABS
/// section (Main Chat / Feed / Ideen / Ziele / Bibliothek), the
/// VERLÄUFE list of past chat threads below it, and at the bottom
/// the search field with the compose (new chat) and gear
/// (Bibliothek) buttons, like the reference.
///
/// Everything is the proven glass recipe — real .glassEffect with
/// the neutral tint and the shared rim — over the black backdrop;
/// rows stagger in with a soft fade/slide when the panel opens.
struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var appeared = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tabsSection
                    historySection
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .glassEffect(
            .regular.tint(Palette.glassTint),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .glassRim(cornerRadius: 28)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
        .dismissKeyboardOnTap()
    }

    // MARK: Header — companion, name, active engine

    private var header: some View {
        HStack(spacing: 11) {
            CompanionGlow(character: store.companion, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nova")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(store.engineLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seitenleiste schließen")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: TABS

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Tabs")
                .padding(.horizontal, 8)
            tabRow(tab: .chat, icon: "message.fill", title: "Main Chat", index: 0)
            tabRow(tab: .feed, icon: "newspaper.fill", title: "Feed", index: 1)
            tabRow(tab: .ideas, icon: "lightbulb.fill", title: "Ideen", index: 2)
            tabRow(tab: .goals, icon: "target", title: "Ziele", index: 3)
            tabRow(tab: .library, icon: "books.vertical.fill", title: "Bibliothek", index: 4)
        }
    }

    private func tabRow(tab: AppStore.Tab, icon: String, title: String, index: Int) -> some View {
        let selected = store.selectedTab == tab
        return Button {
            store.selectedTab = tab
            close()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Palette.primaryText : Palette.ink)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? Palette.primaryText : Palette.ink)
                Spacer()
                if selected {
                    Circle()
                        .fill(Palette.primaryText)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.primaryFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -14)
        .animation(.easeOut(duration: 0.3).delay(0.04 * Double(index)), value: appeared)
    }

    // MARK: VERLÄUFE (past threads)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Verläufe")
                .padding(.horizontal, 8)
            if filteredHistory.isEmpty {
                Text(searchText.isEmpty
                     ? "Noch keine Verläufe. Sobald du im Chat schreibst, landen deine Unterhaltungen hier."
                     : "Keine Treffer für „\(searchText)“.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, conversation in
                    historyRow(conversation)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared ? 0 : -14)
                        .animation(.easeOut(duration: 0.3).delay(0.2 + 0.03 * Double(index)), value: appeared)
                }
            }
        }
    }

    private func historyRow(_ conversation: Conversation) -> some View {
        let isActive = conversation.id == store.activeConversationID
        return Button {
            store.switchConversation(to: conversation.id)
            store.selectedTab = .chat
            close()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.subheadline.weight(isActive ? .bold : .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(conversation.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if isActive {
                    Text("Aktiv")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassCapsuleBackground()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassCard(cornerRadius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteConversation(id: conversation.id)
            } label: {
                Label("Chat löschen", systemImage: "trash")
            }
        }
    }

    private var filteredHistory: [Conversation] {
        let all = store.historyConversations
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: Bottom bar — search + compose + gear (like the reference)

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Suchen").foregroundColor(Palette.secondaryText)
                )
                .focused($searchFocused)
                .foregroundStyle(Palette.ink)
                .tint(Palette.accent)
                .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(
                .regular.tint(Palette.glassTint),
                in: Capsule()
            )

            Button {
                store.startNewConversation()
                store.selectedTab = .chat
                close()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(
                        .regular.tint(Palette.glassTint).interactive(),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Neuer Chat")

            Button {
                store.selectedTab = .library
                close()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(
                        .regular.tint(Palette.glassTint).interactive(),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func close() {
        searchFocused = false
        store.isSidebarOpen = false
    }
}
