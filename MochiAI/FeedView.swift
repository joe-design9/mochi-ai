import SwiftUI

/// Feed tab: greeting row with companion, countdown, profile vibes,
/// daily card, casino promo, idea teaser — Liquid Glass cards, rounded
/// titles, monochrome on the black backdrop.
struct FeedView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greetingRow
                CountdownCard()
                vibesCard
                dailyCard
                casinoCard
                ideaTeaserCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }

    // MARK: Greeting

    private var greetingRow: some View {
        HStack(spacing: 12) {
            CompanionGlow(character: store.companion, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hallo, \(store.profile?.name ?? "Freund")")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text("Dein Feed — gebaut für dich.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
        }
    }

    // MARK: Vibes

    private var vibesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(
                    icon: "sparkles",
                    title: "Deine Vibes",
                    bookmark: SavedItem(id: "feed:vibes", title: "Deine Vibes",
                                        subtitle: "Dein Profil auf einen Blick", kind: "Feed")
                )
                if let profile = store.profile {
                    vibeRow(icon: "person.fill", text: "Name: \(profile.name)")
                    vibeRow(icon: "moon.stars.fill", text: "Entspannung: \(profile.relax)")
                    vibeRow(icon: "heart.fill", text: "Hobby: \(profile.hobby)")
                    vibeRow(icon: "airplane", text: "Teleport-Ziel: \(profile.teleport)")
                }
            }
        }
    }

    private func vibeRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            Spacer()
        }
    }

    // MARK: Daily

    private var dailyCard: some View {
        let daily = DailyPool.today()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "sun.max.fill",
                    title: daily.title,
                    bookmark: SavedItem(id: "feed:daily", title: daily.title,
                                        subtitle: daily.text, kind: "Feed")
                )
                Text(daily.text)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    // MARK: Casino promo

    private var casinoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "die.face.5.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Muse Royal Casino")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("APP")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Palette.primaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.primaryFill))
                    Spacer()
                    BookmarkButton(item: SavedItem(id: "feed:casino", title: "Muse Royal Casino",
                                                   subtitle: "32 Slots warten — nur Spielgeld", kind: "Feed"))
                }
                Text("32 Slots warten auf dich — von Book of Muse bis Leonida Nights. Nur Spielgeld, kein Echtgeld, aber mit echtem Casino-Sound.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    // MARK: Idea teaser

    private var ideaTeaserCard: some View {
        let idea = teaserIdea
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "lightbulb.fill",
                    title: "Idee des Tages",
                    bookmark: SavedItem(id: "idea:\(idea.id)", title: idea.title,
                                        subtitle: idea.text, kind: "Idee")
                )
                Text(idea.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(idea.text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                Button {
                    store.selectedTab = .ideas
                } label: {
                    HStack(spacing: 6) {
                        Text("Zu den Ideen")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .accentCapsule()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var teaserIdea: Idea {
        let ideas = store.visibleIdeas
        guard !ideas.isEmpty else { return IdeaPool.all[0] }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return ideas[day % ideas.count]
    }

    // MARK: Shared header

    private func cardHeader(icon: String, title: String, bookmark: SavedItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            BookmarkButton(item: bookmark)
        }
    }
}

// MARK: - Countdown card (own view: the 1-second TimelineView re-renders
// only this card, never the rest of the feed)

private struct CountdownCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("GTA 6 Countdown")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    BookmarkButton(item: SavedItem(id: "feed:countdown", title: "GTA 6 Countdown",
                                                   subtitle: "Release am 19. November 2026 in Leonida", kind: "Feed"))
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let parts = countdownParts(from: context.date)
                    HStack(spacing: 10) {
                        countdownCell(value: parts.days, label: "Tage")
                        countdownCell(value: parts.hours, label: "Std.")
                        countdownCell(value: parts.minutes, label: "Min.")
                        countdownCell(value: parts.seconds, label: "Sek.")
                    }
                }
                Text("Bis Lucia und Jason Leonida übernehmen. Preload ab 12. November.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func countdownParts(from date: Date) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let diff = max(0, Int(GTA.releaseDate.timeIntervalSince(date)))
        return (diff / 86400, (diff % 86400) / 3600, (diff % 3600) / 60, diff % 60)
    }

    private func countdownCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassEffect(
            .regular.tint(Palette.glassTint),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
