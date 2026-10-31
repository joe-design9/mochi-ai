import SwiftUI

/// App root: warm paper background, onboarding until a profile exists,
/// otherwise the five tabs in a native TabView (standard tab bar,
/// accent tint). Appearance follows the system (light/dark).
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            if store.profile == nil {
                OnboardingView()
            } else {
                TabView(selection: tabSelection) {
                    ChatView()
                        .tabItem { Label("Chat", systemImage: "message.fill") }
                        .tag(AppStore.Tab.chat)
                    FeedView()
                        .tabItem { Label("Feed", systemImage: "newspaper.fill") }
                        .tag(AppStore.Tab.feed)
                    IdeasView()
                        .tabItem { Label("Ideen", systemImage: "lightbulb.fill") }
                        .tag(AppStore.Tab.ideas)
                    GoalsView()
                        .tabItem { Label("Ziele", systemImage: "target") }
                        .tag(AppStore.Tab.goals)
                    LibraryView()
                        .tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }
                        .tag(AppStore.Tab.library)
                }
                .tint(Palette.accent)
            }
        }
    }

    private var tabSelection: Binding<AppStore.Tab> {
        Binding(
            get: { store.selectedTab },
            set: { store.selectedTab = $0 }
        )
    }
}
