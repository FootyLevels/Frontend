import SwiftUI

/// The profile card. It grows out of the button's photo: the card opens from the photo's
/// circle while the photo moves to the middle and grows, then the details fade in.
/// Closing runs it backwards and hands back to the button.
struct ProfileCardOverlay: View {
    let user: UserInfo?
    /// The button the card grows from, in screen coordinates.
    let origin: CGRect
    let onClose: () -> Void
    let onLogOut: () -> Void

    @State private var expanded = false
    @State private var cardHeight: CGFloat = 320
    @State private var stats = ProfileStats()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let avatarSize: CGFloat = 96
    private let avatarTop: CGFloat = 22
    /// Matches the prototype's curve: fast out of the photo, a long soft landing.
    private var morph: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.56) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            let left = Swift.max(16, Swift.min(origin.maxX - width, geo.size.width - 16 - width))
            ZStack(alignment: .topLeading) {
                backdrop
                card(width: width, left: left)
                    .offset(x: left, y: origin.minY)
            }
        }
        .ignoresSafeArea()
        .task {
            stats = ProfileStats.onThisPhone()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : morph) { expanded = true }
        }
    }

    private var backdrop: some View {
        // A light frosted blur in the app's own appearance, so Learn still shows through.
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.15)
        }
        .opacity(expanded ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .accessibilityElement()
        .accessibilityLabel("Close your profile")
        .accessibilityAddTraits(.isButton)
    }

    private func card(width: CGFloat, left: CGFloat) -> some View {
        // With Reduce Motion the card keeps its shape and simply fades.
        let open = expanded || reduceMotion
        let photo = open ? avatarSize : origin.width
        // Where the button sits inside the card, before it opens.
        let start = origin.minX - left
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(SL.raised)
            details
                .frame(width: width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            ProfileAvatar(url: user?.photoURL, style: .solid)
                .frame(width: photo, height: photo)
                .overlay(Circle().stroke(SL.raised, lineWidth: open ? 4 : 0))
                .position(x: open ? width / 2 : start + origin.width / 2,
                          y: open ? avatarTop + avatarSize / 2 : origin.height / 2)
        }
        .frame(width: width, height: cardHeight, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: open ? 34 : origin.height / 2, style: .continuous)
                .frame(width: open ? width : origin.width, height: open ? cardHeight : origin.height)
                .offset(x: open ? 0 : start)
        }
        .shadow(color: .black.opacity(expanded ? 0.4 : 0), radius: 30, y: 18)
        .opacity(reduceMotion ? (expanded ? 1 : 0) : 1)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    private var details: some View {
        VStack(spacing: 0) {
            // Each side gets the space beside the photo, so its words stay on one line.
            HStack(alignment: .top, spacing: 0) {
                signIn
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: avatarSize + 12, height: 1)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.repsLogged)")
                        .font(.system(size: 32, weight: .medium).monospacedDigit())
                        .tracking(-0.6)
                    Text("reps logged")
                        .font(.system(.footnote))
                        .foregroundStyle(SL.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .combine)
            }
            .frame(height: avatarSize, alignment: .top)
            .padding(.top, avatarTop)
            .fadeIn(expanded, delay: 0.2)

            VStack(spacing: 4) {
                Text(user?.shownName ?? "Your account")
                    .font(.system(.title2, weight: .semibold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                Text(stats.mostPractised.map { "Most practised: \($0)" } ?? "No reps logged yet")
                    .font(.system(.subheadline))
                    .foregroundStyle(SL.muted)
            }
            .padding(.top, 16)
            .fadeIn(expanded, delay: 0.26)

            Rectangle().fill(SL.line).frame(height: 1)
                .padding(.top, 18)
                .fadeIn(expanded, delay: 0.3)

            // One row when it fits; at larger text Log Out moves under the counts, full width.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    counts
                    Spacer(minLength: 8)
                    logOut(fill: false)
                }
                VStack(alignment: .leading, spacing: 14) {
                    counts
                    logOut(fill: true)
                }
            }
            .padding(.top, 16)
            .fadeIn(expanded, delay: 0.32)
        }
        .foregroundStyle(SL.ink)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        // The card is a fixed design around the photo; its text stops growing a few sizes up.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var counts: some View {
        HStack(alignment: .top, spacing: 16) {
            stat(stats.drillsDone, "drills done")
            stat(stats.lessonsStarted, "lessons", spoken: "lessons started")
        }
    }

    private func logOut(fill: Bool) -> some View {
        Button(role: .destructive, action: onLogOut) {
            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(.body, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(SL.errorText)
                .padding(.horizontal, 18)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: 44)
                .background(SL.errorFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if user?.signInMethod == .google {
                    Image("GoogleG").resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "envelope.fill").font(.system(.footnote)).foregroundStyle(SL.muted)
                }
                Text(user?.signInMethod == .google ? "Google" : "Email")
                    .font(.system(.subheadline, weight: .semibold))
            }
            Text("account")
                .font(.system(.footnote))
                .foregroundStyle(SL.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(user?.signInMethod == .google ? "Signed in with Google" : "Signed in with email")
    }

    private func stat(_ value: Int, _ label: String, spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(.title3, weight: .medium).monospacedDigit())
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(SL.muted)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(spoken ?? label)")
    }

    private func close() {
        guard expanded else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : morph) {
            expanded = false
        } completion: {
            onClose()
        }
    }
}

private extension View {
    /// Fades the card's details in after the card has opened, and out at once when it closes.
    func fadeIn(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(shown ? .easeOut(duration: 0.3).delay(delay) : .easeIn(duration: 0.12), value: shown)
    }
}
