import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screen 10's runner admin (API minor 6): what a runner reports of itself, register (its key once), drain and
/// undrain, Power Nap, its log tail and remove. Every time is fixed or relative to the fixture's own `now`.
@MainActor
final class RunnerAdminTests: XCTestCase {
    private static let reported =
        #"{"id":3,"name":"ahmed-mbp","status":"offline","tags":["macos"],"asleep":true,"harnesses":{"claude":"2.1.296","codex":"0.88.0"},"harness_status":[{"name":"claude","version":"2.1.296","status":"untested_newer","tested_up_to":"2.1.200","offered":true},{"name":"codex","version":"0.88.0","status":"too_old","offered":false,"reason":"older than 0.90"}],"logins":[{"dir":"claude","harness":"claude","state":"logged_out","account_ids":[]},{"dir":"codex","harness":"codex","state":"logged_in","account_ids":[]},{"dir":"accounts/claude-a","harness":"claude","state":"logged_in","account_ids":[2]}],"slots":2,"uptime_secs":3600,"power_nap":true,"power_nap_applied":false}"#

    func testARunnerCarriesItsHarnessesLoginsSlotsAndSleep() throws {
        let runner = RunnerInfo(try JSONDecoder().decode(Schemas.Runner.self, from: Data(Self.reported.utf8)))
        XCTAssertEqual(runner.state, "asleep")
        XCTAssertEqual(runner.slots, 2)
        XCTAssertEqual(runner.powerNap, true)
        XCTAssertEqual(runner.powerNapApplied, false)
        XCTAssertEqual(runner.harnessRows.map(\.name), ["claude", "codex"])
        XCTAssertEqual(
            runner.harnessRows.map(\.login), ["logged_out", "logged_in"], "an account's login is not the harness's")
        XCTAssertEqual(
            runner.harnessRows.map { $0.status?.word }, ["newer than tested (2.1.200)", "older than 0.90"],
            "API minor 10: each harness against the tested versions")
        XCTAssertEqual(runner.harnessRows.map { $0.status?.offered }, [true, false])
        XCTAssertEqual(runner.loggedOut.map(\.dir), ["claude"])
        XCTAssertEqual(runner.loggedOut.first?.command, "CLAUDE_CONFIG_DIR=$HOME/.citadel-runner/claude claude /login")
        XCTAssertNil(runner.uptime(now: Date()), "an offline runner shows no uptime")
    }

    func testReloginCommandsFollowTheRunnersUsage() {
        func command(_ dir: String, _ harness: String?) -> String {
            RunnerLoginInfo(dir: dir, harness: harness, state: "logged_out").command
        }
        XCTAssertEqual(command("codex", "codex"), "CODEX_HOME=$HOME/.citadel-runner/codex codex login")
        XCTAssertEqual(
            command("opencode", "opencode"), "XDG_DATA_HOME=$HOME/.citadel-runner/opencode/data opencode auth login")
        XCTAssertEqual(
            command("accounts/claude-a", "claude"),
            "CLAUDE_CONFIG_DIR=$HOME/.citadel-runner/accounts/claude-a claude /login")
        XCTAssertTrue(command("credentials/anthropic", nil).contains("$HOME/.citadel-runner/credentials/anthropic"))
    }

    func testTheCrumbCountsAsleepAndFreeSlots() {
        let model = CompanyFixture.model()
        CompanyFixture.runnersPage(model)
        let page = model.runnersPage
        XCTAssertEqual(page.counts.asleep, 1)
        XCTAssertEqual(page.counts.offline, 1)
        // hetzner-1 (4) and hetzner-2 (2) take work; the asleep Mac does not.
        XCTAssertEqual(page.freeSlots(running: [1: 3])?.total, 6)
        XCTAssertEqual(page.freeSlots(running: [1: 3])?.free, 3)
        XCTAssertEqual(page.freeSlots(running: [1: 9])?.free, 2, "more runs than slots fill it, never below zero")
        page.runners[0].drainedAt = Date()
        XCTAssertEqual(page.freeSlots(running: [:])?.total, 2, "a drained runner offers no slot")
    }

