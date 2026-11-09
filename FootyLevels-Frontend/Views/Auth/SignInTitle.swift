import SwiftUI

/// "Welcome to FootyLevels", word by word. When `shown` turns on, each word rises out of its
/// own line; once `alive`, a lime shine crosses "Levels" every few seconds.
struct SignInTitle: View {
    let shown: Bool
    let alive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    word("Welcome ", 0)
                    word("to", 1)
                }
                HStack(spacing: 0) {
                    word("Footy", 2)
                    levels
                }
            }
            // At the largest text sizes the words wrap as plain text instead.
            Text("Welcome to FootyLevels")
        }
        .font(.system(.largeTitle))
        .tracking(-0.6)
        .foregroundStyle(.white)
        .accessibilityRepresentation {
            Text("Welcome to FootyLevels").accessibilityAddTraits(.isHeader)
        }
    }

    private func word(_ text: String, _ index: Int) -> some View {
        Text(text)
            .modifier(Rise(shown: shown, index: index, reduceMotion: reduceMotion))
    }

    private var levels: some View {
        TimelineView(.animation(paused: !alive || reduceMotion)) { context in
            Text("Levels")
                .foregroundStyle(Self.shine(at: alive && !reduceMotion ? Self.shinePosition(at: context.date.timeIntervalSinceReferenceDate) : nil))
        }
        .modifier(Rise(shown: shown, index: 3, reduceMotion: reduceMotion))
    }

    /// Where the shine is across "Levels" (0 is its left edge, 1 its right), or nil between sweeps.
    /// It takes 1.8 s to cross, once every 6 s.
    static func shinePosition(at seconds: TimeInterval) -> Double? {
        let phase = seconds.truncatingRemainder(dividingBy: 6)
        guard phase >= 0, phase < 1.8 else { return nil }
        return -0.2 + 1.4 * (phase / 1.8)
    }

    private static func shine(at position: Double?) -> AnyShapeStyle {
        guard let position else { return AnyShapeStyle(Color.white) }
        let at = { (offset: Double) in Swift.min(Swift.max(position + offset, 0), 1) }
        return AnyShapeStyle(LinearGradient(stops: [
            .init(color: .white, location: at(-0.16)),
            .init(color: SL.lime, location: at(0)),
            .init(color: .white, location: at(0.16)),
        ], startPoint: .leading, endPoint: .trailing))
    }
}

/// Lifts a word up out of its own line, one after another.
private struct Rise: ViewModifier {
    let shown: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: shown ? 0 : 52)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.64).delay(0.38 + Double(index) * 0.07), value: shown)
            .clipped()
    }
}
