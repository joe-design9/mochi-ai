import SwiftUI

/// App root: the plum-and-glow backdrop, onboarding until a profile
/// exists, otherwise the five tabs in a native TabView (iOS 26 renders
/// its bar in real Liquid Glass), accent-tinted. Appearance follows the
/// system — dark is the hero, light maps to soft lilac.
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppBackdrop()

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
                .onChange(of: store.selectedTab) { _, _ in
                    // Switching tabs always puts the keyboard away.
                    KeyboardDismisser.hide()
                }
            }
        }
        .dismissKeyboardOnTap()
    }

    private var tabSelection: Binding<AppStore.Tab> {
        Binding(
            get: { store.selectedTab },
            set: { store.selectedTab = $0 }
        )
    }
}
