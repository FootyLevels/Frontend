import SwiftUI

/// The lesson, in a sheet over the player. Its header (the stages, the current step and the
/// play controls) shows unless the sheet is slid away to watch. Pulled up, it lists the
/// stage's steps, with the chosen one open; at full height it adds the 3D measurements and
/// what one camera can't show.
struct PackageLessonSheet: View {
    let model: PackageLessonModel
    @Binding var detent: LessonSheetDetent
    /// The chosen row per stage. Break it down follows the model's phase instead.
    @Binding var picked: [LessonStage: String]
    let layout: LessonSheetLayout
    var onHeaderHeight: (CGFloat) -> Void
    var openView: () -> Void

    @State private var results: [String: Bool] = [:]
    /// The sheet's height while it is being dragged.
    @State private var dragHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var skill: LessonDocument.Skill { model.skill }
    private var items: [LessonSheetItem] { skill.sheetItems(for: model.stage) }
    private var listHidden: Bool { detent == .peek || detent == .hidden }
    private var selectedID: String? {
        if model.stage == .breakdown { return model.phase?.id ?? items.first?.id }
        return picked[model.stage] ?? items.first?.id
    }

    var body: some View {
        let shown = dragHeight ?? layout.height(detent)
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeaderHeight($0) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        rows
                        more
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, layout.bottomInset + 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedID) { _, id in
                    guard let id, detent == .half || detent == .full else { return }
                    withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(id, anchor: .top) }
                }
            }
            .opacity(listHidden && dragHeight == nil ? 0 : 1)
            .accessibilityHidden(listHidden)
        }
        // Below the smallest height the sheet keeps its size and slides off the bottom.
        .frame(height: Swift.max(shown, layout.height(.peek)), alignment: .top)
        .frame(maxWidth: .infinity)
        .background(SL.card, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .shadow(color: .black.opacity(0.28), radius: 20, y: -6)
        // Slid away, it goes far enough that its shadow leaves too.
        .offset(y: layout.slide(toShow: shown) + (detent == .hidden ? 40 : 0))
        .allowsHitTesting(detent != .hidden)
        .accessibilityHidden(detent == .hidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: detent)
        .onChange(of: model.skill.id) { _, _ in
            picked = [:]
            results = [:]
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            grabber
            PillPicker(options: LessonStage.allCases.map { .init(value: $0, label: $0.shortName, accessibility: "Stage \($0.number): \($0.rawValue)") },
                       selection: Binding(get: { model.stage }, set: { model.enter($0) }))
                .disabled(!model.isReady)
            current
            transport
            LessonScrubber(model: model)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        // The header keeps its full height (two lines of cue); the list below takes what's left.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .gesture(resize)
    }

    private var grabber: some View {
        Button { detent = detent.next } label: {
            Capsule()
                .fill(SL.controlBorder.opacity(0.6))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lesson sheet")
        .accessibilityValue(detent == .peek ? "Small" : detent == .half ? "Half height" : "Full height")
        .accessibilityHint("Resizes the lesson sheet. Make it smaller than small to watch the video.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if detent != .full { detent = detent.next }
            case .decrement: detent = detent == .full ? .half : detent == .half ? .peek : .hidden
            @unknown default: break
            }
        }
    }

    private var current: some View {
        let text = currentText
        return VStack(alignment: .leading, spacing: 3) {
            Text(text.title)
                .font(.system(.title2, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(SL.ink)
            Text(text.detail)
                .font(.system(.subheadline))
                .foregroundStyle(SL.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentText: (title: String, detail: String) {
        if model.stage == .watch { return (skill.watchTitle ?? "Watch it at match speed", skill.intro) }
        guard let item = items.first(where: { $0.id == selectedID }) else { return (skill.short, "") }
        return (item.title, model.stage == .practise ? "\(item.detail) · \(item.tag)" : item.detail)
    }

    /// Watch keeps its name while the row has room for it, and drops to its symbol when not.
    private var transport: some View {
        ViewThatFits(in: .horizontal) {
            transportRow(compactWatch: false)
            transportRow(compactWatch: true)
        }
    }

    private func transportRow(compactWatch: Bool) -> some View {
        HStack(spacing: 10) {
            RoundIconButton(symbol: "backward.end.fill", label: "Previous") { step(-1) }
                .disabled(!model.isReady)
            SheetPlayButton(playback: model.playback) { model.togglePlayback() }
                .disabled(!model.isReady)
            RoundIconButton(symbol: "forward.end.fill", label: "Next") { step(1) }
                .disabled(!model.isReady)
            Spacer(minLength: 0)
            SpeedChip(playback: model.playback, action: openView)
            WatchButton(compact: compactWatch) { detent = .hidden }
            RoundIconButton(symbol: detent == .full ? "chevron.down" : "chevron.up",
                            label: detent == .full ? "Show less of the lesson" : "Show more of the lesson") { detent = detent.next }
        }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let start = layout.height(detent)
                dragHeight = Swift.min(Swift.max(start - value.translation.height, 0), layout.height(.full))
            }
            .onEnded { value in
                let height = dragHeight ?? layout.height(detent)
                dragHeight = nil
                detent = layout.settle(at: height, velocity: -value.velocity.height)
            }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        ForEach(items) { item in
            let on = item.id == selectedID
            VStack(alignment: .leading, spacing: 0) {
                Button { select(item) } label: {
                    SheetRow(item: item, selected: on, result: results[item.id])
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                if on {
                    detail(for: item)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .background(on ? SL.raised : .clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? SL.cardBorder : .clear))
            .id(item.id)
        }
        if model.stage == .test, !skill.challenges.isEmpty, results.count == skill.challenges.count {
            TestSummary(right: results.values.filter { $0 }.count, total: skill.challenges.count) {
                results = [:]
                picked[.test] = items.first?.id
            } back: {
                model.enter(.breakdown)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func detail(for item: LessonSheetItem) -> some View {
        switch model.stage {
        case .watch:
            EmptyView()
        case .breakdown:
            if let phase = skill.phases.first(where: { $0.id == item.id }) {
                PackagePhaseDetail(model: model, phase: phase)
            }
        case .practise:
            if let drill = skill.drills.first(where: { $0.id == item.id }) {
                PackageDrillDetail(model: model, drill: drill)
            }
        case .test:
            if let index = items.firstIndex(of: item), skill.challenges.indices.contains(index) {
                PackageChallengeDetail(model: model, challenge: skill.challenges[index], isLast: index == items.count - 1) { correct in
                    results[item.id] = correct
                    if index + 1 < items.count { picked[.test] = items[index + 1].id }
                }
                .id(item.id)
            }
        }
    }

    private func select(_ item: LessonSheetItem) {
        switch model.stage {
        case .watch:
            picked[.watch] = item.id
            if let time = item.time { model.freeze(at: time) }
        case .breakdown:
            if let phase = skill.phases.first(where: { $0.id == item.id }) { model.focus(on: phase) }
        case .practise, .test:
            picked[model.stage] = item.id
        }
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        select(items[(index + delta + items.count) % items.count])
    }

    // MARK: Full height

    private var more: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetSectionLabel(text: "Measured from the 3D · \(model.phase?.name ?? skill.short)")
            LiveReadings(model: model)
            if let unsure = skill.unsure, !unsure.isEmpty {
                SheetSectionLabel(text: "Hard to see from one camera")
                    .padding(.top, 6)
                ForEach(Array(unsure.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(.subheadline))
                    .foregroundStyle(SL.muted)
                }
            }
        }
        .padding(.top, 18)
    }
}

extension LessonStage {
    /// The label on the sheet's stage picker.
    var shortName: String {
        switch self {
        case .watch: return "Watch"
        case .breakdown: return "Break down"
        case .practise: return "Practise"
        case .test: return "Test"
        }
    }
}

// MARK: - Pieces

/// One step in the list: its time or count, its name and a line about it.
private struct SheetRow: View {
    let item: LessonSheetItem
    let selected: Bool
    /// For challenges already answered: right or wrong.
    let result: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.tag)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(SL.muted)
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(SL.ink)
                Text(item.detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(SL.muted)
                    .lineLimit(selected ? nil : 1)
                    .fixedSize(horizontal: false, vertical: selected)
            }
            Spacer(minLength: 0)
            if let result {
                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(result ? SL.good : SL.miss)
                    .accessibilityLabel(result ? "Right" : "Wrong")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SheetSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(SL.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A round control in the sheet.
private struct RoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(SL.ink)
                .frame(width: 44, height: 44)
                .background(SL.raised, in: Circle())
                .overlay(Circle().stroke(SL.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Slides the sheet away so the whole video shows.
private struct WatchButton: View {
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: compact ? "chevron.down.2" : "chevron.down")
                    .font(.system(.footnote, weight: .bold))
                if !compact { Text("Watch").lineLimit(1) }
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(SL.ink)
            .padding(.leading, compact ? 0 : 12)
            .padding(.trailing, compact ? 0 : 16)
            .frame(minWidth: 44, minHeight: 44)
            .background(SL.raised, in: Capsule())
            .overlay(Capsule().stroke(SL.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch the video full screen")
        .accessibilityInputLabels(["Watch", "Watch the video full screen"])
    }
}

/// Reads the playing state in its own view, so only this button redraws.
private struct SheetPlayButton: View {
    let playback: PlaybackController
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(SL.onGreen)
                .frame(width: 54, height: 54)
                .background(SL.green, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
    }
}

/// Shows the speed when it isn't normal; tapping opens View, where speed lives.
private struct SpeedChip: View {
    let playback: PlaybackController
    let action: () -> Void

    var body: some View {
        if playback.speed != 1 {
            Button(action: action) {
                Text("\(playback.speed.formatted())×")
                    .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SL.muted)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .overlay(Capsule().stroke(SL.line))
                    .minimumTapArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speed \(playback.speed.formatted()) times. Opens View.")
        }
    }
}

/// The skill's stretch of the clip: its phases, the current one highlighted, and the
/// playhead. Drag or tap to scrub.
private struct LessonScrubber: View {
    let model: PackageLessonModel

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let range = model.skill.range
            let span = Swift.max(range.upperBound - range.lowerBound, 0.001)
            let x = { (t: Double) in width * CGFloat((Swift.min(Swift.max(t, range.lowerBound), range.upperBound) - range.lowerBound) / span) }
            ZStack(alignment: .leading) {
                ForEach(model.skill.phases) { phase in
                    Capsule()
                        .fill(phase == model.phase ? Color(uiColor: SL.overlaySecond) : SL.modeTrack)
                        .frame(width: Swift.max(x(phase.end) - x(phase.start) - 3, 2), height: 6)
                        .offset(x: x(phase.start))
                }
                ScrubHead(playback: model.playback, x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let share = Double(Swift.min(Swift.max(value.location.x / Swift.max(width, 1), 0), 1))
                        model.freeze(at: Swift.min(range.lowerBound + share * span, range.upperBound - 0.01))
                    }
            )
        }
        .frame(height: 24)
        .disabled(!model.isReady)
        .accessibilityElement()
        .accessibilityLabel("Skill timeline")
        .accessibilityValue("\(model.phase?.name ?? model.skill.short), \(String(format: "%.1f", model.playback.currentTime)) seconds")
        .accessibilityAdjustableAction { direction in model.step(frames: direction == .increment ? 5 : -5) }
    }
}

/// Reads the 60 Hz clock in its own view.
private struct ScrubHead: View {
    let playback: PlaybackController
    let x: (Double) -> CGFloat

    var body: some View {
        Capsule()
            .fill(SL.ink)
            .frame(width: 3, height: 18)
            .offset(x: x(playback.currentTime) - 1.5)
            .allowsHitTesting(false)
    }
}

/// The readings from the 3D at the current moment. Reads the model's per-frame values in
/// its own view, so only these tiles redraw while the clip plays.
private struct LiveReadings: View {
    let model: PackageLessonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                tile(model.turnDegrees.map { "≈\(Int($0.rounded()))°" } ?? "–", "Turn")
                tile(model.dropCm > 2 ? "≈\(Int(model.dropCm.rounded())) cm" : "Upright", "Lower")
                tile("\(Int(((1 - model.weight) * 100).rounded()))%", "On standing foot")
            }
            Text("Ball \(model.ballText). Estimates from one camera.")
                .font(.system(.footnote))
                .foregroundStyle(SL.muted)
            if !model.hasBody {
                Text("No 3D body in this frame: the tracker lost the player.")
                    .font(.system(.footnote))
                    .foregroundStyle(SL.muted)
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, weight: .medium).monospacedDigit())
                .foregroundStyle(SL.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(SL.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SL.raised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SL.cardBorder))
        .accessibilityElement(children: .combine)
    }
}

/// After the last challenge: the score and where to go next.
private struct TestSummary: View {
    let right: Int
    let total: Int
    let retry: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(right) of \(total) right")
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(SL.ink)
            Text(right == total ? "You know the shape of the move. Take it to the pitch with the later drills."
                                : "Revisit the moments you missed in Break it down, then try again.")
                .font(.system(.subheadline))
                .foregroundStyle(SL.muted)
            HStack(spacing: 8) {
                Button("Try again", action: retry).buttonStyle(.slSecondary)
                Button("Back to Break it down", action: back).buttonStyle(.slPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SL.raised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SL.cardBorder))
    }
}
