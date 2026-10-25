import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B2: notification preferences and device pairing.
@MainActor
final class WireEighteenSettingsTests: XCTestCase {
    private let prefsJSON =
        #"{"matrix":[{"event":"approval_waiting","channel":"push","on":true},{"event":"run_finished","channel":"email","on":false}],"quiet":{"start":1320,"end":450,"on":true,"breakthrough":"stalled"}}"#

    func testPreferencesAreReadFromMinor18AndNotBefore() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: self.prefsJSON) }
        store.loadNotifications()
        await eventually { store.model?.notifications != nil }
        let prefs = try XCTUnwrap(store.model?.notifications)
        XCTAssertTrue(prefs.isOn("approval_waiting", "push"))
        XCTAssertFalse(prefs.isOn("run_finished", "email"))
        XCTAssertEqual(NotificationPrefs.clock(prefs.quietStart), "22:00")
        XCTAssertEqual(NotificationPrefs.clock(prefs.quietEnd), "07:30")

        let older = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: self.prefsJSON) }
        older.loadNotifications()
        older.sendTestNotification()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.isEmpty)
        XCTAssertNil(older.model?.notifications)
    }

    func testACellAndTheQuietWindowAreSentAsOnlyWhatChanged() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: self.prefsJSON) }
        store.loadNotifications()
        await eventually { store.model?.notifications != nil }
        store.setNotification(event: "run_finished", channel: "email", on: true)
        XCTAssertEqual(store.model?.notifications?.isOn("run_finished", "email"), true, "shown at once")
        let cell = try await Wire17.sent("PUT", "/api/v1/companies/1/notifications")
        let matrix = try XCTUnwrap(cell["matrix"] as? [[String: Any]])
        XCTAssertEqual(matrix.first?["event"] as? String, "run_finished")
        XCTAssertEqual(matrix.first?["on"] as? Bool, true)
        XCTAssertNil(cell["quiet_start"])

        FakeServer.serve { _ in .init(json: self.prefsJSON) }
        store.setQuiet(start: 1380, breakthrough: "nothing")
        let quiet = try await Wire17.sent("PUT", "/api/v1/companies/1/notifications")
        XCTAssertEqual(quiet["quiet_start"] as? Int, 1380)
        XCTAssertEqual(quiet["breakthrough"] as? String, "nothing")
        XCTAssertNil(quiet["quiet_end"])
        XCTAssertNil(quiet["matrix"])
    }

    func testARefusedCellIsPutBackAndATypedTimeIsChecked() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: self.prefsJSON) }
        store.loadNotifications()
        await eventually { store.model?.notifications != nil }
        FakeServer.serve { _ in .init(status: 400, json: Wire.refusal("invalid_argument", "unknown event")) }
        store.setNotification(event: "run_finished", channel: "email", on: true)
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.model?.notifications?.isOn("run_finished", "email"), false)
        XCTAssertEqual(NotificationPrefs.minutes("7:30"), 450)
        XCTAssertEqual(NotificationPrefs.minutes("22"), 1320)
        XCTAssertNil(NotificationPrefs.minutes("25:00"))
        XCTAssertNil(NotificationPrefs.minutes("noon"))
    }

    func testSendATestPostsAndToastsTheAuditSequence() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: #"{"seq":812}"#) }
        store.sendTestNotification()
        _ = try await Wire17.sent("POST", "/api/v1/companies/1/notifications/test")
    }

    func testPairingAsksForACodeAndTheNewDeviceAppearsInTheList() async throws {
        let store = try Wire17.store(minor: 18)
        let page = try XCTUnwrap(store.model?.limitsPage)
        let old = #"{"id":1,"name":"MacBook","created_at":"2026-10-20T09:00:00.000Z"}"#
        // The route runs under FakeServer's lock, so it keeps its own flag instead of asking `requests`.
        nonisolated(unsafe) var asked = false
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/devices/pairing":
                asked = true
                return .init(json: #"{"code":"k7q2mx","expires_at":"2099-10-25T12:05:00.000Z"}"#)
            case "/api/v1/devices":
                let new = #",{"id":2,"name":"iPad Pro","created_at":"2026-10-25T12:01:00.000Z"}"#
                return .init(json: "[\(old)\(asked ? new : "")]")
            default: return .init(json: "{}")
            }
        }
        page.devices = [DeviceInfo(id: 1, name: "MacBook", createdAt: Date())]
        store.startPairing()
        await eventually { page.pairing?.code != nil }
        XCTAssertEqual(page.pairing?.code?.tiles, ["K", "7", "Q", "-", "2", "M", "X"])
        store.loadDevices()
        await eventually { page.pairing?.paired?.name == "iPad Pro" }
    }

    func testAnOlderServerIsNeverAskedToPair() async throws {
        let store = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: "{}") }
        store.startPairing()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.model?.limitsPage.pairing)
        XCTAssertFalse(Wire17.didSend("POST", "/api/v1/devices/pairing"))
    }
}
