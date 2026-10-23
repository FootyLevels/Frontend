import Foundation
import RealityKit
import Testing
@testable import FootyLevels_Frontend

/// Lessons made by the lesson pipeline (`Lesson-*.bundle` in SampleData/Lessons): every one
/// the app ships must load, fit together and play. A broken bundle fails here.
@MainActor
struct LessonPackageTests {

    private static let shipped = ["chop-and-spin", "hocus-pocus", "skill-ladder", "three-1v1-moves", "three-levels"]

    private func entry(_ id: String) throws -> LessonLibrary.Entry {
        try #require(LessonLibrary.lessons().first { $0.id == id })
    }

    // MARK: - Data

    @Test func theLibraryListsEveryShippedLesson() {
        let lessons = LessonLibrary.lessons()
        #expect(Set(Self.shipped).isSubset(of: Set(lessons.map(\.id))))
        #expect(lessons.map(\.title) == lessons.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        for lesson in lessons {
            #expect(!lesson.skills.isEmpty, "\(lesson.id) lists no skills")
        }
    }

    /// Every bundle in the app, including ones added after these five.
    @Test(arguments: LessonLibrary.lessons().map(\.id))
    func everyBundledLessonLoadsAndFitsTogether(_ id: String) throws {
        let package = try LessonPackage.load(try entry(id).url)
        #expect(package.document.id == id)
        #expect(FileManager.default.fileExists(atPath: package.videoURL.path))
        #expect(FileManager.default.fileExists(atPath: package.motionDirectory.appendingPathComponent("sequence.json").path))
        #expect(Set(package.footSets.left).isDisjoint(with: package.footSets.right))
        for skill in package.document.skills {
            #expect((2...6).contains(skill.phases.count), "\(id)/\(skill.id) phases")
            #expect((4...5).contains(skill.drills.count), "\(id)/\(skill.id) drills")
            #expect((3...4).contains(skill.challenges.count), "\(id)/\(skill.id) challenges")
            for phase in skill.phases {
                #expect(!phase.name.isEmpty && !phase.cue.isEmpty)
                // The build fills every placeholder; one left over would show as raw text.
                #expect(!(phase.shows ?? "").contains("{{"), "\(id)/\(phase.id) has an unfilled placeholder")
            }
        }
    }

    @Test func damagedDataIsRejected() throws {
        let copy = try temporaryCopy(of: "chop-and-spin")
        defer { try? FileManager.default.removeItem(at: copy) }
        let analysisURL = copy.appendingPathComponent("analysis.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: analysisURL)) as? [String: Any])
        var frames = try #require(json["frames"] as? [String: Any])
        frames["weight"] = [0.5, 0.5]          // far shorter than the clip
        json["frames"] = frames
        try JSONSerialization.data(withJSONObject: json).write(to: analysisURL)
        #expect(throws: LessonPackage.LoadError.self) { try LessonPackage.load(copy) }

        try FileManager.default.removeItem(at: copy.appendingPathComponent("mesh.json"))
        #expect(throws: LessonPackage.LoadError.missing("mesh.json")) { try LessonPackage.load(copy) }
    }

    @Test func aSkillOutsideTheClipIsRejected() throws {
        let copy = try temporaryCopy(of: "hocus-pocus")
        defer { try? FileManager.default.removeItem(at: copy) }
        let lessonURL = copy.appendingPathComponent("lesson.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: lessonURL)) as? [String: Any])
        var skills = try #require(json["skills"] as? [[String: Any]])
        skills[0]["range"] = [0, 999]
        json["skills"] = skills
        try JSONSerialization.data(withJSONObject: json).write(to: lessonURL)
        #expect(throws: LessonPackage.LoadError.self) { try LessonPackage.load(copy) }
    }

    @Test func timeLookupsStayInsideTheClip() throws {
        let package = try LessonPackage.load(try entry("chop-and-spin").url)
        #expect(package.frame(at: -3) == 0)
        #expect(package.frame(at: .infinity) == 0)
        #expect(package.frame(at: 999) == package.analysis.frameCount - 1)
        #expect(package.shotLabel(at: 5)?.label == "Cruyff chop")
        let lastShot = package.analysis.shots.count - 1
        #expect(package.shotIndex(ofFrame: package.analysis.frameCount - 1) == lastShot)
    }

    // MARK: - Playing

    private func loaded(_ id: String) async throws -> PackageLessonModel {
        let model = try PackageLessonModel.load(try entry(id).url)
        await model.load()
        #expect(model.state == .ready)
        await model.finishLoading()
        return model
    }

    @Test func theBodyIsDrawnFromTheBundledMotion() async throws {
        let model = try await loaded("hocus-pocus")
        defer { model.teardown() }
        let body = try #require(model.stageRoot?.findEntity(named: "lesson-body"))
        // Body, then the two feet.
        #expect(body.components[ModelComponent.self]?.materials.count == 3)
        #expect(model.stageRoot?.findEntity(named: "lesson-ball") != nil)
        #expect(model.stageRoot?.findEntity(named: "lesson-ghost") != nil)
    }

    @Test func readingsFollowThePhases() async throws {
        let model = try await loaded("chop-and-spin")
        defer { model.teardown() }
        let chop = try #require(model.package.document.skills.first { $0.id == "chop" })
        model.select(chop.id)
        for phase in chop.phases {
            model.render(at: phase.key)
            #expect(model.phase?.id == phase.id)
            #expect((0...1).contains(model.weight))
            #expect(model.dropCm >= 0)
            #expect((model.turnDegrees != nil) == (phase.turn == true))
        }
    }

    @Test func choosingASkillMovesTheLessonToIt() async throws {
        let model = try await loaded("three-levels")
        defer { model.teardown() }
        #expect(model.skill.id == model.package.document.skills[0].id)
        model.enter(.practise)
        let last = try #require(model.package.document.skills.last)
        model.select(last.id)
        #expect(model.skill.id == last.id)
        #expect(model.stage == .practise)
        #expect(abs(model.playback.currentTime - last.range.lowerBound) < 0.05)
    }

    @Test func breakingDownAPhaseLoopsItAndSwitchesItsCues() async throws {
        let model = try await loaded("chop-and-spin")
        defer { model.teardown() }
        let skill = model.skill
        let phase = try #require(skill.phases.first { $0.ov != nil && $0.angle != nil })
        model.focus(on: phase)
        #expect(model.loop == phase.start...phase.end)
        #expect(model.overlays == phase.ov?.lessonOverlays)
        #expect(model.angle == phase.angle)
    }

    /// A ground move never shows the ball in the air, even where the tracker thinks it is.
    @Test func aGroundMoveKeepsTheBallOnTheTurf() async throws {
        let model = try await loaded("chop-and-spin")
        defer { model.teardown() }
        let analysis = model.package.analysis
        let radius = Float(analysis.ballDiameter / 2)

        let spin = try #require(model.package.document.skills.first { $0.id == "spin" })
        #expect(spin.ballLeavesGround == false)
        model.select(spin.id)
        let airborne = framesInRange(spin.range, model.package).filter { analysis.frames.ballAir[$0] == 1 && analysis.frames.ball[$0] != nil }
        #expect(!airborne.isEmpty)
        for frame in airborne {
            #expect(model.ballPosition(frame: frame)?.y == radius)
        }

        // The lift's ball does leave the ground.
        let lift = try #require(model.package.document.skills.first { $0.id == "flick" })
        model.select(lift.id)
        let lifted = framesInRange(lift.range, model.package).filter { analysis.frames.ballAir[$0] == 1 && analysis.frames.ball[$0] != nil }
        #expect(lifted.contains { (model.ballPosition(frame: $0)?.y ?? 0) > radius + 0.05 })
    }

    // MARK: - Helpers

    private func framesInRange(_ range: ClosedRange<Double>, _ package: LessonPackage) -> [Int] {
        Array(package.frame(at: range.lowerBound)...package.frame(at: range.upperBound))
    }

    private func temporaryCopy(of id: String) throws -> URL {
        let source = try entry(id).url
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("LessonPackageTests-\(UUID().uuidString)", isDirectory: true)
        // The video and motion aren't needed to check the data, so only the JSON is copied.
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        for name in ["lesson.json", "analysis.json", "mesh.json"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: copy.appendingPathComponent(name))
        }
        return copy
    }
}
