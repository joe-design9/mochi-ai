import SwiftUI

/// Feed tab: countdown, profile vibes, daily card, casino promo, idea teaser.
struct FeedView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: "Dein Feed")
                    Text("Gebaut für dich, \(store.profile?.name ?? "Freund").")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                countdownCard
                vibesCard
                dailyCard
                casinoCard
                ideaTeaserCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
    }

    // MARK: Countdown

    private var countdownCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(
                    icon: "gamecontroller.fill",
                    title: "GTA 6 Countdown",
                    bookmark: SavedItem(id: "feed:countdown", title: "GTA 6 Countdown",
                                        subtitle: "Release am 19. November 2026 in Leonida", kind: "Feed")
                )
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
                    .foregroundStyle(.white.opacity(0.65))
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
                .font(.system(.title2, design: .default).weight(.black))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: Vibes

    private var vibesCard: some View {
        GlassCard {
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
                .foregroundStyle(Palette.accentText)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
    }

    // MARK: Daily

    private var dailyCard: some View {
        let daily = DailyPool.today()
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "sun.max.fill",
                    title: daily.title,
                    bookmark: SavedItem(id: "feed:daily", title: daily.title,
                                        subtitle: daily.text, kind: "Feed")
                )
                Text(daily.text)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: Casino promo

    private var casinoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "die.face.5.fill",
                    title: "Muse Royal Casino",
                    bookmark: SavedItem(id: "feed:casino", title: "Muse Royal Casino",
                                        subtitle: "32 Slots warten — nur Spielgeld", kind: "Feed")
                )
                Text("32 Slots warten auf dich — von Book of Muse bis Leonida Nights. Nur Spielgeld, kein Echtgeld, aber mit echtem Casino-Sound.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: Idea teaser

    private var ideaTeaserCard: some View {
        let idea = teaserIdea
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "lightbulb.fill",
                    title: "Idee des Tages",
                    bookmark: SavedItem(id: "idea:\(idea.id)", title: idea.title,
                                        subtitle: idea.text, kind: "Idee")
                )
                Text(idea.title)
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundStyle(.white)
                Text(idea.text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Button {
                    store.selectedTab = .ideas
                } label: {
                    HStack(spacing: 6) {
                        Text("Zu den Ideen")
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
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
                .foregroundStyle(Palette.accentText)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            BookmarkButton(item: bookmark)
        }
    }
}
