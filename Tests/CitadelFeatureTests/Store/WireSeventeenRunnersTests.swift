import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, runners: a probe asks the runner to look at itself now, and its platform comes back with it.
@MainActor
final class WireSeventeenRunnersTests: XCTestCase {
    private static let before =
        #"{"id":3,"name":"hetzner-1","status":"online","asleep":false,"tags":["linux"],"harnesses":{},"logins":[],"harness_status":[]}"#

    private func runner() throws -> RunnerInfo {
        RunnerInfo(try JSONDecoder().decode(Schemas.Runner.self, from: Data(Self.before.utf8)))
    }

    /// Item 2: "Probe now" posts to the runner and the card takes the answer, its os and arch included.
    func testProbeNowRefreshesTheRunnerWithItsPlatform() async throws {
        let store = try Wire17.store()
        let model = try XCTUnwrap(store.model)
        model.runnersPage.runners = [try runner()]
        FakeServer.serve { _ in
            .init(
                json:
                    #"{"id":3,"name":"hetzner-1","status":"online","asleep":false,"tags":["linux"],"os":"macos","arch":"aarch64","harnesses":{},"logins":[],"harness_status":[]}"#
            )
        }
        store.probeRunner(try runner())
        await eventually { model.runnersPage.runners.first?.os == "macos" }
        XCTAssertEqual(model.runnersPage.runners.first?.arch, "aarch64")
        XCTAssertTrue(Wire17.didSend("POST", "/api/v1/runners/3/probe"))
    }

    /// Item 2: a refused probe (409, "runner too old") is a toast with the server's words.
    func testAProbeTheServerRefusesIsAToastWithItsMessage() async throws {
        let store = try Wire17.store()
        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "runner too old")) }
        store.probeRunner(try runner())
        await eventually { store.toasts.items.first != nil }
        XCTAssertEqual(store.toasts.items.first?.body, "runner too old")
    }
}
