import SwiftUI

// MARK: - Companion characters ("Begleiter")

/// The four selectable companions — drawn purely with SwiftUI shapes
/// on a 100×100 canvas, scaled to any size. No image assets.
enum CompanionID: String, CaseIterable, Identifiable {
    case mochi
    case bit
    case neko
    case boo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mochi: return "Mochi"
        case .bit: return "Bit"
        case .neko: return "Neko"
        case .boo: return "Boo"
        }
    }

    /// Seconds between blinks (staggered per character so they feel alive).
    var blinkInterval: TimeInterval {
        switch self {
        case .mochi: return 3.4
        case .bit: return 4.3
        case .neko: return 3.9
        case .boo: return 4.6
        }
    }

    var blinkPhase: TimeInterval {
        switch self {
        case .mochi: return 0.0
        case .bit: return 1.1
        case .neko: return 0.6
        case .boo: return 2.0
        }
    }

    /// Seconds per idle bob cycle.
    var bobPeriod: TimeInterval {
        switch self {
        case .mochi: return 3.0
        case .bit: return 3.6
        case .neko: return 2.8
        case .boo: return 3.4
        }
    }
}

// MARK: - Companion view

/// Renders a companion at any size. Animated instances bob gently and blink;
/// the squash-bounce fires when `store.companionBounceTick` changes (the chat
/// bumps it whenever a new assistant reply arrives). Non-animated instances
/// (chat message rows) render one static frame — cheap.
struct CompanionView: View {
    @EnvironmentObject private var store: AppStore

    let character: CompanionID
    var size: CGFloat = 64
    var animated: Bool = true

