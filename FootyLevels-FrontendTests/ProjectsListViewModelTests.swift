import Foundation
import Testing
@testable import FootyLevels_Frontend

/// When the project list offers "Delete Video". The server enforces the same
/// rules; these keep the app from offering an action that can only fail.
@MainActor
struct ProjectsListViewModelTests {

    private func project(id: String = "a1b2c3d4", job: String? = nil, motion: String? = nil) throws -> SkillLabProject {
        var json: [String: Any] = [
            "id": id, "title": "Clip", "createdAt": "2026-10-08T12:00:00+00:00",
            "video": ["width": 720, "height": 1280, "fps": 30.0, "duration": 10.0,
                      "frameCount": 300, "url": "/assets-data/\(id)/video.mp4"],
            "frames": [],
        ]
        if let job { json["job"] = ["status": job] }
        if let motion { json["motion"] = ["status": motion] }
        return try JSONDecoder().decode(SkillLabProject.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func idleUploadedVideoCanBeDeleted() throws {
        let video = try project()
        #expect(ProjectsListViewModel().canDelete(video))
    }

    @Test func finishedReconstructionDoesNotBlockDeleting() throws {
        let video = try project(job: "complete", motion: "failed")
        #expect(ProjectsListViewModel().canDelete(video))
    }

    @Test func bundledExampleCannotBeDeleted() throws {
        let example = try project(id: BundledSample.id)
        #expect(!ProjectsListViewModel().canDelete(example))
    }

    @Test(arguments: ["queued", "running"])
    func videoBeingReconstructedCannotBeDeleted(status: String) throws {
        let model = ProjectsListViewModel()
        #expect(!model.canDelete(try project(job: status)))
        #expect(!model.canDelete(try project(motion: status)))
    }

    @Test func onlyOneDeleteRunsAtATime() throws {
        let model = ProjectsListViewModel()
        model.deletingId = "another-project"
        #expect(!model.canDelete(try project()))
    }
}
