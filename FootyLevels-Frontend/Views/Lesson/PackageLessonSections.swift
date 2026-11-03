import SwiftUI

private let ballColor = Color(uiColor: SL.overlaySecond)
private let goodColor = SL.good
private let missColor = SL.miss

// MARK: - 1. Watch

struct PackageWatchSection: View {
    let model: PackageLessonModel

    private var skill: LessonDocument.Skill { model.skill }

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 1 OF 4 · WATCH", title: skill.watchTitle ?? "Watch it at match speed", text: skill.intro)
            VStack(spacing: 8) {
                ForEach(Array(skill.notice.enumerated()), id: \.offset) { _, moment in
                    let live = model.phase != nil && model.phase == skill.phase(at: moment.t)
                    Button {
                        model.freeze(at: moment.t)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%.2f s", moment.t))
                                .font(.system(.caption, weight: .semibold).monospacedDigit())
                                .foregroundStyle(ballColor)
                                .frame(minWidth: 52, alignment: .leading)
                            Text("\(Text("\(moment.title). ").fontWeight(.semibold))\(moment.text)")
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
                Button("Full speed") { model.play(skill.watch, rate: 1) }.buttonStyle(.slSecondary)
                Button("Half speed") { model.play(skill.watch, rate: 0.5) }.buttonStyle(.slSecondary)
                Spacer(minLength: 0)
                Button("Break it down") { model.enter(.breakdown) }.buttonStyle(.slPrimary)
            }
        }
        SectionCard {
            Eyebrow(text: "WHY THE 3D HELPS", color: SL.muted)
            Text("The 3D body is reconstructed from this video. Turn the camera, see which foot carries the weight, and follow the feet and the ball. Orange is the ball foot, blue the standing foot.")
                .font(.system(.footnote))
                .foregroundStyle(SL.ink)
            if let adds = skill.adds {
                Text(adds)
                    .font(.system(.footnote))
                    .foregroundStyle(SL.ink)
            }
        }
        if let unsure = skill.unsure, !unsure.isEmpty {
            SectionCard {
                Eyebrow(text: "WHAT THIS CLIP CAN'T TELL US", color: SL.muted)
                ForEach(Array(unsure.enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "questionmark.circle")
                        .font(.system(.caption))
                        .foregroundStyle(SL.muted)
                }
            }
        }
    }
}

// MARK: - 2. Break it down

struct PackageBreakdownSection: View {
    let model: PackageLessonModel
    @State private var open: String?