    @State private var squash: CGFloat = 0

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: 0.05)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    canvas(
                        bob: CGFloat(sin(t * 2 * .pi / character.bobPeriod) * 1.5),
                        eyeOpen: CGFloat(eyeOpen(at: t))
                    )
                }
            } else {
                canvas(bob: 0, eyeOpen: 1)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: 1 + squash * 0.14, y: 1 - squash * 0.17, anchor: .bottom)
        .onChange(of: store.companionBounceTick) { _, _ in
            bounce()
        }
    }

    private func bounce() {
        guard animated else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.45)) {
            squash = 1
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.5).delay(0.15)) {
            squash = 0
        }
    }

    private func eyeOpen(at t: TimeInterval) -> Double {
        let cycle = (t + character.blinkPhase)
            .truncatingRemainder(dividingBy: character.blinkInterval)
        let blinkDuration = 0.22
        guard cycle < blinkDuration else { return 1 }
        let half = blinkDuration / 2
        if cycle < half {
            return 1 - (cycle / half) * 0.92
        }
        return 0.08 + ((cycle - half) / half) * 0.92
    }

    /// The 100×100 drawing canvas, scaled to `size`.
    private func canvas(bob: CGFloat, eyeOpen: CGFloat) -> some View {
        ZStack {
            switch character {
            case .mochi: mochiArt(eyeOpen: eyeOpen)
            case .bit: bitArt(eyeOpen: eyeOpen)
            case .neko: nekoArt(eyeOpen: eyeOpen)
            case .boo: booArt(eyeOpen: eyeOpen)
            }
        }
        .frame(width: 100, height: 100)
        .offset(y: bob)
        .scaleEffect(size / 100)
        .frame(width: size, height: size)
    }

    // MARK: Drawing helpers

    private func eye(width: CGFloat, height: CGFloat, color: Color,
                    x: CGFloat, y: CGFloat, open: CGFloat) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: width, height: height)
            .scaleEffect(y: max(0.08, open), anchor: .center)
            .position(x: x, y: y)
    }

    private func cheek(x: CGFloat, y: CGFloat) -> some View {
        Ellipse()
            .fill(Color(red: 0.949, green: 0.639, blue: 0.710).opacity(0.8))
            .frame(width: 13, height: 8)
            .position(x: x, y: y)
    }

    private func strokePath(color: Color, lineWidth: CGFloat, opacity: Double = 1,
                            _ build: @escaping (inout Path) -> Void) -> some View {
        Path(build)
            .stroke(
                color.opacity(opacity),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 100, height: 100)
    }

    // MARK: Mochi — cream blob

    private func mochiArt(eyeOpen: CGFloat) -> some View {
        let cream = Color(red: 0.969, green: 0.925, blue: 0.847)
        let outline = Color(red: 0.875, green: 0.804, blue: 0.651)
        let ink = Color(red: 0.145, green: 0.129, blue: 0.110)
        return ZStack {
            Circle()
                .fill(cream)
                .overlay(Circle().strokeBorder(outline, lineWidth: 1.5))
                .frame(width: 30, height: 30)
                .position(x: 31, y: 26)
            Circle()
                .fill(cream)
                .overlay(Circle().strokeBorder(outline, lineWidth: 1.5))
                .frame(width: 30, height: 30)
                .position(x: 69, y: 26)
            Ellipse()
                .fill(cream)
                .overlay(Ellipse().strokeBorder(outline, lineWidth: 1.5))
                .frame(width: 78, height: 70)
                .position(x: 50, y: 56)
            eye(width: 8, height: 11.5, color: ink, x: 38, y: 51, open: eyeOpen)
            eye(width: 8, height: 11.5, color: ink, x: 62, y: 51, open: eyeOpen)
            cheek(x: 26, y: 62)
            cheek(x: 74, y: 62)
            strokePath(color: ink, lineWidth: 2.2) { path in
                path.move(to: CGPoint(x: 44, y: 60))
                path.addQuadCurve(to: CGPoint(x: 56, y: 60),
                                  control: CGPoint(x: 50, y: 66.5))
            }
        }
    }

    // MARK: Bit — friendly robot

    private func bitArt(eyeOpen: CGFloat) -> some View {
        let steel = Color(red: 0.576, green: 0.655, blue: 0.737)
        let steelDark = Color(red: 0.431, green: 0.498, blue: 0.573)
        let plate = Color(red: 0.133, green: 0.188, blue: 0.243)
        let cyan = Color(red: 0.435, green: 0.890, blue: 0.949)
        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(steelDark)
                .frame(width: 3.5, height: 11)
                .position(x: 50, y: 15)
            Circle()
                .fill(cyan)
                .frame(width: 9, height: 9)
                .position(x: 50, y: 8)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(steelDark)
                .frame(width: 6, height: 14)
                .position(x: 15, y: 46)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(steelDark)
                .frame(width: 6, height: 14)
                .position(x: 85, y: 46)
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(steel)
                .frame(width: 64, height: 50)
                .position(x: 50, y: 45)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(plate)
                .frame(width: 54, height: 40)
                .position(x: 50, y: 45)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cyan)
                .frame(width: 8, height: 11)
                .scaleEffect(y: max(0.08, eyeOpen), anchor: .center)
                .position(x: 39, y: 43)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cyan)
                .frame(width: 8, height: 11)
                .scaleEffect(y: max(0.08, eyeOpen), anchor: .center)
                .position(x: 61, y: 43)
            strokePath(color: cyan.opacity(0.75), lineWidth: 2) { path in
                path.move(to: CGPoint(x: 44, y: 52))
                path.addQuadCurve(to: CGPoint(x: 56, y: 52),
                                  control: CGPoint(x: 50, y: 57.5))
            }
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(steelDark)
                .frame(width: 38, height: 22)
                .position(x: 50, y: 80)
            Circle()
                .fill(cyan.opacity(0.85))
                .frame(width: 8, height: 8)
                .position(x: 50, y: 80)
        }
    }

    // MARK: Neko — orange cat

    private func nekoArt(eyeOpen: CGFloat) -> some View {
        let orange = Color(red: 0.949, green: 0.647, blue: 0.290)
        let orangeDark = Color(red: 0.851, green: 0.514, blue: 0.180)
        let pink = Color(red: 0.949, green: 0.639, blue: 0.710)
        let ink = Color(red: 0.145, green: 0.129, blue: 0.110)
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 26, y: 38))
                path.addLine(to: CGPoint(x: 37, y: 10))
                path.addLine(to: CGPoint(x: 50, y: 32))
                path.closeSubpath()
                path.move(to: CGPoint(x: 74, y: 38))
                path.addLine(to: CGPoint(x: 63, y: 10))
                path.addLine(to: CGPoint(x: 50, y: 32))
                path.closeSubpath()
            }
            .fill(orange)
            .frame(width: 100, height: 100)
            Path { path in
                path.move(to: CGPoint(x: 31, y: 32))
                path.addLine(to: CGPoint(x: 37, y: 18))
                path.addLine(to: CGPoint(x: 44, y: 30))
                path.closeSubpath()
                path.move(to: CGPoint(x: 69, y: 32))
                path.addLine(to: CGPoint(x: 63, y: 18))
                path.addLine(to: CGPoint(x: 56, y: 30))
                path.closeSubpath()
            }
            .fill(pink)
            .frame(width: 100, height: 100)
            Ellipse()
                .fill(orange)
                .frame(width: 74, height: 60)
                .position(x: 50, y: 56)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(orangeDark)
                .frame(width: 3, height: 9)
                .rotationEffect(.degrees(-12))
                .position(x: 42, y: 33)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(orangeDark)
                .frame(width: 3, height: 9)
                .position(x: 50, y: 31)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(orangeDark)
                .frame(width: 3, height: 9)
                .rotationEffect(.degrees(12))
                .position(x: 58, y: 33)
            eye(width: 7.5, height: 10.5, color: ink, x: 37, y: 54, open: eyeOpen)
            eye(width: 7.5, height: 10.5, color: ink, x: 63, y: 54, open: eyeOpen)
            Ellipse()
                .fill(Color(red: 0.871, green: 0.420, blue: 0.455))
                .frame(width: 6, height: 4.5)
                .position(x: 50, y: 62)
            strokePath(color: ink, lineWidth: 1.8) { path in
                path.move(to: CGPoint(x: 50, y: 64))
                path.addQuadCurve(to: CGPoint(x: 44.5, y: 67.5),
                                  control: CGPoint(x: 47, y: 68.5))
                path.move(to: CGPoint(x: 50, y: 64))
                path.addQuadCurve(to: CGPoint(x: 55.5, y: 67.5),
                                  control: CGPoint(x: 53, y: 68.5))
            }
            strokePath(color: ink, lineWidth: 1.6, opacity: 0.4) { path in
                path.move(to: CGPoint(x: 6, y: 55))
                path.addLine(to: CGPoint(x: 25, y: 57.5))
                path.move(to: CGPoint(x: 7, y: 63))
                path.addLine(to: CGPoint(x: 25, y: 62))
                path.move(to: CGPoint(x: 9, y: 47))
                path.addLine(to: CGPoint(x: 26, y: 50.5))
                path.move(to: CGPoint(x: 94, y: 55))
                path.addLine(to: CGPoint(x: 75, y: 57.5))
                path.move(to: CGPoint(x: 93, y: 63))
                path.addLine(to: CGPoint(x: 75, y: 62))
                path.move(to: CGPoint(x: 91, y: 47))
                path.addLine(to: CGPoint(x: 74, y: 50.5))
            }
        }
    }

    // MARK: Boo — little ghost

    private func booArt(eyeOpen: CGFloat) -> some View {
        let fill = Color(red: 0.988, green: 0.984, blue: 0.973)
        let outline = Color(red: 0.847, green: 0.816, blue: 0.902)
        let ink = Color(red: 0.216, green: 0.196, blue: 0.290)
        let bodyPath = Path { path in
            path.move(to: CGPoint(x: 22, y: 86))
            path.addLine(to: CGPoint(x: 22, y: 50))
            path.addQuadCurve(to: CGPoint(x: 78, y: 50),
                              control: CGPoint(x: 50, y: 4))
            path.addLine(to: CGPoint(x: 78, y: 86))
            path.addQuadCurve(to: CGPoint(x: 59, y: 86),
                              control: CGPoint(x: 68.5, y: 76))
            path.addQuadCurve(to: CGPoint(x: 41, y: 86),
                              control: CGPoint(x: 50, y: 96))
            path.addQuadCurve(to: CGPoint(x: 22, y: 86),
                              control: CGPoint(x: 31.5, y: 76))
            path.closeSubpath()
        }
        return ZStack {
            Ellipse()
                .fill(fill)
                .overlay(Ellipse().strokeBorder(outline, lineWidth: 1.2))
                .frame(width: 14, height: 8)
                .rotationEffect(.degrees(-25))
                .position(x: 18, y: 67)
            Ellipse()
                .fill(fill)
                .overlay(Ellipse().strokeBorder(outline, lineWidth: 1.2))
                .frame(width: 14, height: 8)
                .rotationEffect(.degrees(25))
                .position(x: 82, y: 67)
            bodyPath
                .fill(fill)
                .frame(width: 100, height: 100)
            bodyPath
                .stroke(outline, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 100, height: 100)
            eye(width: 8, height: 11, color: ink, x: 38, y: 52, open: eyeOpen)
            eye(width: 8, height: 11, color: ink, x: 62, y: 52, open: eyeOpen)
            Ellipse()
                .fill(ink)
                .frame(width: 7, height: 9)
                .position(x: 50, y: 65)
            cheek(x: 28, y: 64)
            cheek(x: 72, y: 64)
        }
    }
}
