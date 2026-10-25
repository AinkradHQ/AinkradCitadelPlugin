import AinkradAppKit
import SwiftUI

/// Why stuck (08) as the prototype acts: a fix that lands takes its card out at once (the engine's next `.stuck`
/// read is still the truth) and says what happened in a toast; a refusal is the 11 G banner.
extension CitadelStore {
    /// "Retry on hetzner-1": the issue's newest ended run again, pinned to that runner.
    func retryFix(_ stuck: StuckInfo, on runner: RunnerInfo) {
        guard let company = model?.companyID else { return }
        let name = stuckKey(stuck)
        let agent = model?.agent(stuck.agentID)
        fix(
            stuck, "Couldn't retry \(name) on \(runner.name)", outcome: "Nothing was retried.",
            toast: AinkradRichToast(
                title: "\(name) retried on \(runner.name)",
                body: "\(agent.map { "\($0.name)'s" } ?? "Its") last run starts again there", status: .success,
                icon: figure(agent))
        ) { server, issue in
            guard let run = await server.lastEndedRun(issue: issue, company: company) else {
                return ServerAnswer(status: 404, code: "not_found", message: "\(name) has no ended run to retry")
            }
            return await server.retry(run: run.id, on: runner.id)
        }
    }

    /// Reassign (or "Stop and reassign"): the issue handed to `agent`, who is woken with it.
    func reassignFix(_ stuck: StuckInfo, to agent: AgentInfo) {
        let name = stuckKey(stuck)
        fix(
            stuck, "Couldn't reassign \(name) to \(agent.name)", outcome: "It still waits where it was.",
            toast: AinkradRichToast(
                title: "\(name) → \(agent.name)", body: "Woken with the issue and its comments", status: .success,
                icon: figure(agent))
        ) { await $0.reassignIssue($1, to: agent.id) }
    }

    /// The engine's `rewake` / `requeue` by hand, `unblock`, `release_checkout`, Bump priority, Move to backlog.
    func engineFix(_ stuck: StuckInfo, _ repair: String) {
        let name = stuckKey(stuck)
        let who = model?.agent(stuck.agentID)?.name ?? "its agent"
        let (fail, outcome, title): (String, String, String) =
            switch repair {
            case "unblock": ("Couldn't unblock \(name)", "It stays blocked.", "\(name) unblocked")
            case "release_checkout": ("Couldn't release \(name)", "It stays checked out.", "\(name) released")
            case "bump": ("Couldn't bump \(name)", "Its priority is unchanged.", "\(name) moved to the front")
            case "backlog":
                ("Couldn't move \(name) to the backlog", "It stays where it was.", "\(name) is in the backlog")
            default: ("Couldn't wake \(name)'s agent", "Nobody was woken.", "\(who) woken again on \(name)")
            }
        fix(stuck, fail, outcome: outcome, toast: AinkradRichToast(title: title, status: .success)) { server, issue in
            switch repair {
            case "unblock":
                await server.unblock(issue: issue)
                    ? nil : ServerAnswer(status: 409, code: "conflict", message: "it still has open blockers")
            case "release_checkout": await server.releaseCheckout(issue: issue)
            case "bump": await server.bump(issue: issue)
            case "backlog": await server.moveToBacklog(issue: issue)
            default: await server.nudge(issue: issue)
            }
        }
    }

    /// "Send nudge": a message the live run's agent gets at its next turn, which resets the watchdog.
    func nudgeFix(_ stuck: StuckInfo, run: Int64, text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let agent = model?.agent(stuck.agentID)
        fix(
            stuck, "Couldn't message run #\(run)", outcome: "Nothing was sent.",
            toast: AinkradRichToast(
                title: "\(agent?.name ?? "The agent") got your nudge",
                body: "Delivered at its next turn · the watchdog resets",
                status: .success, icon: figure(agent))
        ) { server, _ in await server.message(run: run, body: body) }
    }

    /// "Wake my Mac" (`now`) / "Run when I'm back" (`when_back`): the sleeping runner with the agent's tags.
    func wakeFix(_ stuck: StuckInfo, when: String) {
        guard let server, let model else { return }
        let tags = model.agent(stuck.agentID)?.runnerTags ?? []
        let name = stuckKey(stuck)
        Task {
            guard let runner = sleepingRunner(for: tags, in: await server.runnerList() ?? []) else {
                actionFailure = ActionFailure(
                    title: "No runner to wake",
                    answer: ServerAnswer(
                        status: 404, code: "not_found",
                        message: "no offline runner has the tags \(tags.joined(separator: ", "))"),
                    outcome: "Nothing was sent.")
                return
            }
            if case .failure(let answer) = await server.wake(runner: runner.id, when: when) {
                actionFailure = ActionFailure(
                    title: "Couldn't wake \(runner.name)", answer: answer, outcome: "Nothing was sent.")
                return
            }
            model.stuck.removeAll { $0 == stuck }
            schedule([.stuck, .runners])
            toast(
                when == "now"
                    ? AinkradRichToast(
                        title: "Waking \(runner.name)",
                        body: "A push went to its runner · \(name) starts once it answers",
                        status: .success)
                    : AinkradRichToast(
                        title: "\(name) parked until \(runner.name) wakes", body: "It runs when you're back"))
        }
    }

    /// "Allow Power Nap runs": no confirm — the toast's Undo turns it off again.
    func powerNapFix(_ stuck: StuckInfo) {
        guard let server, let model else { return }
        let tags = model.agent(stuck.agentID)?.runnerTags ?? []
        let name = stuckKey(stuck)
        Task {
            guard let runner = sleepingRunner(for: tags, in: await server.runnerList() ?? []) else { return }
            if case .failure(let answer) = await server.setPowerNap(runner: runner.id, true) {
                actionFailure = ActionFailure(
                    title: "Couldn't allow Power Nap on \(runner.name)", answer: answer,
                    outcome: "Its preference is unchanged.")
                return
            }
            schedule([.stuck, .runners])
            toast(
                AinkradRichToast(
                    title: "Power Nap runs allowed", body: "\(name) starts at \(runner.name)'s next Power Nap window",
                    status: .success,
                    actions: [
                        AinkradRichToastAction("Undo") { [weak self] in
                            Task {
                                _ = await server.setPowerNap(runner: runner.id, false)
                                self?.schedule([.stuck, .runners])
                                self?.toast(AinkradRichToast(title: "Power Nap runs turned off"))
                            }
                        }
                    ]))
        }
    }

    private func fix(
        _ stuck: StuckInfo, _ title: String, outcome: String, toast message: AinkradRichToast,
        _ work: @escaping (CitadelServer, Int64) async -> ServerAnswer?
    ) {
        guard let issue = stuck.issueID else { return }
        perform(
            title, outcome: outcome,
            done: {
                self.model?.stuck.removeAll { $0 == stuck }
                self.schedule([.stuck, .costs, .issueFresh(issue)])
                self.toast(message)
            }
        ) { await work($0, issue) }
    }

    private func stuckKey(_ stuck: StuckInfo) -> String { model?.issue(stuck.issueID)?.key ?? "the issue" }

    private func figure(_ agent: AgentInfo?) -> AnyView? {
        guard let agent, let model else { return nil }
        return AnyView(AgentFigure(agent: agent, model: model, size: 28))
    }
}
