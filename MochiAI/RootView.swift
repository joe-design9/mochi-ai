import SwiftUI

/// App root: the pure-black backdrop with its subtle neutral sheen.
/// A fresh install of the normal build meets the invite gate first
/// (v2.4.0), then onboarding until a profile exists, otherwise the
/// Nova layout (v3.0.0): the Chat is the home screen and the other
/// sections (Feed / Ideen / Ziele / Bibliothek) live behind the
/// Muse-style slide-over sidebar — no bottom TabView anymore.
///
/// All five sections stay mounted (like the old TabView kept them)
/// and crossfade with a small vertical settle, so the chat keeps its
/// scroll position and composer draft across section switches.
/// Appearance follows the system — dark is the hero, light maps to
/// clean light-gray monochrome.
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    /// Width of the floating sidebar panel.
    private let sidebarWidth: CGFloat = 302

    var body: some View {
        ZStack {
            AppBackdrop()

            if store.profile == nil && store.needsInviteGate {
                InviteGateView()
            } else if store.profile == nil {
                OnboardingView()
            } else {
                mainLayout
            }
        }
        .dismissKeyboardOnTap()
#if QA
        .task { await openSidebarForQAIfRequested() }
#endif
    }

    // MARK: Main layout — sections + slide-over sidebar

    private var mainLayout: some View {
        ZStack(alignment: .leading) {
            sections

            if store.isSidebarOpen {
                // Dim layer: a plain black overlay (a solid color,
                // never a material) — tap anywhere outside the panel
                // to close it.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { store.isSidebarOpen = false }
                    .transition(.opacity)

                SidebarView()
                    .frame(width: sidebarWidth)
                    .padding(.leading, 10)
                    .padding(.vertical, 10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    // Drag the panel left to dismiss it.
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                if value.translation.width < -56 {
                                    store.isSidebarOpen = false
                                }
                            }
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: store.isSidebarOpen)
        .onChange(of: store.selectedTab) { _, _ in
            // Switching sections always puts the keyboard away.
            KeyboardDismisser.hide()
        }
        // Left-edge swipe opens the sidebar (the header buttons on
        // every section do the same job, discoverably).
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard !store.isSidebarOpen,
                          value.startLocation.x < 28,
                          value.translation.width > 56,
                          abs(value.translation.height) < 60 else { return }
                    store.isSidebarOpen = true
                }
        )
    }

    /// All sections mounted at once; the selected one fades/rises in,
    /// the rest are invisible and non-interactive — state (chat
    /// scroll, drafts, expanded goals) survives every switch.
    private var sections: some View {
        ZStack {
            section(.chat) { ChatView() }
            section(.feed) { FeedView() }
            section(.ideas) { IdeasView() }
            section(.goals) { GoalsView() }
            section(.library) { LibraryView() }
        }
    }

    private func section<Content: View>(
        _ tab: AppStore.Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = store.selectedTab == tab
        return content()
            .opacity(selected ? 1 : 0)
            .offset(y: selected ? 0 : 10)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .animation(.easeOut(duration: 0.25), value: store.selectedTab)
    }

#if QA
    /// `-QASidebar`: opens the sidebar shortly after launch so CI can
    /// photograph the v3.0.0 navigation (TABS + seeded Verläufe +
    /// bottom search bar) in its opened state.
    private func openSidebarForQAIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-QASidebar")
        else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)
        store.isSidebarOpen = true
    }
#endif
}
