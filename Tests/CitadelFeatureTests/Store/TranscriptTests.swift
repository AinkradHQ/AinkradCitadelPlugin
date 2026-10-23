import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// Transcript chunk → tool card (status, edit counts, redactions, the approval it waits on), and the run rail's
/// arithmetic.
@MainActor
final class TranscriptTests: XCTestCase {
    private func calls(_ items: [TranscriptItem]) -> [ToolCallItem] {
        items.compactMap { if case .tool(let call) = $0 { call } else { nil } }
    }

    func testAToolCallRunsUntilTheHarnessMovesOnThenSucceeds() {
        let chunks = CompanyFixture.transcript
        let items = Transcript.items(Array(chunks.prefix(5)), runState: "running")
        let tools = calls(items)
        XCTAssertEqual(tools.map(\.name), ["Read", "Edit", "Edit", "Bash"])
        XCTAssertEqual(tools.map(\.status), [.succeeded, .succeeded, .succeeded, .running], "only the newest runs")
        guard case .text(_, let text, _)? = items.first else { return XCTFail("text first") }
        XCTAssertTrue(text.hasPrefix("The stream drops events"))
    }

    func testAToolResultEndsItsCallWithExitDurationAndOutput() {
        let at = Date(timeIntervalSince1970: 1_000)
        func chunk(_ seq: Int64, _ kind: String, _ fields: [String: String]) -> TranscriptChunkInfo {
            TranscriptChunkInfo(seq: seq, at: at.addingTimeInterval(Double(seq)), kind: kind, fields: fields)
        }
        let chunks = [
            chunk(1, "tool_use", ["id": "t1", "name": "Bash", "input.command": "cargo test"]),
            chunk(2, "tool_use", ["id": "t2", "name": "Bash", "input.command": "cargo build"]),
            chunk(
                3, "tool_result",
                [
                    "id": "t1", "status": "error", "exit_code": "101", "duration_ms": "4200",
                    "output": "test db::writes ... FAILED [redacted:GITHUB_TOKEN]", "output_bytes": "90000",
                ]),
            chunk(4, "tool_result", ["id": "t2", "status": "ok", "exit_code": "0", "duration_ms": "800"]),
        ]
        let tools = calls(Transcript.items(chunks, runState: "running"))
        XCTAssertEqual(tools.map(\.status), [.failed, .succeeded], "each result finds its own call by id")
        XCTAssertEqual(tools[0].result, .summary("exit 101 · 4.2 s"))
        XCTAssertEqual(tools[1].result, .success("exit 0 · 0.8 s"))
        XCTAssertEqual(tools[0].output, "test db::writes ... FAILED [redacted:GITHUB_TOKEN]")
        XCTAssertEqual(tools[0].footnote, "output cut to its head and tail · 90000 bytes in all")
        XCTAssertEqual(tools[0].secrets, ["GITHUB_TOKEN"])
        XCTAssertNil(tools[1].output)
    }

    func testAnEditCountsItsLinesAndCarriesItsDiff() {
        let edit = calls(Transcript.items(CompanyFixture.transcript, runState: "running"))[1]
        XCTAssertEqual(edit.result, .counts(added: 1, removed: 1))
        XCTAssertEqual(edit.edit?.path, "citadel/crates/citadel-server/src/stream.rs")
    }

    func testRedactedSecretsBecomeChipsNeverValues() {
        let bash = calls(Transcript.items(CompanyFixture.transcript, runState: "running"))[3]
        XCTAssertEqual(Set(bash.secrets), ["GITHUB_TOKEN", "run token"])
        XCTAssertEqual(bash.result, .summary("2 secrets redacted"))
        XCTAssertFalse(bash.argument.contains("[redacted:"))
        XCTAssertEqual(Redaction.masked("a [redacted:bearer] b"), "a 🔒bearer b")
    }

    func testTheCallAPendingApprovalAsksAboutWaitsAndOnlyThen() {
        let waiting = calls(Transcript.items(CompanyFixture.transcript, runState: "running", waitingRequest: "r7"))
        XCTAssertEqual(waiting.last?.status, .waiting)
        let answered = calls(Transcript.items(CompanyFixture.transcript, runState: "running", waitingRequest: nil))
        XCTAssertEqual(answered.last?.status, .succeeded, "an answered approval leaves the call to finish")
    }

    func testAFailedRunFailsTheCallItWasIn() {
        let chunks = Array(CompanyFixture.transcript.prefix(6))
        XCTAssertEqual(calls(Transcript.items(chunks, runState: "failed")).last?.status, .failed)
        XCTAssertEqual(calls(Transcript.items(chunks, runState: "succeeded")).last?.status, .succeeded)
    }

    func testSystemLinesSitInTimeOrder() {
        let note = RunNote(
            at: CompanyFixture.now.addingTimeInterval(-150), action: "run.provider_dropped", text: "drop")
        let items = Transcript.items(CompanyFixture.transcript, notes: [note], runState: "running")
        let index = items.firstIndex { if case .note = $0 { true } else { false } }
        XCTAssertEqual(index, 4, "after the edits (180 s ago), before the env call (120 s ago)")
    }

    func testTheMeterBurnRateAndTimeToCap() {
        var run = CompanyFixture.run(1, agent: 4, issue: 42, minutes: 4, tokens: 80_000)
        run.startedAt = CompanyFixture.now.addingTimeInterval(-240)
        let meter = RunMeter(run: run, cap: 200_000, warnFraction: 0.8, now: CompanyFixture.now)
        XCTAssertEqual(meter.level, .ok)
        XCTAssertEqual(meter.perMinute ?? 0, 20_000, accuracy: 1)
        XCTAssertEqual(meter.minutesLeft ?? 0, 6, accuracy: 0.01)
        run.inputTokens = 170_000
        XCTAssertEqual(RunMeter(run: run, cap: 200_000, warnFraction: 0.8).level, .warning)
    }

    func testStageTimingsFollowTheRunsStamps() {
        let stages = StageTimings(run: CompanyFixture.run(1, agent: 4, issue: 42, minutes: 1, tokens: 1))
        XCTAssertEqual(stages.rows.map(\.name), ["Wake → claimed", "Setup · worktrees", "Harness up", "First token"])
        XCTAssertEqual(stages.rows.map(\.seconds).reduce(0, +), stages.total ?? 0, accuracy: 0.001)
        XCTAssertEqual(stages.total ?? 0, 9, accuracy: 0.001)
    }

    func testAWeekOfRunsCountsHowEachEnded() {
        let model = CompanyFixture.model()
        CompanyFixture.agentPage(model)
        let week = WeekOfRuns(runs: model.agentRuns[4] ?? [], now: CompanyFixture.now)
        XCTAssertEqual(week.bars.count, 7)
        XCTAssertEqual(week.caption, "6 runs · 3 succeeded · 1 failed · 1 cap hit")
    }
}
