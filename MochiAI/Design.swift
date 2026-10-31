import SwiftUI

// MARK: - Palette

enum Palette {
    static let lavender = Color(red: 0.82, green: 0.74, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.42, blue: 0.98)
    static let accentText = Color(red: 0.90, green: 0.84, blue: 1.0)
}

// MARK: - Animated full-bleed background

/// Violet/indigo gradient with slow-drifting color glows — the color is
/// what the Liquid Glass above it refracts.
struct AppBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.08, blue: 0.38),
                    Color(red: 0.11, green: 0.06, blue: 0.30),
                    Color(red: 0.05, green: 0.09, blue: 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.62, green: 0.32, blue: 0.98).opacity(0.35))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: drift ? 70 : -50, y: drift ? -300 : -230)
            Circle()
                .fill(Color(red: 0.92, green: 0.36, blue: 0.78).opacity(0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: drift ? -120 : -60, y: drift ? 260 : 330)
            Circle()
                .fill(Color(red: 0.28, green: 0.52, blue: 1.0).opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 95)
                .offset(x: drift ? 130 : 80, y: drift ? 380 : 300)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Orb avatar

/// Glossy AI orb drawn purely in SwiftUI: gradient sphere, inner bubbles
/// and a specular highlight.
struct OrbView: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.86, green: 0.80, blue: 1.0),
                            Color(red: 0.60, green: 0.46, blue: 0.99),
                            Color(red: 0.40, green: 0.27, blue: 0.85),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 1,
                        endRadius: size * 0.72
                    )
                )
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: size * 0.26, height: size * 0.26)
                .offset(x: size * 0.15, y: size * 0.12)
                .blur(radius: size * 0.03)
            Circle()
                .fill(Color.white.opacity(0.30))
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: -size * 0.17, y: size * 0.22)
                .blur(radius: size * 0.025)
            Ellipse()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.30, height: size * 0.16)
                .offset(x: -size * 0.15, y: -size * 0.25)
                .blur(radius: size * 0.04)
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.55, green: 0.40, blue: 0.95).opacity(0.55), radius: size * 0.16, y: size * 0.05)
    }
}

// MARK: - Glass building blocks

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    let content: Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .default).weight(.black))
            .foregroundStyle(.white)
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.6))
    }
}

extension View {
    /// Shared styling for text fields sitting on glass.
    func glassField() -> some View {
        self
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
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
                .foregroundStyle(Palette.accentText)
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
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    Color(red: 0.80, green: 0.68, blue: 1.0),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
