import SwiftUI

/// The signed-in app: lessons, overlay comparison, private training circles and videos
/// lessons, on a bottom tab bar. Each tab owns its own navigation.
struct MainTabView: View {
    /// Nil for the Debug local-sample entry, which has no account.
    let appState: AppStateViewModel?

    /// Shared by both tabs, so a video imported on one shows up on the other.
    @State private var library = ProjectsListViewModel()
    /// The profile card, which opens from the photo button on Learn or Videos.
    @State private var profile = ProfilePresenter()

    var body: some View {
        TabView {
            Tab("Learn", systemImage: "figure.soccer") {
                LessonLibraryView(appState: appState)
            }
            Tab("Overlay", systemImage: "square.2.layers.3d") {
                OverlayDifferenceView(library: library)
            }
            Tab("Community", systemImage: "person.3") {
                CommunityView(hasAccount: appState?.isLoggedIn == .loggedIn)
            }
            Tab("Videos", systemImage: "film.stack") {
                ProjectsListView(appState: appState, viewModel: library)
            }
        }
        .tint(SL.tint)
        .toolbarBackground(SL.header, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(profile)
        // Over the tab bar too, so the whole app blurs behind the card.
        .overlay {
            if profile.isOpen, let appState {
                ProfileCardOverlay(user: appState.currentUser, origin: profile.origin) {
                    profile.dismiss()
                } onLogOut: {
                    profile.dismiss()
                    try? appState.signOut()
                }
            }
        }
    }
}
