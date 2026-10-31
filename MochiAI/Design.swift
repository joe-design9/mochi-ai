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
