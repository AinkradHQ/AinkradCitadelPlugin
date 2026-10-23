import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 10 and 15's writes: waking a runner, adding an account (never its secret), and Last fallbacks from the
/// runs list. Every time is fixed — never `Date()`.
@MainActor
final class PoolActionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWakeWhenBackPostsItsModeAndTheCardShowsTheRequest() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/runners/4/wake", request.httpMethod == "POST" else {
                return .init(status: 404)
            }
            return .init(
                json:
                    #"{"id":4,"name":"oracle-arm","status":"offline","tags":["linux"],"wake_mode":"when_back","wake_requested_at":"2026-10-23T10:00:00.000Z"}"#
            )
        }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        store.wakeRunner(4, when: "when_back")
        await eventually { model.runnersPage.runners.first { $0.id == 4 }?.wakeMode != nil }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/runners/4/wake" })
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.sentBody)) as? [String: String])
        XCTAssertEqual(sent["when"], "when_back")
        XCTAssertEqual(model.runnersPage.runners.first { $0.id == 4 }?.wakeMode, "when_back")
        XCTAssertNil(model.runnersPage.failures[4])
    }

    func testARefusedWakeSaysWhatTheServerSaidOnTheCard() async throws {
        FakeServer.serve { _ in .init(status: 409, json: #"{"code":"conflict","message":"It is online."}"#) }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        store.wakeRunner(4, when: "now")
        await eventually { model.runnersPage.failures[4] != nil }
        let failure = try XCTUnwrap(model.runnersPage.failures[4])
        XCTAssertEqual(failure.title, "Couldn't wake oracle-arm")
        XCTAssertEqual(failure.message, "The server answered 409: It is online. Nothing was pushed.")
    }

    func testTheWakeLineSaysWhatHappensNext() {
        var runner = RunnerInfo(
            id: 3, name: "ahmed-mbp", status: "offline", healthReason: nil, lastSeenAt: nil, tags: [])
        XCTAssertNil(runner.wakeLine(now: now))
        runner.wakeMode = "now"
        runner.wakeRequestedAt = now.addingTimeInterval(-120)
        XCTAssertEqual(runner.wakeLine(now: now)?.title, "Wake requested 2m ago.")
        runner.wakeMode = "when_back"
        XCTAssertEqual(runner.wakeLine(now: now)?.title, "Runs when you're back — asked 2m ago.")
    }

    func testTheAccountDraftNeverTakesASecret() {
        var draft = NewAccountDraft()
        XCTAssertEqual(draft.problem, "Name the account.")
        draft.label = "claude personal"
        XCTAssertNotNil(draft.problem, "a space in the name")
        draft.label = "claude-personal"
        XCTAssertNil(draft.problem, "a subscription needs no key reference")
        draft.credential = "sk-ant-api03-abcdef"
        XCTAssertEqual(draft.problem, "That looks like the key itself — give where it lives.")
        draft.credentialKind = "env"
        draft.credential = "anthropic_key"
        XCTAssertEqual(draft.problem, "An environment variable's name, such as ANTHROPIC_API_KEY.")
        draft.credential = ""
        draft.billing = "metered"
        XCTAssertEqual(draft.problem, "An API-key account needs where its key lives.")
        draft.credential = "ANTHROPIC_API_KEY"
        XCTAssertNil(draft.problem)
        XCTAssertEqual(draft.body.credentialEnv, "ANTHROPIC_API_KEY")
        XCTAssertNil(draft.body.credentialRef)
        draft.credentialKind = "file"
        draft.credential = "~/.citadel/keys/anthropic"
        XCTAssertEqual(draft.body.credentialRef, "~/.citadel/keys/anthropic")
        XCTAssertNil(draft.body.credentialEnv)
        XCTAssertEqual(draft.body.billing?.word, "metered")
    }

    func testAddingAnAccountPostsTheReferenceAndJoinsThePool() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/accounts", request.httpMethod == "POST" else {
                return .init(status: 404)
            }
            return .init(
                json:
                    #"{"id":9,"label":"claude-new","harness":"claude","billing":"subscription","status":"active","config_dir":"~/.citadel/acct/claude-new","company_ids":[],"credential_ref":"~/.citadel/keys/new"}"#
            )
        }
        let (store, model) = try connectedStore()
        var draft = NewAccountDraft()
        draft.label = "claude-new"
        draft.credential = "~/.citadel/keys/new"
        var closed = false
        store.addAccount(draft) { closed = true }
        await eventually { closed }
        XCTAssertTrue(model.accountsPage.accounts.contains { $0.id == 9 })
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/accounts" })
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Citadel-Company"), "the pool is not a company's")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.sentBody)) as? [String: Any])
        XCTAssertEqual(sent["credential_ref"] as? String, "~/.citadel/keys/new")
        XCTAssertNil(sent["credential_env"])
    }

    func testLastFallbacksMergeTheStreamWithTheRunsList() throws {
        let events = try [
            CompanyFixture.fallbackEvent(seq: 2, run: 429, from: "gpt-5.5", to: "Opus 5.5", reason: "5 h at 100%")
        ]
        func run(_ id: Int64, reason: String?) -> RunInfo {
            RunInfo(
                id: id, agentID: 4, issueID: nil, state: "succeeded", harness: "claude", harnessVersion: nil,
                model: "sonnet-5", accountID: nil, runnerID: nil, fallbackReason: reason, terminalReason: nil,
                queuedAt: now)
        }
        let moves = FallbackMove.merged(
            events: events, runs: [run(429, reason: "rate limited"), run(424, reason: "account at limit")])
        XCTAssertEqual(moves.map(\.run), [429, 424], "one per run, the stream's first")
        XCTAssertEqual(moves[0].from, "gpt-5.5")
        XCTAssertNil(moves[1].from)
        XCTAssertEqual(moves[1].to, "sonnet-5")
        XCTAssertEqual(moves[1].why, "account at limit")
    }

    private func connectedStore() throws -> (CitadelStore, CompanyModel) {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        store.model = model
        return (store, model)
    }
}

extension URLRequest {
    /// The body, whether URLSession kept it as data or as a stream.
    fileprivate var sentBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
