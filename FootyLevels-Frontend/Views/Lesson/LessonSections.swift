import SwiftUI

private let stepColor = Color(uiColor: SL.overlaySecond)

// MARK: - 1. Watch

struct WatchSection: View {
    let model: SkillLessonModel

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 1 OF 4 · ABOUT A MINUTE", title: "Watch it at match speed",
                           text: "The whole move takes about two seconds against a defender. Watch it twice, at full and half speed. Tap a moment to jump to it.")
            VStack(spacing: 8) {
                ForEach(Array(OverFakeLessonContent.watchMoments.enumerated()), id: \.offset) { _, moment in
                    let content = OverFakeLessonContent.phase(moment.phase)
                    let live = model.phase.id == moment.phase
                    Button {
                        model.setLoop(nil)
                        model.freeze(at: moment.time)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%.2f s", moment.time))
                                .font(.system(.caption, weight: .semibold).monospacedDigit())
                                .foregroundStyle(stepColor)
                                .frame(minWidth: 52, alignment: .leading)
                            Text("\(Text("\(content.name). ").fontWeight(.semibold))\(watchText(moment.phase, content))")
                                .font(.system(.footnote))
                                .foregroundStyle(SL.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(live ? SL.ink : SL.cardBorder))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button("Full speed") { model.play(0...3.0, rate: 1) }.buttonStyle(.slSecondary)
                Button("Half speed") { model.play(0...3.0, rate: 0.5) }.buttonStyle(.slSecondary)
                Spacer(minLength: 0)
                Button("Break it down") { model.enter(.breakdown) }.buttonStyle(.slPrimary)
            }
        }
        SectionCard {
            Eyebrow(text: "WHY THE 3D HELPS", color: SL.muted)
            Text("The 3D body is reconstructed from this video. Turn the camera, see which foot carries the weight, and follow the feet and the ball. Orange is the stepping foot, blue the front foot.")
                .font(.system(.footnote))
                .foregroundStyle(SL.ink)
            Text("The defender isn't reconstructed, and this fast section is the least precise part of the 3D.")
                .font(.system(.caption))
                .foregroundStyle(SL.muted)
        }
    }

    private func watchText(_ id: String, _ content: LessonPhaseContent) -> String {
        let measured = content.shows(model.lesson)
        return measured.isEmpty ? content.watch : "\(content.watch) \(measured)"
    }
}

// MARK: - 2. Break it down

struct BreakdownSection: View {
    let model: SkillLessonModel
    @State private var open: String? = "setup"