    func testRegisterPostsNameAndTagsAndKeepsTheKeyForTheSheet() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/runners", request.httpMethod == "POST" else {
                return .init(json: "[]")
            }
            return .init(
                json:
                    #"{"key":"rk_live_once","runner":{"id":9,"name":"hetzner-3","status":"offline","tags":["linux","docker"],"asleep":false,"harnesses":{},"harness_status":[],"logins":[]}}"#
            )
        }
        let (store, model) = try connectedStore()
        store.registerRunner(name: "hetzner-3", tags: ["linux", "docker"])
        await eventually { model.runnersPage.registered != nil }
        let sent = try body(of: "/api/v1/runners", method: "POST")
        XCTAssertEqual(sent["name"] as? String, "hetzner-3")
        XCTAssertEqual(sent["tags"] as? [String], ["linux", "docker"])
        let registered = try XCTUnwrap(model.runnersPage.registered)
        XCTAssertEqual(
            registered.command(server: URL(string: "https://citadel.example.com")!),
            "CITADEL_RUNNER_KEY=rk_live_once \\\n  citadel-runner wss://citadel.example.com/runner/v1/connect \\\n  --tags linux,docker"
        )
    }

    func testDrainAndUndrainUpdateTheCard() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/runners/1/drain" else { return .init(status: 404) }
            let drained = request.httpMethod == "POST" ? #","drained_at":"2026-10-23T10:00:00.000Z""# : ""
            return .init(
                json:
                    #"{"id":1,"name":"hetzner-1","status":"online","tags":[],"asleep":false,"harnesses":{},"harness_status":[],"logins":[]\#(drained)}"#
            )
        }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        let runner = model.runnersPage.runners[0]
        store.setDrained(runner, true)
        await eventually { model.runnersPage.runners[0].drainedAt != nil }
        store.setDrained(model.runnersPage.runners[0], false)
        await eventually { model.runnersPage.runners[0].drainedAt == nil }
        XCTAssertEqual(
            FakeServer.requests.filter { $0.url?.path == "/api/v1/runners/1/drain" }.map(\.httpMethod),
            ["POST", "DELETE"])
    }

    func testPowerNapSendsThePreference() async throws {
        FakeServer.serve { _ in
            .init(
                json:
                    #"{"id":3,"name":"ahmed-mbp","status":"offline","tags":[],"asleep":true,"harnesses":{},"harness_status":[],"logins":[],"power_nap":true}"#
            )
        }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        store.setPowerNap(model.runnersPage.runners[2], true)
        await eventually { model.runnersPage.runners[2].powerNap == true }
        XCTAssertEqual(try body(of: "/api/v1/runners/3/power-nap", method: "PUT")["enabled"] as? Bool, true)
    }

    func testTheLogOpensAndARefusalCarriesItsErrorID() async throws {
        FakeServer.serve { request in
            request.url?.path == "/api/v1/runners/2/logs"
                ? .init(json: #"{"runner_id":2,"lines":["probe claude: logged out","probe codex: ok"]}"#)
                : .init(status: 409, json: Wire.refusal("conflict", "The runner is offline."))
        }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        let page = model.runnersPage
        store.showRunnerLog(page.runners[1])
        await eventually { page.log != nil }
        XCTAssertEqual(page.log?.runner, 2)
        XCTAssertEqual(page.log?.lines.count, 2)
        store.showRunnerLog(page.runners[3])
        await eventually { page.failures[4] != nil }
        XCTAssertEqual(page.failures[4]?.answer.errorID, "err_01JTEST")
        XCTAssertEqual(page.failures[4]?.answer.line, "409 conflict: The runner is offline. · err_01JTEST")
    }

    func testRemoveDropsTheCard() async throws {
        FakeServer.serve { request in
            request.httpMethod == "DELETE" ? .init(json: #"{"id":4}"#) : .init(json: "[]")
        }
        let (store, model) = try connectedStore()
        CompanyFixture.runnersPage(model)
        store.removeRunner(model.runnersPage.runners[3])
        await eventually { !model.runnersPage.runners.contains { $0.id == 4 } }
        XCTAssertTrue(FakeServer.requests.contains { $0.url?.path == "/api/v1/runners/4" && $0.httpMethod == "DELETE" })
        XCTAssertNil(model.runnersPage.failures[4])
    }

    private func body(of path: String, method: String) throws -> [String: Any] {
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == path && $0.httpMethod == method })
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
