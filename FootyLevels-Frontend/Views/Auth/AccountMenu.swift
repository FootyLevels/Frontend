import SwiftUI

/// The signed-in account and the way to log out, behind a person button.
/// Learn shows it over the hero image; Videos shows it in the toolbar.
struct AccountMenu: View {
    let appState: AppStateViewModel
    /// Draws the button as a frosted circle for use over photographs.
    var onImage = false

    var body: some View {
        Menu {
            if let email = appState.currentUser?.email {
                Text(email)
            }
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                try? appState.signOut()
            }
        } label: {
            if onImage {
                Image(systemName: "person.crop.circle")
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(.white)
                    .scaledFrame(width: 44, height: 44, relativeTo: .title3)
                    .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.35)))
                    .environment(\.colorScheme, .dark)
            } else {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .accessibilityLabel("Account")
        .accessibilityHint("Shows your account and Log Out")
    }
}