    private var skill: LessonDocument.Skill { model.skill }

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 2 OF 4 · STEP BY STEP", title: "Break it down",
                           text: skill.breakdownIntro ?? "\(skill.phases.count) moments, in order. Open one to freeze on it; play it to loop it at half speed. The cues in the 3D switch to what matters for that moment.")
        }
        VStack(spacing: 8) {
            ForEach(Array(skill.phases.enumerated()), id: \.element.id) { index, phase in
                phaseCard(phase, number: index + 1)
            }
        }
        .onAppear { open = open ?? skill.phases.first?.id }
        Button("Practise it") { model.enter(.practise) }
            .buttonStyle(.slPrimaryWide)
    }

    private func phaseCard(_ phase: LessonDocument.Phase, number: Int) -> some View {
        let isOpen = open == phase.id
        let live = model.phase == phase
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                open = isOpen ? nil : phase.id
                if !isOpen { model.focus(on: phase) }
            } label: {
                HStack(spacing: 10) {
                    NumberBadge(text: "\(number)", filled: live, color: ballColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.name.uppercased())
                            .font(SL.display(.body))
                            .foregroundStyle(SL.ink)
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
                    Text(phase.cue.uppercased())
                        .font(SL.display(.body))
                        .foregroundStyle(ballColor)
                    if let shows = phase.shows { fact("In the 3D", shows) }
                    if let video = phase.video { fact("In the video", video) }
                    if let confidence = phase.confidence {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(confidence.label.uppercased())
                                .font(.system(.caption2, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(confidence.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(confidence.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            if let why = phase.why {
                                Text(why)
                                    .font(.system(.caption))
                                    .foregroundStyle(SL.muted)
                            }
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

struct PackagePractiseSection: View {
    let model: PackageLessonModel
    @State private var store: DrillProgressStore

    init(model: PackageLessonModel) {
        self.model = model
        // Progress is kept per lesson and skill: drill ids repeat between skills.
        _store = State(initialValue: DrillProgressStore(key: "lesson.\(model.package.document.id).\(model.skill.id).drills"))
    }

    private var drills: [LessonDocument.Drill] { model.skill.drills }

    var body: some View {
        SectionCard {
            SectionHeading(eyebrow: "STAGE 3 OF 4 · ON THE PITCH", title: "Practise it",
                           text: "\(drills.count) drills, from walking pace to a live defender. Play the model, do the reps, then tick what you managed. Turn on Mirror to learn it on your other foot.")
        }
        VStack(spacing: 10) {
            ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                drillCard(drill, number: index + 1)
            }
        }
        Button("Test yourself") { model.enter(.test) }
            .buttonStyle(.slPrimaryWide)
    }

    private func drillCard(_ drill: LessonDocument.Drill, number: Int) -> some View {
        let progress = store.progress(drill.id)
        let done = progress.isComplete(targetReps: drill.reps, checkCount: drill.checks.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NumberBadge(text: done ? "✓" : "\(number)", filled: done, color: goodColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.lvl.uppercased())
                        .font(.system(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(SL.muted)
                    Text(drill.title)
                        .font(SL.display(.title3))
                        .foregroundStyle(SL.ink)
                }
                Spacer(minLength: 0)
                Button {
                    model.play(drill.model, rate: drill.rate)
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
                            .fill(rep < progress.reps ? goodColor : .clear)
                            .overlay(Circle().stroke(rep < progress.reps ? goodColor : SL.muted, lineWidth: 1.2))
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
        .slPanel(fill: SL.card, border: done ? goodColor : SL.cardBorder, radius: 10)
    }
}

// MARK: - 4. Test yourself

/// Plays the skill's challenges in order, then shows the results.
struct PackageTestSection: View {
    let model: PackageLessonModel

    @State private var index = 0
    @State private var results: [(name: String, correct: Bool)] = []
    @State private var answer: Int?
    @State private var tap: TapVerdict?
    @State private var waitingForTap = false
    @State private var picked: [String] = []

    private var challenges: [LessonDocument.Challenge] { model.skill.challenges }
    private var current: LessonDocument.Challenge? { challenges.indices.contains(index) ? challenges[index] : nil }

    var body: some View {
        SectionCard {
            if let current {
                switch current {
                case .choice(let choice): choiceView(choice)
                case .tap(let tap): tapView(tap)
                case .order(let order): orderView(order)
                }
            } else {
                summary
            }
        }
        .onAppear { prepare() }
        .onChange(of: index) { _, _ in prepare() }
        .onChange(of: model.autoStops) { _, _ in
            if waitingForTap, case .tap(let challenge) = current { finishTap(nil, challenge) }
        }
    }

    private func prepare() {
        answer = nil
        tap = nil
        waitingForTap = false
        picked = []
        switch current {
        case .choice(let choice):
            model.overlays = LessonOverlays(footprints: true, paths: true, ghost: false, direction: false)
            if let angle = LessonDocument.angle(for: choice.view) { model.show(angle) }
            model.freeze(at: choice.t)
        case .tap(let challenge):
            model.overlays = LessonOverlays(footprints: false, paths: true, ghost: false, direction: false)
            model.freeze(at: challenge.from)
        case .order, .none:
            break
        }
    }

    private func heading(_ title: String, _ text: String) -> some View {
        SectionHeading(eyebrow: "STAGE 4 OF 4 · CHALLENGE \(index + 1) OF \(challenges.count)", title: title, text: text)
    }

    private func next(_ name: String, _ correct: Bool) -> some View {
        Button(index == challenges.count - 1 ? "See results" : "Next challenge") {
            results.append((name, correct))
            index += 1
        }
        .buttonStyle(.slPrimary)
    }

    private func feedback(_ good: Bool, _ text: String) -> some View {
        Text(text)
            .font(.system(.footnote))
            .foregroundStyle(SL.ink)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(good ? goodColor.opacity(0.12) : SL.noticeFill, in: RoundedRectangle(cornerRadius: 8))
    }

    // Choice

    private func choiceView(_ choice: LessonDocument.Challenge.Choice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(choice.title, choice.prompt)
            ForEach(Array(choice.options.enumerated()), id: \.offset) { option, text in
                optionButton(option, text, correct: choice.answer) { pick(option, in: choice) }
            }
            if let answer {
                feedback(answer == choice.answer, "\(answer == choice.answer ? "Right." : "Not quite.") \(choice.explain)")
                next(choice.title, answer == choice.answer)
            }
        }
    }

    private func pick(_ option: Int, in choice: LessonDocument.Challenge.Choice) {
        guard answer == nil else { return }
        answer = option
        // Then show what happens.
        if let play = choice.play, play.count >= 2 {
            model.overlays = LessonOverlays(footprints: true, paths: true, ghost: true, direction: true)
            model.play(play[0]...Swift.max(play[0], play[1]), rate: play.count > 2 ? Float(play[2]) : 0.5)
        }
    }

    private func optionButton(_ option: Int, _ text: String, correct: Int, action: @escaping () -> Void) -> some View {
        let chosen = answer == option
        let reveal = answer != nil
        let isRight = option == correct
        return Button(action: action) {
            Text(text)
                .font(.system(.subheadline))
                .foregroundStyle(SL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(reveal && isRight ? goodColor.opacity(0.12) : (chosen ? missColor.opacity(0.1) : .clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(reveal && isRight ? goodColor : (chosen ? missColor : SL.cardBorder)))
        }
        .buttonStyle(.plain)
        .disabled(reveal)
    }

    // Tap

    private func tapView(_ challenge: LessonDocument.Challenge.Tap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(challenge.title, challenge.prompt)
            HStack(spacing: 8) {
                Button("Start") {
                    tap = nil
                    waitingForTap = true
                    model.play(from: challenge.from, rate: Float(challenge.rate ?? 0.5),
                               stopAt: challenge.target + tolerance(challenge) + 0.4)
                }
                .buttonStyle(.slSecondary)
                .disabled(waitingForTap)
                Button(challenge.label) { finishTap(model.playback.currentTime, challenge) }
                    .buttonStyle(.slPrimary)
                    .disabled(!waitingForTap)
            }
            if let tap {
                feedback(tap.isCorrect, tapText(tap, challenge))
                HStack(spacing: 8) {
                    Button("Try again") { prepare() }.buttonStyle(.slSecondary)
                    next(challenge.title, tap.isCorrect)
                }
            }
        }
    }

    private func tolerance(_ challenge: LessonDocument.Challenge.Tap) -> Double { challenge.tolerance ?? 0.15 }

    private func finishTap(_ tapped: Double?, _ challenge: LessonDocument.Challenge.Tap) {
        waitingForTap = false
        model.freeze(at: challenge.target)
        tap = TapVerdict.judge(tapped: tapped, target: challenge.target, tolerance: tolerance(challenge))
    }

    private func tapText(_ verdict: TapVerdict, _ challenge: LessonDocument.Challenge.Tap) -> String {
        let moment = String(format: "It happens at %.2f s; the video is frozen there. ", challenge.target) + challenge.explain
        switch verdict {
        case .missed: return "No tap that time. \(moment)"
        case .onTime(let error): return "Spot on, \(Int(abs(error) * 1000)) ms \(error < 0 ? "early" : "late"). \(moment)"
        case .early(let by): return String(format: "%.2f s early. ", by) + moment
        case .late(let by): return String(format: "%.2f s late. ", by) + moment
        }
    }

    // Order

    private func orderView(_ order: LessonDocument.Challenge.Order) -> some View {
        let correct = order.ids
        let choices = order.shuffled ?? Array(correct.reversed())
        let finished = picked.count == correct.count
        let misplaced = PhaseOrder.misplaced(picked, correct: correct)
        return VStack(alignment: .leading, spacing: 10) {
            heading(order.title ?? "Put it in order", order.prompt ?? "Tap the moments in the order they happen.")
            FlowRow(spacing: 6) {
                ForEach(Array(picked.enumerated()), id: \.offset) { index, id in
                    let right = index < correct.count && correct[index] == id
                    Text("\(index + 1). \(name(id))")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(right ? SL.onGreen : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(right ? SL.green : SL.wrong, in: Capsule())
                }
            }
            .frame(minHeight: 30, alignment: .topLeading)
            FlowRow(spacing: 6) {
                ForEach(choices, id: \.self) { id in
                    Button(name(id)) { picked.append(id) }
                        .font(.system(.footnote))
                        .foregroundStyle(SL.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(SL.cardBorder))
                        .disabled(picked.contains(id) || finished)
                        .opacity(picked.contains(id) ? 0.35 : 1)
                }
            }
            if finished {
                feedback(misplaced == 0, misplaced == 0 ? "All in order."
                         : "\(misplaced) out of place. The order is: \(correct.map(name).joined(separator: " → ")).")
                HStack(spacing: 8) {
                    Button("Try again") { picked = [] }.buttonStyle(.slSecondary)
                    next(order.title ?? "Order", misplaced == 0)
                }
            }
        }
    }

    private func name(_ id: String) -> String {
        model.skill.phases.first { $0.id == id }?.name ?? id
    }

    // Results

    private var summary: some View {
        let got = results.filter(\.correct).count
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(eyebrow: "STAGE 4 OF 4 · RESULTS", title: "Your answers",
                           text: got == results.count ? "You know the shape of the move. Take it to the pitch with the later drills."
                                                      : "Revisit the moments you missed in Break it down, then try again.")
            Text("\(got) / \(results.count)")
                .font(SL.display(.largeTitle))
                .foregroundStyle(SL.ink)
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Label(result.name, systemImage: result.correct ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(.footnote))
                    .foregroundStyle(result.correct ? goodColor : missColor)
            }
            HStack(spacing: 8) {
                Button("Try again") { results = []; index = 0 }.buttonStyle(.slSecondary)
                Button("Back to Break it down") { model.enter(.breakdown) }.buttonStyle(.slPrimary)
            }
        }
    }
}
