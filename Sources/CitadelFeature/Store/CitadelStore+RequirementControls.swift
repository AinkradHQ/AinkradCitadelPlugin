import AinkradAppKit
import Foundation

/// The requirement hero's Pause / Resume and Mark done (API minor 18). Pausing holds new wakes for its issues while
/// running work finishes; Mark done needs it in progress with no issue open, and the server's refusal says so. An
/// older server is sent nothing.
extension CitadelStore {
    func pause(requirement: RequirementInfo) {
        guard hasTrancheB else { return }
        requirementWrite(requirement.id, "Couldn't pause \(requirement.key)", outcome: "It keeps running.") {
            await $0.pause(requirement: requirement.id)
        } done: { [self] model in
            setPaused(requirement.id, at: Date(), in: model)
            toast(
                AinkradRichToast(
                    title: "\(requirement.key) paused",
                    body: "Running tasks finish their current tool call; nothing new starts.", status: .warning))
        }
    }

    func resume(requirement: RequirementInfo) {
        guard hasTrancheB else { return }
        requirementWrite(requirement.id, "Couldn't resume \(requirement.key)", outcome: "It stays paused.") {
            await $0.resume(requirement: requirement.id)
        } done: { [self] model in
            setPaused(requirement.id, at: nil, in: model)
            toast(
                AinkradRichToast(
                    title: "\(requirement.key) resumed", body: "Its held tasks are scheduled again.", status: .success))
        }
    }

    func markDone(requirement: RequirementInfo) {
        guard hasTrancheB else { return }
        requirementWrite(requirement.id, "Couldn't mark \(requirement.key) done", outcome: "It is still in progress.") {
            await $0.finish(requirement: requirement.id)
        } done: { [self] model in
            if let index = model.requirements.firstIndex(where: { $0.id == requirement.id }) {
                model.requirements[index].state = "done"
                model.requirements[index].pausedAt = nil
            }
            toast(AinkradRichToast(title: "\(requirement.key) done", status: .success))
        }
    }

    private func setPaused(_ id: Int64, at date: Date?, in model: CompanyModel) {
        if let index = model.requirements.firstIndex(where: { $0.id == id }) {
            model.requirements[index].pausedAt = date
        }
    }
}
