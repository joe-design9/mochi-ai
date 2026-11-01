import SwiftUI
import UIKit

// MARK: - Palette (Nova identity: monochrome — pure black + neutral glass)
//
// The real Muse app's dark UI: a pure-black canvas, neutral/clear Liquid
// Glass surfaces on top, white as the only "accent". NO hue anywhere in
// the UI chrome — no pink, no violet, no blue, no gradient hues. (The
// companion characters' artwork keeps its own colors; that's the mascot,
// not the palette.) Light mode is the same system in clean white /
// light-gray monochrome. SF Rounded headings, plain sans body.

enum Palette {
    /// The monochrome accent: links, checkmarks, active states, the
    /// progress ring. White on black (dark) / near-black on white (light).
    static let accent = dynamic(light: 0x111113, dark: 0xFFFFFF)

    /// Primary-button fill (send button, primary capsules/blocks):
    /// solid white in dark mode, solid near-black in light mode.
    static let primaryFill = dynamic(light: 0x111113, dark: 0xFFFFFF)
    /// Glyph/text color on top of `primaryFill`.
    static let primaryText = dynamic(light: 0xFFFFFF, dark: 0x000000)

    /// Screen base: pure black (dark) / clean light gray (light).
    static let paper = dynamic(light: 0xF4F4F6, dark: 0x000000)
    /// Elevated solid surface (fallbacks, picker checkmark backing).
    static let card = dynamic(light: 0xFFFFFF, dark: 0x131315)
    /// Legacy solid field fill — text fields are real Liquid Glass
    /// since v2.4.0 (appField); kept only as a solid fallback token.
    static let fieldFill = dynamic(light: 0xFFFFFF, dark: 0x1B1B1E)
    /// Primary text.
    static let ink = dynamic(light: 0x131315, dark: 0xF5F5F7)
    /// Secondary / muted text (neutral gray).
    static let secondaryText = dynamic(light: 0x6E6E73, dark: 0xA7A7AD)
    /// Hairline borders: neutral.
    static let hairline = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.14)
    )
    /// Subtle neutral fill: chips, inset areas, progress-ring track.
    static let subtleFill = dynamic(light: 0xE9E9ED, dark: 0x26262A)
    /// Tint for the Liquid Glass surfaces: neutral smoky glass.
    static let glassTint = dynamicColor(
        light: UIColor(white: 1, alpha: 0.55),
        dark: UIColor(white: 0.08, alpha: 0.52)
    )
    /// Tint for user chat bubbles: slightly brighter neutral glass.
    static let userBubbleTint = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.16)
    )
    /// Top edge of the glass highlight stroke (bright, fades downward).
    static let glassHighlightTop = dynamicColor(
        light: UIColor(white: 1, alpha: 0.85),
        dark: UIColor(white: 1, alpha: 0.30)
    )
    /// Bottom edge of the glass highlight stroke (nearly gone).
    static let glassHighlightBottom = dynamicColor(
        light: UIColor(white: 1, alpha: 0.25),
        dark: UIColor(white: 1, alpha: 0.04)
    )
    /// Success / saved state.
    static let success = dynamic(light: 0x2F9E44, dark: 0x5BD97A)
    /// Destructive text.
    static let danger = dynamic(light: 0xD64541, dark: 0xFF8A7A)

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

// MARK: - Backdrop (pure black canvas + an extremely subtle NEUTRAL
// sheen — monochrome only, no hue; just enough depth for the glass
// above it to refract, like the real Muse app's dark UI)
//
// LAYOUT SAFETY (v2.0.1 fix, kept): the backdrop must NEVER take part
// in the layout of anything around it. The v2.0.0 version put
// 520–640pt glow circles in a plain ZStack — the stack sized itself to
// its largest child, the root view inflated well beyond the screen, and
// all sibling content (header, greeting, input bar) laid out against
// that inflated width and clipped on both edges. The backdrop lives in
// a GeometryReader sized exactly to the screen: the sheen circles are
// placed with .position() inside that fixed frame and clipped, so
// their size can never propagate into any parent layout.

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dark = colorScheme == .dark
            // One generous sheen diameter, derived from the screen only.
            let sheen = max(size.width, size.height) * 1.15
            ZStack {
                Palette.paper
                // Neutral sheen, top — a whisper of gray light on the
                // black canvas (in light mode: white on light gray).
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color.white.opacity(dark ? 0.075 : 0.55),
                            .clear,
                        ],
                        center: .center, startRadius: 0, endRadius: sheen / 2
                    ))
                    .frame(width: sheen, height: sheen)
                    .position(x: size.width * 0.5, y: size.height * -0.06)
                // Fainter counter-sheen, bottom-right, for depth.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color.white.opacity(dark ? 0.04 : 0.35),
                            .clear,
                        ],
                        center: .center, startRadius: 0, endRadius: sheen / 2
                    ))
                    .frame(width: sheen, height: sheen)
                    .position(x: size.width * 0.9, y: size.height * 1.02)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass surfaces & shared styles
