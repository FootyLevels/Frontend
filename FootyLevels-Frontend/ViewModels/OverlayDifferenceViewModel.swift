import Foundation
import Observation

/// The two sides of an overlay: A is the person's own attempt, B the one it's
/// compared against.
enum OverlaySlot: String, CaseIterable, Identifiable {
    case first = "A"
    case second = "B"

    var id: String { rawValue }

    var role: String {
        switch self {
        case .first: return "You"
        case .second: return "Reference"
        }
    }
}

/// The "Overlay" tab's setup: which two videos to compare, and getting each
/// one's 3D motion built so the comparison can open.
@MainActor
@Observable
final class OverlayDifferenceViewModel {
    typealias Slot = OverlaySlot

    private(set) var chosen: [Slot: SkillLabProject] = [:]
    /// The project whose motion build is being requested.
    var startingId: String?
    var errorMessage: String?

    func project(in slot: Slot) -> SkillLabProject? { chosen[slot] }

    /// The same video may fill both slots — comparing two attempts within
    /// one clip is a fair use.
    func choose(_ project: SkillLabProject, for slot: Slot) {
        chosen[slot] = project
        errorMessage = nil
    }

    var canCompare: Bool {
        Slot.allCases.allSatisfy { chosen[$0]?.motion?.isPlayable == true }
    }

    /// Whether to offer "Build 3D motion" for a chosen video.
    func canBuildMotion(_ project: SkillLabProject) -> Bool {
        startingId == nil && !BundledSample.isSample(project.id) && !project.isBusy
            && project.motion?.isPlayable != true
    }

    func buildMotion(for slot: Slot) async {
        guard let project = chosen[slot], canBuildMotion(project) else { return }
        startingId = project.id
        errorMessage = nil
        defer { startingId = nil }
        do {
            try await SkillLabClient.shared.startMotion(projectId: project.id)
            replace(try await SkillLabClient.shared.project(id: project.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Changes whenever a chosen video starts or stops building, so the view
    /// can restart `pollWhileBuilding`.
    var pollKey: String {
        Slot.allCases.map { slot in
            chosen[slot].map { "\($0.id):\($0.isBusy)" } ?? "-"
        }.joined(separator: "|")
    }

    /// Building motion runs on the server for minutes and reports only through
    /// the project document, so re-read the chosen videos while any is busy.
    func pollWhileBuilding(every interval: Duration = .seconds(3)) async {
        while !Task.isCancelled, chosen.values.contains(where: \.isBusy) {
            try? await Task.sleep(for: interval)
            for project in Set(chosen.values.filter(\.isBusy).map(\.id)) {
                if let latest = try? await SkillLabClient.shared.project(id: project) {
                    replace(latest)
                }
            }
        }
    }

    /// Updates every slot holding this project.
    private func replace(_ project: SkillLabProject) {
        for (slot, current) in chosen where current.id == project.id {
            chosen[slot] = project
        }
    }
}
