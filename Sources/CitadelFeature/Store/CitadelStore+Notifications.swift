import AinkradAppKit
import CitadelClient
import Foundation

/// Settings › Notifications (API minor 18): the event × channel matrix, quiet hours, and "Send a test". Below 18
/// nothing is read or written and the page stays the disabled drawing.
extension CitadelStore {
    var notificationsOn: Bool { serverSupports(minor: Self.trancheBMinor) }

    func loadNotifications() {
        guard notificationsOn, let server, let model else { return }
        Task { if let prefs = await server.notifications(company: model.companyID) { model.notifications = prefs } }
    }

    /// One cell of the matrix: shown at once, put back with the server's words when it refuses.
    func setNotification(event: String, channel: String, on: Bool) {
        guard var prefs = model?.notifications else { return }
        prefs.matrix[NotificationPrefs.key(event, channel)] = on
        send(Schemas.NotificationsUpdate(matrix: [.init(channel: channel, event: event, on: on)]), showing: prefs)
    }

    /// Quiet hours: any of the window, its switch and what breaks through; only what changed is sent.
    func setQuiet(start: Int? = nil, end: Int? = nil, on: Bool? = nil, breakthrough: String? = nil) {
        guard var prefs = model?.notifications else { return }
        if let start { prefs.quietStart = start }
        if let end { prefs.quietEnd = end }
        if let on { prefs.quietOn = on }
        if let breakthrough { prefs.breakthrough = breakthrough }
        send(
            Schemas.NotificationsUpdate(
                breakthrough: breakthrough, quietEnd: end.map(Int64.init), quietOn: on,
                quietStart: start.map(Int64.init)), showing: prefs)
    }

    private func send(_ update: Schemas.NotificationsUpdate, showing next: NotificationPrefs) {
        guard notificationsOn, let server, let model, let before = model.notifications else { return }
        model.notifications = next
        Task {
            switch await server.setNotifications(company: model.companyID, update) {
            case .success(let stored):
                actionFailure = nil
                model.notifications = stored
            case .failure(let answer):
                model.notifications = before
                actionFailure = ActionFailure(
                    title: "Couldn't save the notification settings", answer: answer,
                    outcome: "They are as they were.")
            }
        }
    }

    /// "Send a test": the server emits a `notifications.test` event; the toast is how a push reads.
    func sendTestNotification() {
        guard notificationsOn, let server, let model else { return }
        Task {
            switch await server.testNotification(company: model.companyID) {
            case .success(let seq):
                toast(
                    AinkradRichToast(
                        title: "Test notification sent", body: "This is how a push looks · audit #\(seq)",
                        status: .warning))
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't send a test", answer: answer, outcome: "Nothing was sent.")
            }
        }
    }
}
