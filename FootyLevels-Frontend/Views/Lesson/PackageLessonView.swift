import SwiftUI

/// Plays one lesson made by the lesson pipeline: every skill in the video, each from
/// watching it to doing it. Everything shown comes from the lesson bundle.
struct PackageLessonView: View {
    let entry: LessonLibrary.Entry

    @State private var model: PackageLessonModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                PackageLessonScreen(model: model)
            } else if let loadError {
                ContentUnavailableView("Lesson unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SL.page)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil, loadError == nil else { return }
            do {
                let lesson = try PackageLessonModel.load(entry.url)
                model = lesson
                await lesson.load()
                lesson.enter(.watch)
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onDisappear { model?.pause() }
    }
}

private struct PackageLessonScreen: View {
    let model: PackageLessonModel

    private var document: LessonDocument { model.package.document }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if document.skills.count > 1 {
                    SkillPicker(model: model)
                }
                StagePicker(model: model)
                LessonStageView(model: model, shotLabel: shotLabel, cue: model.phase.map { ($0.name, $0.cue) })
                PackageInfoBar(model: model)
                LessonTransport(model: model) { PackageTimeline(model: model) }
                Group {
                    switch model.stage {
                    case .watch: PackageWatchSection(model: model)
                    case .breakdown: PackageBreakdownSection(model: model)
                    case .practise: PackagePractiseSection(model: model)
                    case .test: PackageTestSection(model: model)
                    }
                }
                // A new skill starts its sections afresh.
                .id(model.skill.id)
                Text("Built from \(document.sourceNote) Measurements are estimates from a single camera; nothing here rates the player.")
                    .font(.system(size: 11))
                    .foregroundStyle(SL.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var shotLabel: String {
        model.package.shotLabel(at: model.phase?.start ?? model.skill.range.lowerBound)?.label ?? ""
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "LEARN A SKILL", rule: true)
            title
                .font(SL.display(32, .heavy))
                .tracking(-1.2)
                .foregroundStyle(SL.ink)
            Text(document.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "77816F"))
        }
        .padding(.top, 8)
    }

    /// The title with its accent word drawn in the ball-foot colour.
    private var title: Text {
        guard let accent = document.accent, let range = document.title.range(of: accent) else {
            return Text(document.title)
        }
        return Text(document.title[..<range.lowerBound])
            + Text(document.title[range]).foregroundColor(Color(uiColor: SL.overlaySecond))
            + Text(document.title[range.upperBound...])
    }
}

// MARK: - Skill picker

/// One chip per move in the video.
private struct SkillPicker: View {
    let model: PackageLessonModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.package.document.skills) { skill in
                    let selected = model.skill.id == skill.id
                    Button {
                        model.select(skill.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.tab.uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(selected ? Color(hex: "D6E2D0") : SL.muted)
                            Text(skill.short)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? Color(hex: "F1F6E9") : SL.ink)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? SL.greenActive : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? SL.greenActive : SL.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(skill.name), \(skill.tab)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .disabled(!model.isReady)
    }
}

// MARK: - Info bar

/// Which feet are down, where the weight sits between them, and the readings.
/// In Break it down, the reading the phase is about gets a ring. All estimated from the 3D.
private struct PackageInfoBar: View {
    let model: PackageLessonModel

    private var stand: Color { Color(uiColor: SL.overlayFirst) }
    private var ball: Color { Color(uiColor: SL.overlaySecond) }

