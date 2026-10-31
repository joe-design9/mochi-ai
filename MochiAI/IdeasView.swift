import SwiftUI

/// Ideas tab: built-in + custom idea cards with save/dismiss, plus a sheet
/// to add your own idea.
struct IdeasView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewIdea = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "Ideen")
                        Text("Speichere, was dich anspricht — der Rest fliegt raus.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button {
                        showingNewIdea = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Neue Idee")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if store.visibleIdeas.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "lightbulb.slash")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Alles verworfen — stark. Leg oben eine eigene Idee an.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(store.visibleIdeas) { idea in
                        ideaCard(idea)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingNewIdea) {
            NewIdeaSheet()
        }
    }

    private func ideaCard(_ idea: Idea) -> some View {
        let savedItem = SavedItem(id: "idea:\(idea.id)", title: idea.title, subtitle: idea.text, kind: "Idee")
        let isSaved = store.isSaved(id: savedItem.id)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(idea.category.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(1.0)
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Spacer()
                    BookmarkButton(item: savedItem)
                }
                Text(idea.title)
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundStyle(.white)
                Text(idea.text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 10) {
                    Button {
                        store.toggleSaved(savedItem)
                    } label: {
                        Text(isSaved ? "Gespeichert" : "Speichern")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(
                                    isSaved
                                        ? Color(red: 0.30, green: 0.62, blue: 0.38)
                                        : Color(red: 0.55, green: 0.38, blue: 0.95)
                                )
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.dismissIdea(idea)
                    } label: {
                        Text("Verwerfen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
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

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Neue Idee")
                        .font(.system(.title2, design: .default).weight(.black))
                        .foregroundStyle(.white)
                    FieldLabel(text: "TITEL")
                    TextField("z. B. Balkon-Kino bauen", text: $title)
                        .glassField()
                    FieldLabel(text: "BESCHREIBUNG")
                    TextField("Worum geht's?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .glassField()
                    Button("Idee speichern") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmedTitle.isEmpty else { return }
                        store.customIdeas.append(Idea(
                            id: "custom-\(UUID().uuidString)",
                            title: trimmedTitle,
                            text: text.trimmingCharacters(in: .whitespaces),
                            category: "Eigene"
                        ))
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    Button("Abbrechen") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }
}
