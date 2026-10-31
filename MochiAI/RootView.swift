import SwiftUI

/// App root: animated background, onboarding until a profile exists,
/// otherwise the five tabs with a floating Liquid Glass tab bar above them.
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppBackground()

            if store.profile == nil {
                OnboardingView()
            } else {
                tabContent

                VStack {
                    Spacer()
                    FloatingTabBar()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch store.selectedTab {
        case .chat:
            ChatView()
        case .feed:
            FeedView()
        case .ideas:
            IdeasView()
        case .goals:
            GoalsView()
        case .library:
            LibraryView()
        }
    }
}

// MARK: - Floating glass tab bar

struct FloatingTabBar: View {
    @EnvironmentObject private var store: AppStore

    private let tabs: [(tab: AppStore.Tab, icon: String, label: String)] = [
        (.chat, "message.fill", "Chat"),
        (.feed, "newspaper.fill", "Feed"),
        (.ideas, "lightbulb.fill", "Ideen"),
        (.goals, "target", "Ziele"),
        (.library, "books.vertical.fill", "Bibliothek"),
    ]

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.tab) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon)
                                .font(.system(size: 19, weight: .semibold))
                            Text(item.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(store.selectedTab == item.tab ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if store.selectedTab == item.tab {
                                Capsule().fill(Color.white.opacity(0.20))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
