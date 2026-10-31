import SwiftUI
import UIKit

// MARK: - Palette (Muse/Mochi identity: deep ink-plum + pink→violet Vice glow)
//
// Dark mode is the hero: deep plum surfaces, pink-violet gradient accents,
// real Liquid Glass cards over a softly glowing backdrop. Light mode maps
// to a soft lilac-white with the same accent family. No terracotta, no
// paper/cream, no serif — SF Rounded headings, plain sans body.

enum Palette {
    /// Pink→violet gradient endpoints (brand accent).
    static let accentPink = Color(red: 0.910, green: 0.475, blue: 0.776)   // #E879C6
    static let accentViolet = Color(red: 0.545, green: 0.486, blue: 0.965) // #8B7CF6

    /// The brand gradient: send button, primary buttons, highlights.
    static let accentGradient = LinearGradient(
        colors: [accentPink, accentViolet],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Solid accent for small text/icons (links, checkmarks, active states).
    static let accent = dynamic(light: 0x7A5AF8, dark: 0xB79CFF)

    /// Screen base behind the glows: deep ink-plum / soft lilac-white.
    static let paper = dynamic(light: 0xF3EFFC, dark: 0x17131F)
    /// Elevated solid surface (fallbacks, picker checkmark backing).
    static let card = dynamic(light: 0xFDFCFF, dark: 0x221C2E)
    /// Solid fill for text fields (glass or solid only — never a material).
    static let fieldFill = dynamic(light: 0xFFFFFF, dark: 0x2A2140)
    /// Primary text.
    static let ink = dynamic(light: 0x251B36, dark: 0xF5F1FC)
    /// Secondary / muted text (lavender gray).
    static let secondaryText = dynamic(light: 0x6E6390, dark: 0xB3A8CF)
    /// Hairline borders: violet-tinted.
    static let hairline = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.14)
    )
    /// Subtle neutral fill: chips, inset areas, progress-ring track.
    static let subtleFill = dynamic(light: 0xE6DEF9, dark: 0x322A4D)
    /// Tint for the Liquid Glass surfaces (violet, translucent).
    static let glassTint = dynamicColor(
        light: UIColor(white: 1, alpha: 0.42),
        dark: UIColor(red: 0.16, green: 0.12, blue: 0.27, alpha: 0.52)
    )
    /// Tint for user chat bubbles: accent-washed glass.
    static let userBubbleTint = dynamicColor(
        light: UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 0.20),
        dark: UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 0.34)
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

// MARK: - Backdrop (static Vice-style glows over the plum base — cheap:
// three radial gradients, no blur stacks, no animation)
//
// LAYOUT SAFETY (v2.0.1 fix): the backdrop must NEVER take part in the
// layout of anything around it. The v2.0.0 version put 520–640pt circles
// in a plain ZStack — the stack sized itself to its largest child, the
// root view inflated well beyond the screen, and all sibling content
// (header, greeting, input bar) laid out against that inflated width
// and clipped on both edges. Now the backdrop lives in a GeometryReader
// sized exactly to the screen: glow circles are placed with .position()
// inside that fixed frame and clipped, so their size can never
// propagate into any parent layout.

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dark = colorScheme == .dark
            // One generous glow diameter, derived from the screen only.
            let glow = max(size.width, size.height) * 1.25
            ZStack {
                Palette.paper
                // Pink glow, top-left — the main color wash.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Palette.accentPink.opacity(dark ? 0.58 : 0.38),
                            Palette.accentViolet.opacity(dark ? 0.20 : 0.12),
                            .clear,
                        ],
                        center: .center, startRadius: 0, endRadius: glow / 2
                    ))
                    .frame(width: glow, height: glow)
                    .position(x: size.width * 0.08, y: size.height * 0.02)
                // Violet glow, right edge, upper-middle.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Palette.accentViolet.opacity(dark ? 0.52 : 0.34),
                            Palette.accentPink.opacity(dark ? 0.16 : 0.10),
                            .clear,
                        ],
                        center: .center, startRadius: 0, endRadius: glow / 2
                    ))
                    .frame(width: glow, height: glow)
                    .position(x: size.width * 1.02, y: size.height * 0.44)
                // Pink glow, bottom — keeps the lower half warm too.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Palette.accentPink.opacity(dark ? 0.34 : 0.22),
                            .clear,
                        ],
                        center: .center, startRadius: 0, endRadius: glow / 2
                    ))
                    .frame(width: glow, height: glow)
                    .position(x: size.width * 0.22, y: size.height * 1.04)
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
    /// Real Liquid Glass card surface (violet-tinted regular glass).
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        glassEffect(
            .regular.tint(Palette.glassTint),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// Clean text-field styling: solid elevated fill, hairline border.
    func appField(cornerRadius: CGFloat = 12) -> some View {
        self
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }

    /// Gradient-filled capsule label (primary small buttons).
    func accentCapsule() -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.accentGradient))
    }

    /// Gradient-filled full-width block label (primary sheet buttons).
    func accentBlock() -> some View {
        self
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.accentGradient)
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

// MARK: - Companion with brand glow halo

/// The companion is the brand element: a soft pink→violet radial halo
/// behind it so it pops on the plum backdrop (empty state, headers,
/// onboarding). The halo is a static radial gradient — no blur, no loop.
struct CompanionGlow: View {
    let character: CompanionID
    var size: CGFloat = 64
    var animated: Bool = true

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
                        colors: [
                            Palette.accentPink.opacity(0.55),
                            Palette.accentViolet.opacity(0.26),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.95
                    ))
                    .frame(width: size * 1.9, height: size * 1.9)
                    .allowsHitTesting(false)
            }
    }
}
