import SwiftUI

/// The account's photo in a circle, or the person symbol when there's no photo.
struct ProfileAvatar: View {
    enum Style {
        /// Frosted, for over a photograph.
        case glass
        /// Brand-filled, for the profile card.
        case solid
        /// Just the symbol, for a toolbar.
        case plain
    }

    let url: URL?
    var style: Style = .glass

    var body: some View {
        ZStack {
            background
            if let url {
                AsyncImage(url: ProfilePhoto.sized(url, pixels: 300)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    symbol
                }
            } else {
                symbol
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .glass: Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        case .solid: Circle().fill(SL.avatarFill)
        case .plain: Color.clear
        }
    }

    private var symbol: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .fontWeight(.light)
            .foregroundStyle(style == .plain ? SL.ink : Color.white)
    }
}

/// Google serves account photos at the size the address asks for.
enum ProfilePhoto {
    /// Asks a Google photo address for `pixels` square, so it stays sharp when shown large.
    /// Other addresses are left as they are.
    static func sized(_ url: URL, pixels: Int) -> URL {
        let text = url.absoluteString
        guard let range = text.range(of: "=s[0-9]+-c$", options: .regularExpression) else { return url }
        return URL(string: text.replacingCharacters(in: range, with: "=s\(pixels)-c")) ?? url
    }
}
