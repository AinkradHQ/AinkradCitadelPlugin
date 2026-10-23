import Foundation

/// Pause, resume, stop, message and allow-for-issue (screens 02–06). The server's audit events reload what changed;
/// a refusal becomes `actionFailure` (mockup 11 G).
extension CitadelStore {
    /// Pause parks the agent once its current tool call ends; new wakes queue until Resume.
    func setPaused(_ agent: AgentInfo, _ paused: Bool) {
        perform(
            paused ? "Couldn't pause \(agent.name)" : "Couldn't resume \(agent.name)",
            outcome: paused ? "It keeps running." : "It stays paused."
        ) { server in
            paused ? await server.pause(agent: agent.id) : await server.resume(agent: agent.id)
        }
    }

    /// Every active agent of the company paused (or resumed) at once: Home's ⏸.
    func setCompanyPaused(_ paused: Bool) {
        guard let id = company?.id else { return }
        perform(
            paused ? "Couldn't pause all runs" : "Couldn't resume all runs",
            outcome: paused ? "Nothing was paused." : "Nothing was resumed."
        ) { server in
            paused ? await server.pause(company: id) : await server.resume(company: id)
        }
    }

    /// Ends the run now; its runner kills the harness.
    func stop(run: Int64) {
        perform("Couldn't stop run #\(run)", outcome: "It keeps running.") { await $0.stop(run: run) }
    }

    /// A message the agent gets at its next turn; `sent` runs once the server took it.
    func message(run: Int64, _ text: String, sent: @escaping @MainActor () -> Void) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        perform("Couldn't message run #\(run)", outcome: "Nothing was sent.", done: sent) {
            await $0.message(run: run, body: body)
        }
    }

    /// Approves the escalation and lets the same call run on its issue without asking again for a while.
    func allowForIssue(_ approval: ApprovalInfo, reply: String?) {
        let reply = reply.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        perform(
            "Couldn't allow it for the issue", outcome: "Nothing was allowed.",
            done: { self.model?.answer(approval, approved: true, reply: reply) }
        ) { server in
            await server.allowForIssue(approval: approval.id, reply: reply)
        }
    }

    private func perform(
        _ title: String, outcome: String, done: @escaping @MainActor () -> Void = {},
        _ work: @escaping (CitadelServer) async -> ServerAnswer?
    ) {
        guard let server else { return }
        Task {
            if let answer = await work(server) {
                actionFailure = ActionFailure(title: title, answer: answer, outcome: outcome)
            } else {
                done()
            }
        }
    }

}
