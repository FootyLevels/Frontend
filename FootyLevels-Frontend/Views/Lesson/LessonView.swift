import SwiftUI

/// The Over Fake lesson, from watching the move to doing it.
/// It plays from the app bundle, so it works offline and without an account.
struct LessonView: View {
    @State private var model: SkillLessonModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                LessonScreen(model: model)
            } else if let loadError {
                ContentUnavailableView("Lesson unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SL.page)
        .navigationTitle("The over fake")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil, loadError == nil else { return }
            do {
                let lesson = try SkillLessonModel.bundled()
                model = lesson
                await lesson.load()
                lesson.enter(.watch)
            } catch {
                loadError = error.localizedDescription
            }
        }
        // Leaving the lesson only pauses; coming back carries on from the same moment.
        .onDisappear { model?.pause() }
    }
}

private struct LessonScreen: View {
    let model: SkillLessonModel
    @State private var drills = DrillProgressStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                StagePicker(model: model)
                LessonStageView(model: model, shotLabel: shotLabel, cue: cue)
                LessonInfoBar(model: model)
                LessonTransport(model: model) { LessonTimeline(model: model) }
                switch model.stage {
                case .watch: WatchSection(model: model)
                case .breakdown: BreakdownSection(model: model)
                case .practise: PractiseSection(model: model, store: drills)
                case .test: TestSection(model: model)
                }
                Text("Built from one tutorial clip and its 3D reconstruction. Measurements are estimates from a single camera; nothing here rates the player.")
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
        if model.phase.shot == 0 { return "Full-speed demo" }
        return model.phase.start < 6 ? "Tutorial · step 1" : "Tutorial · step 2"
    }

    private var cue: (name: String, text: String) {
        let content = OverFakeLessonContent.phase(model.phase.id)
        return (content.name, content.cue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "LEARN A SKILL", rule: true)
            (Text("The over ") + Text("fake").foregroundColor(Color(uiColor: SL.overlaySecond)))
                .font(SL.display(32, .heavy))
                .tracking(-1.2)
                .foregroundStyle(SL.ink)
            Text("Shape one way, step across the ball, then take it the other way.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "77816F"))
        }
        .padding(.top, 8)
    }
}

// MARK: - Info bar

/// Which feet are down, where the weight sits between them, and the reading
/// the current phase is about. All estimated from the 3D.
private struct LessonInfoBar: View {
    let model: SkillLessonModel

    private var front: Color { Color(uiColor: SL.overlayFirst) }
    private var step: Color { Color(uiColor: SL.overlaySecond) }

    var body: some View {
        let focus = model.stage == .breakdown ? OverFakeLessonContent.phase(model.phase.id).focus : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                pill("Front foot (\(model.mirror ? "R" : "L"))", on: model.frontPlanted, color: front)
                pill("Step foot (\(model.mirror ? "L" : "R"))", on: model.stepPlanted, color: step)
                    .overlay(focusRing(focus == .stepFoot))
                Spacer(minLength: 0)
            }
            meter.overlay(focusRing(focus == .weight).padding(-4))
            HStack(spacing: 14) {
                reading("Body", model.dropCm > 2 ? "≈\(Int(model.dropCm.rounded())) cm lower" : "upright")
                reading("Turn", model.turnDegrees.map { "≈\(Int($0.rounded()))°" } ?? "–")
                    .overlay(focusRing(focus == .turn).padding(-4))
                reading("Ball", ballText)
                    .overlay(focusRing(focus == .ball).padding(-4))
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .slPanel(fill: SL.panel, border: SL.panelBorder, radius: 10)
    }

    private var ballText: String {
        let speed = model.ballSpeed
        if speed > 1.5, speed < 12 { return String(format: "≈%.1f m/s", speed) }
        return speed > 0.6 && speed < 12 ? "rolling" : "close"
    }

    private var meter: some View {
        let w = model.mirror ? 1 - model.weight : model.weight
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.mirror ? "◀ Step foot" : "◀ Front foot")
                Spacer()
                Text("WEIGHT · EST.").tracking(0.8)
                Spacer()
                Text(model.mirror ? "Front foot ▶" : "Step foot ▶")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(SL.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [front.opacity(0.35), SL.line, step.opacity(0.35)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(SL.ink)
                        .overlay(Circle().stroke(SL.panel, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * w - 8)
                        .animation(.easeOut(duration: 0.12), value: w)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight, estimated")
        .accessibilityValue("\(Int((w * 100).rounded())) percent toward the \(model.mirror ? "front" : "stepping") foot")
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

/// Both shots, the lesson's phases and their key moments, with a playhead.
/// Drag or tap to scrub.
private struct LessonTimeline: View {
    let model: SkillLessonModel

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) in width * CGFloat(t / model.lesson.duration) }
            ZStack(alignment: .topLeading) {
                ForEach(model.lesson.shots, id: \.id) { shot in
                    Text(shot.id == 0 ? "FULL-SPEED DEMO" : "SLOW TUTORIAL")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(SL.muted)
                        .lineLimit(1)
                        .frame(width: x(shot.end - shot.start), alignment: .leading)
                        .offset(x: x(shot.start) + 3)
                }
                ForEach(model.lesson.phases) { phase in
                    let active = phase.id == model.phase.id
                    RoundedRectangle(cornerRadius: 3)
                        .fill(active ? Color(uiColor: SL.overlaySecond) : (phase.id == "pause" ? SL.line.opacity(0.6) : SL.modeTrack))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(SL.panel, lineWidth: 1))
                        .frame(width: Swift.max(x(phase.end - phase.start), 2), height: 16)
                        .offset(x: x(phase.start), y: 15)
                    if phase.id != "pause" {
                        Rectangle()
                            .fill(SL.ink.opacity(0.5))
                            .frame(width: 1.5, height: 6)
                            .offset(x: x(phase.key) - 0.75, y: 33)
                    }
                }
                if let loop = model.loop {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(uiColor: SL.overlaySecond), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: Swift.max(x(loop.upperBound - loop.lowerBound), 4), height: 22)
                        .offset(x: x(loop.lowerBound), y: 12)
                }
                Playhead(playback: model.playback, range: 0...model.lesson.duration, width: width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let t = Double(Swift.min(Swift.max(value.location.x / Swift.max(width, 1), 0), 1)) * model.lesson.duration
                        model.freeze(at: t)
                    }
            )
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel("Lesson timeline")
        .accessibilityValue("\(model.phase.id == "pause" ? "Tutorial pause" : OverFakeLessonContent.phase(model.phase.id).name), \(String(format: "%.1f", model.playback.currentTime)) seconds")
        .accessibilityAdjustableAction { direction in model.step(frames: direction == .increment ? 5 : -5) }
    }
}
