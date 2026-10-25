import CitadelClient
import Foundation

/// Notification preferences and the test push (API minor 18).
extension CitadelServer {
    func notifications(company: Int64) async -> NotificationPrefs? {
        await read("getNotifications") {
            guard case .ok(let ok) = try await client.getNotifications(path: .init(id: company)) else { return nil }
            return NotificationPrefs(try ok.body.json)
        }
    }

    /// Changes only what `update` carries; the preferences as stored.
    func setNotifications(company: Int64, _ update: Schemas.NotificationsUpdate) async -> Result<
        NotificationPrefs, ServerAnswer
    > {
        await attempt({ try await client.setNotifications(path: .init(id: company), body: .json(update)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return NotificationPrefs(try ok.body.json)
        }
    }

    /// Emits a `notifications.test` event; its audit sequence.
    func testNotification(company: Int64) async -> Result<Int64, ServerAnswer> {
        await attempt({ try await client.testNotification(path: .init(id: company)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.seq
        }
    }
}
