import SwiftUI
import UIKit

// MARK: - Palette (warm paper, Claude-inspired, follows system appearance)

enum Palette {
    /// Terracotta accent — buttons, active states, rings, links.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757

    /// Screen background: warm paper / warm near-black.
    static let paper = dynamic(light: 0xF7F4EF, dark: 0x1B1A18)
    /// Card surface.
    static let card = dynamic(light: 0xFDFBF7, dark: 0x262422)
    /// Primary text.
    static let ink = dynamic(light: 0x201D1A, dark: 0xF2EEE7)
    /// Secondary / muted text.
    static let secondaryText = dynamic(light: 0x71695D, dark: 0xA89F92)
    /// Hairline borders (black 8% / white 10%).
    static let hairline = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    /// Subtle neutral fill: user chat bubble, chips, inset fields.
    static let subtleFill = dynamic(light: 0xECE7DD, dark: 0x2C2A27)
    /// Success / saved state.
    static let success = Color(red: 0.30, green: 0.62, blue: 0.38)
    /// Destructive text.
    static let danger = Color(red: 0.82, green: 0.34, blue: 0.30)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamicColor(light: uiColor(light), dark: uiColor(dark))
    }

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Shared surfaces

extension View {
    /// Flat card: solid surface, hairline border, very subtle shadow. No glass.
    func cardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.045), radius: 10, y: 3)
    }

    /// Clean text-field styling: solid inset fill, hairline border.
    func appField(cornerRadius: CGFloat = 12) -> some View {
        self
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }

    /// Accent-filled capsule label (primary small buttons).
    func accentCapsule() -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.accent))
    }

    /// Accent-filled full-width block label (primary sheet buttons).
    func accentBlock() -> some View {
        self
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accent))
    }

    /// Hairline-bordered capsule label (secondary small buttons).
    func hairlineCapsule() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.card))
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// Padded flat card container (replaces the old glass card).
struct Card<Content: View>: View {
    var cornerRadius: CGFloat = 20
    let content: Content

    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .cardStyle(cornerRadius: cornerRadius)
    }
}

// MARK: - Typography helpers

/// Big serif screen title (Claude vibe).
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .serif).weight(.bold))
            .foregroundStyle(Palette.ink)
    }
}

/// Serif section/card title.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .serif).weight(.bold))
            .foregroundStyle(Palette.ink)
    }
}

/// Small-caps gray label (field labels + section headers).
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.0)
            .foregroundStyle(Palette.secondaryText)
    }
}

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
