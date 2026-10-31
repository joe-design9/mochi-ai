import SwiftUI

// Shared small components. The theme itself (palette, Liquid Glass
// styles, typography, backdrop) lives in Theme.swift.

// MARK: - Bookmark toggle (Feed & Ideas)

struct BookmarkButton: View {
    @EnvironmentObject private var store: AppStore
    let item: SavedItem

    var body: some View {
        Button {
            store.toggleSaved(item)
        } label: {
            Image(systemName: store.isSaved(id: item.id) ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(store.isSaved(id: item.id) ? Palette.accent : Palette.secondaryText)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state (Ideas / Goals / Library)

/// One consistent empty-state card for the tabs: a neutral Liquid
/// Glass disc with the icon (the same visual grammar as the call
/// screen's companion disc), a rounded title and a muted explanation.
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        Card {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .glassEffect(
                            .regular.tint(Palette.glassTint),
                            in: Circle()
                        )
                        .frame(width: 62, height: 62)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Progress ring (Goals)

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.subtleFill, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    Palette.accent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: size, height: size)
    }
}
