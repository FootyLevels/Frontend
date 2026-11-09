import SwiftUI

/// Opens the profile card. Remembers where it sits, so the card can grow out of it.
@MainActor
@Observable
final class ProfilePresenter {
    private(set) var isOpen = false
    /// The button the card opened from, in screen coordinates.
    private(set) var origin: CGRect = .zero

    func open(from frame: CGRect) {
        origin = frame
        isOpen = true
    }

    func dismiss() {
        isOpen = false
    }
}

/// The account's photo as a round button. While the card is open the card's own photo
/// takes its place.
struct ProfileButton: View {
    let user: UserInfo?
    var size: CGFloat = 44
    var style: ProfileAvatar.Style = .glass
    @Environment(ProfilePresenter.self) private var presenter: ProfilePresenter?
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            presenter?.open(from: frame)
        } label: {
            ProfileAvatar(url: user?.photoURL, style: style)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(style == .glass ? 0.4 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .opacity(presenter?.isOpen == true ? 0 : 1)
        .accessibilityLabel("Your profile")
        .accessibilityHint("Shows your name, your progress and Log Out")
    }
}
