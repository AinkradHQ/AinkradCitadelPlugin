import CitadelClient
import Foundation

/// The company's notification preferences (API minor 18): which event reaches which channel, and quiet hours.
struct NotificationPrefs: Equatable, Sendable {
    /// The events in the matrix's order: the wire word and the line it is read as.
    static let events: [(key: String, title: String)] = [
        ("approval_waiting", "Approval waiting on you"), ("run_waiting_permission", "Run waiting on a permission"),
        ("agent_question", "Agent asks you a question"), ("issue_stuck", "Issue stuck / stalled run"),
        ("budget_warning", "Budget past warn %"), ("account_limit", "Account at a window limit"),
        ("run_finished", "Run finished"), ("requirement_done", "Requirement done"),
    ]
    /// The channels in the matrix's order.
    static let channels = ["push", "signal", "email"]

    /// `event|channel` → on.
    var matrix: [String: Bool]
    /// Minutes from midnight (0 to 1439); the window wraps past midnight when `quietStart` is after `quietEnd`.
    var quietStart: Int
    var quietEnd: Int
    var quietOn: Bool
    /// `stalled` (stalled production work still pushes) or `nothing`.
    var breakthrough: String

    static func key(_ event: String, _ channel: String) -> String { "\(event)|\(channel)" }
    func isOn(_ event: String, _ channel: String) -> Bool { matrix[Self.key(event, channel)] ?? false }

    /// `22:00`, `07:30`.
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60) }

    /// A typed time (`22:00`, `7:30`, `22`) as minutes from midnight, or `nil`.
    static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let hour = Int(parts[0]), (0...23).contains(hour) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

extension NotificationPrefs {
    init(_ wire: Schemas.Notifications) {
        self.init(
            matrix: Dictionary(
                wire.matrix.map { (Self.key($0.event, $0.channel), $0.on) }, uniquingKeysWith: { _, last in last }),
            quietStart: Int(wire.quiet.start), quietEnd: Int(wire.quiet.end), quietOn: wire.quiet.on,
            breakthrough: wire.quiet.breakthrough)
    }
}
