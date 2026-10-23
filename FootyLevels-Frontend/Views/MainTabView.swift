import SwiftUI

/// The signed-in app: videos, overlay comparison, and private training circles, on a
/// bottom tab bar. Each tab owns its own navigation.
struct MainTabView: View {
    /// Nil for the Debug local-sample entry, which has no account.
    let appState: AppStateViewModel?

    /// Shared by both tabs, so a video imported on one shows up on the other.
    @State private var library = ProjectsListViewModel()

    var body: some View {
        TabView {
            Tab("Videos", systemImage: "film.stack") {
                ProjectsListView(appState: appState, viewModel: library)
            }
            Tab("Overlay", systemImage: "square.2.layers.3d") {
                OverlayDifferenceView(library: library)
            }
            Tab("Community", systemImage: "person.3") {
                CommunityView(hasAccount: appState?.isLoggedIn == .loggedIn)
            }
        }
        .tint(SL.green)
    }
}