//
// STRICT RULE (user demand): real Liquid Glass (.glassEffect) or a solid
// color — never .ultraThinMaterial or any other material fallback.

extension View {
    /// The light-catching rim shared by every glass surface: a 1pt
    /// highlight stroke that is bright at the top edge and fades
    /// downward. This rim is what makes glass read as glass over the
    /// pure-black canvas — a tinted shape WITHOUT it reads as a flat
    /// fill (v2.3.0 device feedback: header, user bubbles).
    func glassRim(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Palette.glassHighlightTop, Palette.glassHighlightBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    /// Real Liquid Glass card surface: neutral smoky regular glass
    /// plus the shared rim (a plain gradient stroke, NOT a material).
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        glassEffect(
            .regular.tint(Palette.glassTint),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .glassRim(cornerRadius: cornerRadius)
    }

    /// Backs the view with a small real-Liquid-Glass capsule incl.
    /// rim — chips and cells (v2.4.0: replaces the flat subtleFill
    /// capsules, which read as solid plastic in dark mode).
    func glassCapsuleBackground() -> some View {
        background {
            Capsule()
                .glassEffect(
                    .regular.tint(Palette.glassTint),
                    in: Capsule()
                )
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Palette.glassHighlightTop, Palette.glassHighlightBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    /// Text-field styling: a real Liquid Glass surface (v2.4.0 —
    /// the old solid fieldFill read as a flat dark-gray block in
    /// dark mode, exactly what the user flagged on the composer;
    /// fields are glass everywhere now, never a solid fill).
    func appField(cornerRadius: CGFloat = 12) -> some View {
        self
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .glassEffect(
                        .regular.tint(Palette.glassTint),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .glassRim(cornerRadius: cornerRadius)
    }

    /// Solid monochrome capsule label (primary small buttons): white
    /// fill + black text in dark mode, inverted in light mode.
    func accentCapsule() -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.primaryFill))
    }

    /// Solid monochrome full-width block label (primary sheet buttons).
    func accentBlock() -> some View {
        self
            .font(.headline.weight(.semibold))
            .foregroundStyle(Palette.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.primaryFill)
            )
    }

    /// Interactive Liquid Glass capsule label (secondary small buttons).
    func hairlineCapsule() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(
                .regular.tint(Palette.glassTint).interactive(),
                in: Capsule()
            )
    }
}

/// Padded Liquid Glass card container.
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
            .glassCard(cornerRadius: cornerRadius)
    }
}

// MARK: - Typography (SF Rounded headings, plain sans body)

/// Big rounded screen title.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundStyle(Palette.ink)
    }
}

/// Rounded section/card title.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded).weight(.bold))
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

// MARK: - Sidebar button (v3.0.0)

/// Opens the Nova sidebar — the leading button of every section
/// header (chat, feed, ideas, goals, library), one consistent glass
/// circle everywhere.
struct SidebarButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.isSidebarOpen = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38)
                .glassEffect(
                    .regular.tint(Palette.glassTint).interactive(),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seitenleiste öffnen")
    }
}

// MARK: - Companion with neutral light halo

/// The companion is the brand element: a whisper of neutral light
/// behind it so the mascot lifts off the black canvas (empty state,
/// headers, onboarding). Monochrome like everything else — the
/// character's own artwork colors are the only colors here. The halo
/// is a static radial gradient — no blur, no loop.
struct CompanionGlow: View {
    let character: CompanionID
    var size: CGFloat = 64
    var animated: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The halo is background content: background views never change
        // the size of the view they back, so the oversized glow circle
        // (1.9×) is purely decorative and cannot inflate any layout.
        // The gradient reaches .clear exactly at the halo's edge, so
        // nothing visible extends past its fixed frame. (v2.0.1: this
        // was a ZStack child — same layout-safety rule as AppBackdrop.)
        CompanionView(character: character, size: size, animated: animated)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(RadialGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.13), Color.white.opacity(0.04), .clear]
                            : [Color.black.opacity(0.05), Color.black.opacity(0.02), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.95
                    ))
                    .frame(width: size * 1.9, height: size * 1.9)
                    .allowsHitTesting(false)
            }
    }
}