    private var phases: [SkillLesson.Phase] { model.lesson.phases.filter { $0.shot == 1 } }

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 2 OF 4 · THE SLOW TUTORIAL", title: "Break it down",
                           text: "Seven moments, in order. Open one to freeze on it; play it to loop it at half speed. The cues in the 3D switch to what matters for that moment.")
        }
        VStack(spacing: 8) {
            ForEach(Array(numbered.enumerated()), id: \.element.phase.id) { _, item in
                phaseCard(item.phase, number: item.number)
            }
        }
        Button("Practise it") { model.enter(.practise) }
            .buttonStyle(.slPrimaryWide)
    }

    private var numbered: [(phase: SkillLesson.Phase, number: Int?)] {
        var n = 0
        return phases.map { phase in
            if phase.id == "pause" { return (phase, nil) }
            n += 1
            return (phase, n)
        }
    }

    private func phaseCard(_ phase: SkillLesson.Phase, number: Int?) -> some View {
        let content = OverFakeLessonContent.phase(phase.id)
        let isOpen = open == phase.id
        let live = model.phase.id == phase.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                open = isOpen ? nil : phase.id
                if !isOpen { model.focus(on: phase) }
            } label: {
                HStack(spacing: 10) {
                    NumberBadge(text: number.map(String.init) ?? "–", filled: live, color: stepColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.name.uppercased())
                            .font(SL.display(.body))
                            .foregroundStyle(number == nil ? SL.muted : SL.ink)
                        Text(String(format: "%.2f–%.2f s", phase.start, phase.end))
                            .font(.system(.caption2).monospacedDigit())
                            .foregroundStyle(SL.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(SL.muted)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapse" : "Freeze on this moment and show its details")

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Text(content.cue.uppercased())
                        .font(SL.display(.body))
                        .foregroundStyle(stepColor)
                    fact("In the 3D", content.shows(model.lesson))
                    fact("In the video", content.watch)
                    if let confidence = content.confidence {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(confidence.label.uppercased())
                                .font(.system(.caption2, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(confidence.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(confidence.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            Text(content.confidenceWhy)
                                .font(.system(.caption))
                                .foregroundStyle(SL.muted)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Play at ½×") { model.play(phase.start...phase.end, rate: 0.5) }
                            .buttonStyle(.slPrimary)
                        Button("Freeze on key moment") { model.freeze(at: phase.key) }
                            .buttonStyle(.slSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .slPanel(fill: SL.card, border: isOpen ? SL.ink.opacity(0.6) : SL.cardBorder, radius: 10)
    }

    private func fact(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(SL.muted)
            Text(text)
                .font(.system(.footnote))
                .foregroundStyle(SL.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 3. Practise

struct PractiseSection: View {
    let model: SkillLessonModel
    let store: DrillProgressStore

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 3 OF 4 · ON THE PITCH", title: "Practise it",
                           text: "Five drills, from footwork only to full speed. Play the model, do the reps, then tick what you managed. Turn on Mirror to learn it on your other foot.")
        }
        VStack(spacing: 10) {
            ForEach(Array(OverFakeLessonContent.drills.enumerated()), id: \.element.id) { index, drill in
                drillCard(drill, number: index + 1)
            }
        }
        Button("Test yourself") { model.enter(.test) }
            .buttonStyle(.slPrimaryWide)
    }

    private func drillCard(_ drill: LessonDrill, number: Int) -> some View {
        let progress = store.progress(drill.id)
        let done = progress.isComplete(targetReps: drill.reps, checkCount: drill.checks.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NumberBadge(text: done ? "✓" : "\(number)", filled: done, color: SL.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.level.uppercased())
                        .font(.system(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(SL.muted)
                    Text(drill.title)
                        .font(SL.display(.title3))
                        .foregroundStyle(SL.ink)
                }
                Spacer(minLength: 0)
                Button {
                    model.play(drill.start...drill.end, rate: drill.rate, skipPause: drill.skipsPause)
                } label: {
                    Label("Model", systemImage: "play.fill")
                }
                .buttonStyle(.slSecondary)
                .accessibilityLabel("Play the model for \(drill.title)")
            }
            Text(drill.how)
                .font(.system(.footnote))
                .foregroundStyle(SL.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(drill.checks.enumerated()), id: \.offset) { index, check in
                    let on = index < progress.checks.count && progress.checks[index]
                    Toggle(check, isOn: Binding(get: { on }, set: { value in store.update(drill.id) { $0.setCheck(index, value) } }))
                        .toggleStyle(CheckToggleStyle())
                        .font(.system(.footnote))
                        .foregroundStyle(SL.ink)
                }
            }
            HStack(spacing: 10) {
                Button("+1 rep") { store.update(drill.id) { $0.reps += 1 } }
                    .buttonStyle(.slSecondary)
                Text("\(Swift.min(progress.reps, drill.reps)) / \(drill.reps)")
                    .font(.system(.caption).monospacedDigit())
                    .foregroundStyle(SL.muted)
                HStack(spacing: 3) {
                    ForEach(0..<drill.reps, id: \.self) { rep in
                        Circle()
                            .fill(rep < progress.reps ? SL.good : .clear)
                            .overlay(Circle().stroke(rep < progress.reps ? SL.good : SL.muted, lineWidth: 1.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button("Reset") { store.reset(drill.id) }
                    .font(.system(.caption))
                    .foregroundStyle(SL.muted)
            }
        }
        .padding(14)
        .slPanel(fill: SL.card, border: done ? SL.good : SL.cardBorder, radius: 10)
    }
}

// MARK: - 4. Test yourself

struct TestSection: View {
    let model: SkillLessonModel

    enum Step: Int { case whichFoot, spotPlant, predict, order, results }

    struct Result {
        let name: String
        let correct: Bool
    }

    @State private var step: Step = .whichFoot
    @State private var results: [Result] = []
    @State private var answer: String?
    @State private var tap: TapVerdict?
    @State private var waitingForTap = false
    @State private var picked: [String] = []

    private var lesson: SkillLesson { model.lesson }
    private var passTime: Double { lesson.time(ofFrame: lesson.events.pass.frame) }
    private var plantTime: Double { lesson.time(ofFrame: lesson.events.plant.frame) }
    private let predictTime = 6.78
    private let shuffled = ["change", "sell", "go", "setup", "plant", "shift", "step"]

    var body: some View {
        SectionCard {
            switch step {
            case .whichFoot: whichFoot
            case .spotPlant: spotPlant
            case .predict: predict
            case .order: order
            case .results: summary
            }
        }
        .onAppear { prepare(step) }
        .onChange(of: step) { _, new in prepare(new) }
        .onChange(of: model.autoStops) { _, _ in
            if waitingForTap { finishTap(nil) }
        }
        .onChange(of: model.mirror) { _, _ in if step == .whichFoot { answer = nil } }
    }

    private func prepare(_ step: Step) {
        answer = nil
        tap = nil
        waitingForTap = false
        picked = []
        switch step {
        case .whichFoot:
            model.overlays = LessonOverlays(footprints: false, paths: true, ghost: false, direction: false)
            model.freeze(at: passTime)
        case .spotPlant:
            model.overlays = LessonOverlays(footprints: false, paths: true, ghost: false, direction: false)
            model.freeze(at: 4.15)
        case .predict:
            model.overlays = LessonOverlays(footprints: true, paths: false, ghost: false, direction: false)
            model.freeze(at: predictTime)
        case .order, .results:
            break
        }
    }

    private func heading(_ number: Int, _ title: String, _ text: String) -> some View {
        SectionHeading(eyebrow: "STAGE 4 OF 4 · CHALLENGE \(number) OF 4", title: title, text: text)
    }

    private func next(_ name: String, _ correct: Bool) -> some View {
        Button(step == .order ? "See results" : "Next challenge") {
            results.append(Result(name: name, correct: correct))
            step = Step(rawValue: step.rawValue + 1) ?? .results
        }
        .buttonStyle(.slPrimary)
    }

    private func option(_ id: String, _ text: String, correct: String) -> some View {
        let chosen = answer == id
        let reveal = answer != nil
        let isRight = id == correct
        return Button {
            guard answer == nil else { return }
            answer = id
        } label: {
            Text(text)
                .font(.system(.subheadline))
                .foregroundStyle(SL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(reveal && isRight ? SL.good.opacity(0.12) : (chosen ? SL.miss.opacity(0.1) : .clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(reveal && isRight ? SL.good : (chosen ? SL.miss : SL.cardBorder)))
        }
        .buttonStyle(.plain)
        .disabled(reveal)
    }

    private func feedback(_ good: Bool, _ text: String) -> some View {
        Text(text)
            .font(.system(.footnote))
            .foregroundStyle(SL.ink)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(good ? SL.good.opacity(0.12) : SL.noticeFill, in: RoundedRectangle(cornerRadius: 8))
    }

    // 1
    private var whichFoot: some View {
        let correct = model.mirror ? "left" : "right"
        return VStack(alignment: .leading, spacing: 10) {
            heading(1, "Which foot steps across?", "The video is frozen mid-step. Which of the player\u{2019}s feet is swinging across the ball?")
            option("left", "His left foot", correct: correct)
            option("right", "His right foot", correct: correct)
            if let answer {
                feedback(answer == correct, "\(answer == correct ? "Right." : "Not quite.") The \(correct) foot (orange) swings across while the front foot holds the weight.\(model.mirror ? " Mirror is on, so this is the left-footed version." : "")")
                next("Which foot", answer == correct)
            }
        }
    }

    // 2
    private var spotPlant: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(2, "Tap when the foot lands", "It plays at quarter speed. Tap Plant! the moment the stepping foot lands past the ball.")
            HStack(spacing: 8) {
                Button("Start") {
                    tap = nil
                    waitingForTap = true
                    model.play(from: 4.15, rate: 0.25, stopAt: plantTime + 0.5)
                }
                .buttonStyle(.slSecondary)
                .disabled(waitingForTap)
                Button("Plant!") { finishTap(model.playback.currentTime) }
                    .buttonStyle(.slPrimary)
                    .disabled(!waitingForTap)
            }
            if let tap {
                feedback(tap.isCorrect, tapText(tap))
                HStack(spacing: 8) {
                    Button("Try again") { prepare(.spotPlant) }.buttonStyle(.slSecondary)
                    next("Spot the plant", tap.isCorrect)
                }
            }
        }
    }

    private func finishTap(_ tapped: Double?) {
        waitingForTap = false
        model.freeze(at: plantTime)
        tap = TapVerdict.judge(tapped: tapped, target: plantTime)
    }

    private func tapText(_ verdict: TapVerdict) -> String {
        let landed = String(format: "The foot lands at %.2f s; the video is frozen there.", plantTime)
        switch verdict {
        case .missed: return "No tap that time. \(landed)"
        case .onTime(let error): return "Spot on, \(Int(abs(error) * 1000)) ms \(error < 0 ? "early" : "late"). \(landed)"
        case .early(let by): return String(format: "%.2f s early: the foot was still swinging. ", by) + landed
        case .late(let by): return String(format: "%.2f s late: the weight was already moving across. ", by) + landed
        }
    }

    // 3
    private var predict: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(3, "What happens next?", "Frozen with his weight loaded on the planted foot. Predict the next movement.")
            option("a", "He keeps going the way his weight is moving", correct: "b")
            option("b", "He turns back and takes the ball the other way with his other foot", correct: "b")
            option("c", "He drags the ball back with the sole of the planted foot", correct: "b")
            if let answer {
                feedback(answer == "b", "\(answer == "b" ? "Yes." : "Watch it play.") Loading the planted foot is the fake: he turns about \(Int(lesson.events.turn.degrees.rounded()))° in half a second and the front foot takes the ball away.")
                next("Predict the exit", answer == "b")
            }
        }
        .onChange(of: answer) { _, value in
            guard value != nil, step == .predict else { return }
            model.overlays = LessonOverlays(footprints: true, paths: false, ghost: true, direction: true)
            model.play(predictTime...7.8, rate: 0.5)
        }
    }

    // 4
    private var order: some View {
        let correct = OverFakeLessonContent.order
        let finished = picked.count == correct.count
        let misplaced = PhaseOrder.misplaced(picked, correct: correct)
        return VStack(alignment: .leading, spacing: 10) {
            heading(4, "Put the moves in order", "Tap the moments in the order they happen.")
            FlowRow(spacing: 6) {
                ForEach(Array(picked.enumerated()), id: \.offset) { index, id in
                    let right = index < correct.count && correct[index] == id
                    Text("\(index + 1). \(OverFakeLessonContent.phase(id).name)")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(right ? SL.onGreen : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(right ? SL.green : SL.wrong, in: Capsule())
                }
            }
            .frame(minHeight: 30, alignment: .topLeading)
            FlowRow(spacing: 6) {
                ForEach(shuffled, id: \.self) { id in
                    Button(OverFakeLessonContent.phase(id).name) { picked.append(id) }
                        .font(.system(.footnote))
                        .foregroundStyle(SL.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(SL.cardBorder))
                        .disabled(picked.contains(id))
                        .opacity(picked.contains(id) ? 0.35 : 1)
                }
            }
            if finished {
                feedback(misplaced == 0, misplaced == 0 ? "All seven in order."
                         : "\(misplaced) out of place. The order is: \(correct.map { OverFakeLessonContent.phase($0).name }.joined(separator: " → ")).")
                HStack(spacing: 8) {
                    Button("Try again") { picked = [] }.buttonStyle(.slSecondary)
                    next("Order", misplaced == 0)
                }
            }
        }
    }

    private var summary: some View {
        let got = results.filter(\.correct).count
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(eyebrow: "STAGE 4 OF 4 · RESULTS", title: "Your answers",
                           text: got == results.count ? "You know the shape of the move. Take it to the pitch with drills 4 and 5."
                                                      : "Revisit the moments you missed in Break it down, then try again.")
            Text("\(got) / \(results.count)")
                .font(SL.display(.largeTitle))
                .foregroundStyle(SL.ink)
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Label(result.name, systemImage: result.correct ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(.footnote))
                    .foregroundStyle(result.correct ? SL.good : SL.miss)
            }
            HStack(spacing: 8) {
                Button("Try again") { results = []; step = .whichFoot }.buttonStyle(.slSecondary)
                Button("Back to Break it down") { model.enter(.breakdown) }.buttonStyle(.slPrimary)
            }
        }
    }
}
