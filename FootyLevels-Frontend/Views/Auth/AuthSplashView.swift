import SwiftUI

/// The black beat between signing in or out and the next screen: the logo bars
/// spring up one after another, then the wordmark fades in. Logging out adds a goodbye.
struct AuthSplashView: View {
    let direction: AuthDirection

    /// Seconds the splash takes to cover the old screen.
    static let cover = 0.28
    /// Seconds from the start of the cover until the screens swap underneath.
    static let swapAfter = 1.25
    /// Seconds the splash takes to fade off the new screen.
    static let reveal = 0.52

    @State private var drawn = false

    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 40, onImage: true, drawn: drawn)
            if direction == .signingOut {
                Text("See you next session")
                    .font(.system(.subheadline))
                    .foregroundStyle(.white.opacity(0.72))
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.38), value: drawn)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .background(.black)
        .accessibilityElement(children: .combine)
        .task {
            // Draw the logo once the old screen is covered.
            try? await Task.sleep(for: .seconds(Self.cover))
            drawn = true
        }
    }
}

#Preview("Signing in") {
    AuthSplashView(direction: .signingIn)
}

#Preview("Signing out") {
    AuthSplashView(direction: .signingOut)
}
