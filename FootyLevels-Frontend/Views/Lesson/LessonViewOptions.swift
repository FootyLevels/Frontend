import SwiftUI

/// The View sheet: what fills the screen, the 3D camera, the speed and what the 3D draws.
struct LessonViewOptions<Model: LessonPlayer>: View {
    @Bindable var model: Model
    @Binding var main: LessonMainView
    /// Reports the content's height, so the sheet can be exactly that tall.
    var onHeight: (CGFloat) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("View")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(SL.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(SL.link)
                        .minimumTapArea()
                }
                group("Show") {
                    PillPicker(options: [.init(value: LessonMainView.video, label: "Video"), .init(value: .body, label: "3D body")],
                               selection: $main)
                }
                group("3D camera") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { cameraChips(fill: true) }
                        FlowRow(spacing: 6) { cameraChips(fill: false) }
                    }
                }
                group("Speed") {
                    PillPicker(options: PlaybackController.speeds.map { .init(value: $0, label: "\($0.formatted())×", accessibility: "\($0.formatted()) times speed") },
                               selection: Binding(get: { model.playback.speed }, set: { model.playback.speed = $0 }))
                }
                group("On the 3D body") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        OptionToggle(title: "Mirror", isOn: $model.mirror)
                        OptionToggle(title: "Footprints", isOn: $model.overlays.footprints)
                        OptionToggle(title: "Paths", isOn: $model.overlays.paths)
                        OptionToggle(title: "Ghost", isOn: $model.overlays.ghost)
                        OptionToggle(title: "Direction", isOn: $model.overlays.direction)
                        OptionToggle(title: "Follow", isOn: $model.overlays.follow)
                    }
                }
                HStack(spacing: 16) {
                    legend("Ball foot", Color(uiColor: SL.overlaySecond))
                    legend("Standing foot", Color(uiColor: SL.overlayFirst))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .disabled(!model.isReady)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(.caption, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(SL.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    @ViewBuilder
    private func cameraChips(fill: Bool) -> some View {
        ForEach(CameraAngle.allCases) { angle in
            let on = model.angle == angle
            Button {
                model.show(angle)
                main = .body
            } label: {
                Text(angle.rawValue)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(on ? SL.onGreen : SL.ink)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: fill ? .infinity : nil, minHeight: 36)
                    .background(on ? SL.green : SL.raised, in: Capsule())
                    .overlay(Capsule().stroke(on ? SL.green : SL.line))
                    .minimumTapArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(angle.rawValue) camera")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
        }
        .font(.system(.footnote))
        .foregroundStyle(SL.muted)
    }
}

/// A row of options in one capsule, the chosen one filled.
struct PillPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        var accessibility: String?
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(.footnote, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(on ? SL.onGreen : SL.muted)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? SL.green : .clear, in: Capsule())
                        // The track's inset is part of each option, so every one is 44 points tall to tap.
                        .padding(3)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibility ?? option.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(SL.raised, in: Capsule())
        .overlay(Capsule().stroke(SL.line))
    }
}

/// An on/off option drawn as a tile with a check box.
private struct OptionToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(isOn ? SL.onGreen : .clear)
                    .frame(width: 22, height: 22)
                    .background(isOn ? SL.tint : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(isOn ? SL.tint : SL.controlBorder, lineWidth: 2))
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(SL.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SL.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SL.line))
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
    }
}
