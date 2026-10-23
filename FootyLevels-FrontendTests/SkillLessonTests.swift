import Foundation
import RealityKit
import Testing
@testable import FootyLevels_Frontend

/// The Learn tab's Over Fake lesson: its bundled measurements, the lookups and
/// scoring the screens rely on, and the 3D scene it builds.
@MainActor
struct SkillLessonTests {

    private func lesson() throws -> SkillLesson { try SkillLesson.bundled() }

    // MARK: - Data

    @Test func theBundledLessonCoversTheWholeClip() throws {
        let lesson = try lesson()
        #expect(lesson.frameCount == 242)
        #expect(lesson.frames.weight.count == lesson.frameCount)
        #expect(lesson.phases.map(\.id) == ["approach", "fake", "turn", "burst", "setup", "sell", "step", "plant",
                                             "pause", "shift", "change", "go"])
        #expect(!lesson.footSets.left.isEmpty && !lesson.footSets.right.isEmpty)
        #expect(Set(lesson.footSets.left).isDisjoint(with: lesson.footSets.right))
    }

    @Test func keyMomentsMatchTheTutorial() throws {
        let e = try lesson().events
        #expect(e.pass.frame < e.plant.frame && e.plant.frame < e.plant.transferFrame)
        #expect(e.shift.frame < e.go.frame)
        #expect(e.turn.degrees > 90)
        #expect(e.sell.dropCm > 0)
    }

    @Test func damagedDataIsRejected() throws {
        let url = try #require(BundledSample.fileURL(forAssetPath: "/assets-data/over-fake/lesson.json"))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var frames = try #require(json["frames"] as? [String: Any])
        frames["weight"] = [0.5, 0.5]          // far shorter than the clip
        json["frames"] = frames
        #expect(throws: SkillLesson.LoadError.self) {
            try SkillLesson.decode(JSONSerialization.data(withJSONObject: json))
        }
    }

    // MARK: - Lookups

    @Test func phaseAtATime() throws {
        let lesson = try lesson()
        #expect(lesson.phase(at: 0).id == "approach")
        #expect(lesson.phase(at: 4.6).id == "step")
        #expect(lesson.phase(at: 5.5).id == "pause")
        #expect(lesson.phase(at: lesson.duration).id == "go")
        #expect(lesson.shot(ofFrame: 90) == 0)
        #expect(lesson.shot(ofFrame: 91) == 1)
        #expect(lesson.frame(at: .nan) == 0)
        #expect(lesson.frame(at: 99) == lesson.frameCount - 1)
    }

    @Test func theGhostShowsThePreviousStepAndSkipsThePause() throws {
        let lesson = try lesson()
        let shift = try #require(lesson.phase("shift"))
        #expect(lesson.previousKeyPhase(before: shift)?.id == "plant")
        let setup = try #require(lesson.phase("setup"))
        #expect(lesson.previousKeyPhase(before: setup) == nil)   // first of the tutorial
    }

    // MARK: - Challenges and drills

    @Test func tapsAreJudgedAgainstTheMeasuredMoment() {
        #expect(TapVerdict.judge(tapped: nil, target: 4.67) == .missed)
        #expect(TapVerdict.judge(tapped: 4.70, target: 4.67).isCorrect)
        if case .early(let by) = TapVerdict.judge(tapped: 4.40, target: 4.67) { #expect(abs(by - 0.27) < 1e-9) } else { Issue.record("expected early") }
        if case .late = TapVerdict.judge(tapped: 4.90, target: 4.67) {} else { Issue.record("expected late") }
    }

    @Test func phaseOrderCountsMisplacedPicks() {
        let right = OverFakeLessonContent.order
        #expect(PhaseOrder.misplaced(right, correct: right) == 0)
        var swapped = right
        swapped.swapAt(0, 1)
        #expect(PhaseOrder.misplaced(swapped, correct: right) == 2)
        #expect(PhaseOrder.misplaced(Array(right.prefix(5)), correct: right) == 2)
    }

    @Test func aDrillIsDoneWithAllRepsAndChecks() {
        var progress = DrillProgress()
        #expect(!progress.isComplete(targetReps: 2, checkCount: 2))
        progress.reps = 2
        progress.setCheck(1, true)
        #expect(!progress.isComplete(targetReps: 2, checkCount: 2))
        progress.setCheck(0, true)
        #expect(progress.isComplete(targetReps: 2, checkCount: 2))
    }

    @Test func drillProgressIsKeptBetweenLaunches() throws {
        let suite = "SkillLessonTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DrillProgressStore(defaults: defaults).update("still") { $0.reps = 4; $0.setCheck(2, true) }
        let reopened = DrillProgressStore(defaults: defaults)
        #expect(reopened.progress("still") == DrillProgress(reps: 4, checks: [false, false, true]))
        reopened.reset("still")
        #expect(DrillProgressStore(defaults: defaults).progress("still") == DrillProgress())
    }

    @Test func everyPhaseHasCoachingText() throws {
        let lesson = try lesson()
        for phase in lesson.phases {
            let content = OverFakeLessonContent.phase(phase.id)
            #expect(!content.name.isEmpty && !content.cue.isEmpty)
            if phase.shot == 1 { #expect(!content.shows(lesson).isEmpty) }
        }
    }

    // MARK: - 3D

    private func loaded() async throws -> SkillLessonModel {
        let model = try SkillLessonModel.bundled()
        await model.load()
        #expect(model.state == .ready)
        return model
    }

    @Test func theBodyIsDrawnWithItsFeetHighlighted() async throws {
        let model = try await loaded()
        defer { model.teardown() }
        let body = try #require(model.stageRoot?.findEntity(named: "lesson-body"))
        // Body, front foot, stepping foot.
        #expect(body.components[ModelComponent.self]?.materials.count == 3)
        #expect(model.stageRoot?.findEntity(named: "lesson-ball") != nil)
    }

    @Test func readingsFollowTheMovement() async throws {
        let model = try await loaded()
        defer { model.teardown() }
        let lesson = model.lesson

        model.render(at: 3.5)
        #expect(model.phase.id == "setup")
        #expect(model.frontPlanted && model.stepPlanted)

        // The contact light needs the foot down and nearly still, so it comes
        // on a few frames after touch-down; by the weight transfer it's on.
        model.render(at: lesson.time(ofFrame: lesson.events.plant.transferFrame))
        #expect(model.phase.id == "plant")
        #expect(model.stepPlanted)

        model.render(at: 7.1)
        #expect(model.phase.id == "change")
        #expect((model.turnDegrees ?? 0) > 60)

        model.render(at: 4.0)
        #expect(model.turnDegrees == nil)
    }

    @Test func mirrorAndGhostChangeTheScene() async throws {
        let model = try await loaded()
        defer { model.teardown() }
        await model.finishLoading()   // the ghost's pose is in a later chunk

        model.mirror = true
        #expect(model.stageRoot?.scale.x == -1)

        model.overlays.ghost = true
        model.render(at: 6.5)   // shift: the ghost shows the plant
        #expect(model.stageRoot?.findEntity(named: "lesson-ghost")?.isEnabled == true)

        model.overlays.ghost = false
        model.render(at: 6.5)
        #expect(model.stageRoot?.findEntity(named: "lesson-ghost")?.isEnabled == false)
    }
}
