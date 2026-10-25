import AinkradAppKit
import AppKit
import Foundation

/// The Runs screen: the company's newest runs, then run events keep them current (`reload(.run)`); the peek
/// drawer's transcript, and the run actions the Runs and Run screens share (nudge, retry, the JSONL download, the
/// link).
extension CitadelStore {
    func loadRunsPage() {
        guard let server, let model else { return }
        Task {
            // ponytail: one read per unknown issue; a batch issue read if the list grows past 100 runs.
            guard let runs = await server.companyRuns(company: model.companyID, limit: 100) else { return }
            model.companyRuns = runs
            for issue in Set(runs.compactMap(\.issueID)) where model.issues[issue] == nil {
                model.issues[issue] = await server.issue(issue)
            }
        }
    }

    /// The peek drawer opened on a run: its steps come from its transcript, read once.
    func peek(run id: Int64?) {
        model?.runsPage.peekID = id
        guard let id, let model, let server, model.transcripts[id] == nil else { return }
        Task { model.transcripts[id] = await server.transcript(run: id) ?? [] }
    }

    /// Nudge a stalling run in place: its issue's next actor is woken again (`POST /issues/{id}/nudge`), which
    /// resets the watchdog.
    func nudge(run: RunInfo) {
        guard let issue = run.issueID else { return }
        let name = model?.agent(run.agentID)?.name ?? "The agent"
        perform(
            "Couldn't nudge \(name)", outcome: "Nobody was woken.",
            done: {
                self.toast(
                    AinkradRichToast(
                        title: "\(name) picked it up", body: "Nudge delivered · watchdog reset", status: .success))
            }
        ) { await $0.nudge(issue: issue) }
    }

    /// Retry an ended run on the runner it ran on (the server needs one named).
    func retry(run: RunInfo) {
        guard let runner = run.runnerID else { return }
        let key = model?.issue(run.issueID)?.key ?? "Run #\(run.id)"
        perform(
            "Couldn't retry run #\(run.id)", outcome: "Nothing was retried.",
            done: {
                self.toast(
                    AinkradRichToast(
                        title: "\(key) queued again", body: "A runner picks it up in a few seconds.", status: .success))
            }
        ) { await $0.retry(run: run.id, on: runner) }
    }

    /// Stops a live run and says so.
    func stopWithToast(_ run: RunInfo) {
        let key = model?.issue(run.issueID)?.key
        perform(
            "Couldn't stop run #\(run.id)", outcome: "It keeps running.",
            done: {
                self.toast(
                    AinkradRichToast(
                        title: "Run #\(run.id) stopped",
                        body: key.map { "\($0) is back in the queue" } ?? "The worktree and branch are kept",
                        status: .warning))
            }
        ) { await $0.stop(run: run.id) }
    }

    /// Pause all: every agent parks after its current tool call.
    func pauseAll() {
        setCompanyPaused(true)
        toast(AinkradRichToast(title: "Pausing all runs", body: "Each agent parks after its current tool call"))
    }

    /// `citadel://run/418` on the pasteboard.
    func copyRunLink(_ run: RunInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("citadel://run/\(run.id)", forType: .string)
        toast(AinkradRichToast(title: "Link copied", body: "citadel://run/\(run.id)"))
    }

    /// A tool call's argument on the pasteboard.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast(AinkradRichToast(title: "Copied", body: text))
    }

    /// The run's transcript as JSON lines (one chunk per line), saved where you choose.
    func downloadTranscript(_ run: RunInfo) {
        let lines = (model?.transcripts[run.id] ?? []).map(Self.jsonLine)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "run-\(run.id).jsonl"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
            toast(AinkradRichToast(title: "Transcript saved", body: url.lastPathComponent, status: .success))
        } catch {
            Log.connection.error("transcript save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func jsonLine(_ chunk: TranscriptChunkInfo) -> String {
        var object: [String: Any] = ["seq": chunk.seq, "type": chunk.kind, "at": chunk.at.ISO8601Format()]
        for (key, value) in chunk.fields { object[key] = value }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Where a run's chips and tiles lead.
extension CitadelStore {
    func go(_ screen: Screen) {
        isShowingSettings = false
        detail = nil
        self.screen = screen
    }

    func goRequirement(_ id: Int64) {
        model?.requirementsPage.selectedID = id
        go(.requirements)
    }

    /// The company's limits (where the run and issue caps are raised).
    func goLimits() {
        model?.limitsPage.section = .limits
        isShowingSettings = true
    }
}