    var body: some View {
        let focus = model.stage == .breakdown ? model.phase?.focus : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                pill("Ball foot", on: model.ballPlanted, color: ball)
                    .overlay(focusRing(focus == "ball"))
                pill("Standing foot", on: model.standPlanted, color: stand)
                    .overlay(focusRing(focus == "stand"))
                Spacer(minLength: 0)
            }
            meter.overlay(focusRing(focus == "weight").padding(-4))
            HStack(spacing: 14) {
                reading("Body", model.dropCm > 2 ? "≈\(Int(model.dropCm.rounded())) cm lower" : "upright")
                    .overlay(focusRing(focus == "drop").padding(-4))
                reading("Turn", model.turnDegrees.map { "≈\(Int($0.rounded()))°" } ?? "–")
                    .overlay(focusRing(focus == "turn").padding(-4))
                reading("Ball", model.ballText)
                    .overlay(focusRing(focus == "balls").padding(-4))
                Spacer(minLength: 0)
            }
            if !model.hasBody {
                Text("No 3D body in this frame: the tracker lost the player.")
                    .font(.system(size: 11))
                    .foregroundStyle(SL.muted)
            }
        }
        .padding(12)
        .slPanel(fill: SL.panel, border: SL.panelBorder, radius: 10)
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("◀ Standing foot")
                Spacer()
                Text("WEIGHT · EST.").tracking(0.8)
                Spacer()
                Text("Ball foot ▶")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(SL.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [stand.opacity(0.35), SL.line, ball.opacity(0.35)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(SL.ink)
                        .overlay(Circle().stroke(SL.panel, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * model.weight - 8)
                        .animation(.easeOut(duration: 0.12), value: model.weight)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight, estimated")
        .accessibilityValue("\(Int((model.weight * 100).rounded())) percent toward the ball foot")
    }

    private func pill(_ text: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? color : .clear)
                .overlay(Circle().stroke(on ? color : SL.muted, lineWidth: 1.5))
                .frame(width: 9, height: 9)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(on ? color : SL.muted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(Capsule().stroke(on ? color : SL.line, lineWidth: 1.5))
        .accessibilityLabel("\(text) \(on ? "on the ground" : "off the ground")")
    }

    private func reading(_ label: String, _ value: String) -> some View {
        (Text(label + " ").foregroundColor(SL.muted) + Text(value).foregroundColor(SL.ink).fontWeight(.semibold))
            .font(.system(size: 12).monospacedDigit())
    }

    private func focusRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(on ? Color(uiColor: SL.overlaySecond).opacity(0.7) : .clear, lineWidth: 2)
    }
}

// MARK: - Timeline

/// The selected skill's part of the video: its shots, phases and key moments, with a
/// playhead. Drag or tap to scrub.
private struct PackageTimeline: View {
    let model: PackageLessonModel

    private var range: ClosedRange<Double> { model.skill.range }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = Swift.max(range.upperBound - range.lowerBound, 0.001)
            let x = { (t: Double) in width * CGFloat((Swift.min(Swift.max(t, range.lowerBound), range.upperBound) - range.lowerBound) / span) }
            ZStack(alignment: .topLeading) {
                ForEach(Array(shots.enumerated()), id: \.offset) { _, shot in
                    Text(shot.label.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(SL.muted)
                        .lineLimit(1)
                        .frame(width: Swift.max(x(shot.end) - x(shot.start) - 3, 0), alignment: .leading)
                        .offset(x: x(shot.start) + 3)
                }
                ForEach(model.skill.phases) { phase in
                    let active = phase == model.phase
                    RoundedRectangle(cornerRadius: 3)
                        .fill(active ? Color(uiColor: SL.overlaySecond) : SL.modeTrack)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(SL.panel, lineWidth: 1))
                        .frame(width: Swift.max(x(phase.end) - x(phase.start), 2), height: 16)
                        .offset(x: x(phase.start), y: 15)
                    Rectangle()
                        .fill(SL.ink.opacity(0.5))
                        .frame(width: 1.5, height: 6)
                        .offset(x: x(phase.key) - 0.75, y: 33)
                }
                if let loop = model.loop {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(uiColor: SL.overlaySecond), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: Swift.max(x(loop.upperBound) - x(loop.lowerBound), 4), height: 22)
                        .offset(x: x(loop.lowerBound), y: 12)
                }
                Playhead(playback: model.playback, range: range, width: width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let share = Double(Swift.min(Swift.max(value.location.x / Swift.max(width, 1), 0), 1))
                        model.freeze(at: Swift.min(range.lowerBound + share * span, range.upperBound - 0.01))
                    }
            )
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel("Skill timeline")
        .accessibilityValue("\(model.phase?.name ?? model.skill.short), \(String(format: "%.1f", model.playback.currentTime)) seconds")
        .accessibilityAdjustableAction { direction in model.step(frames: direction == .increment ? 5 : -5) }
    }

    /// The labelled shots that overlap this skill.
    private var shots: [LessonDocument.Shot] {
        model.package.document.shots.filter { $0.end > range.lowerBound + 0.05 && $0.start < range.upperBound - 0.05 }
    }
}
