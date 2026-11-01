import SwiftUI

/// Ideas tab: built-in + custom idea cards with save/dismiss, plus a sheet
/// to add your own idea — Liquid Glass cards on the black backdrop.
struct IdeasView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewIdea = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    SidebarButton()
                    VStack(alignment: .leading, spacing: 4) {
                        ScreenTitle(text: "Ideen")
                        Text("Speichere, was dich anspricht — der Rest fliegt raus.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Button {
                        showingNewIdea = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Neue Idee")
                        }
                        .accentCapsule()
                    }
                    .buttonStyle(.plain)
                }

                if store.visibleIdeas.isEmpty {
                    EmptyStateCard(
                        icon: "lightbulb.slash",
                        title: "Alles verworfen — stark.",
                        text: "Leg oben eine eigene Idee an, wenn dir etwas Neues einfällt."
                    )
                } else {
                    ForEach(store.visibleIdeas) { idea in
                        ideaCard(idea)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .sheet(isPresented: $showingNewIdea) {
            NewIdeaSheet()
        }
    }

    private func ideaCard(_ idea: Idea) -> some View {
        let savedItem = SavedItem(id: "idea:\(idea.id)", title: idea.title, subtitle: idea.text, kind: "Idee")
        let isSaved = store.isSaved(id: savedItem.id)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(idea.category.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glassCapsuleBackground()
                    Spacer()
                    BookmarkButton(item: savedItem)
                }
                Text(idea.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(idea.text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                HStack(spacing: 10) {
                    Button {
                        store.toggleSaved(savedItem)
                    } label: {
                        HStack(spacing: 6) {
                            if isSaved {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(isSaved ? "Gespeichert" : "Speichern")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSaved ? .white : Palette.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(isSaved ? Palette.success : Palette.primaryFill))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.dismissIdea(idea)
                    } label: {
                        Text("Verwerfen")
                            .hairlineCapsule()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - New idea sheet

struct NewIdeaSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(text: "Neue Idee")
                    FieldLabel(text: "Titel")
                    TextField("z. B. Balkon-Kino bauen", text: $title)
                        .focused($isFieldFocused)
                        .appField()
                    FieldLabel(text: "Beschreibung")
                    TextField("Worum geht's?", text: $text, axis: .vertical)
                        .focused($isFieldFocused)
                        .lineLimit(3...6)
                        .appField()
                    Button("Idee speichern") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmedTitle.isEmpty else { return }
                        isFieldFocused = false
                        store.customIdeas.append(Idea(
                            id: "custom-\(UUID().uuidString)",
                            title: trimmedTitle,
                            text: text.trimmingCharacters(in: .whitespaces),
                            category: "Eigene"
                        ))
                        dismiss()
                    }
                    .accentBlock()
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    Button("Abbrechen") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
    }
}
