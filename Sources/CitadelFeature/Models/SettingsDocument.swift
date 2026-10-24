import Foundation

/// What Citadel remembers in `host.documents`. Never the device key: that lives in `host.secrets` only
/// (`DeviceKeyStore`).
struct SettingsDocument: Codable, Equatable, Sendable {
    /// The server's origin, as `ServerAddress.origin` wrote it; `nil` before the first connect.
    var server: String?
    /// The company the window works in (`X-Citadel-Company`).
    var companyID: Int64?
    /// The company last chosen on each server (by origin), so a reconnect lands where you were. Optional: a
    /// document saved before it has none.
    var companyByServer: [String: Int64]?
    /// True once a connect has succeeded: from then on, losing the server is a slim bar over the shell, not the
    /// connect card (mockup 01 note 5).
    var hasConnected = false
    /// When the server last answered, for "Last seen 3 min ago".
    var lastSeen: Date?
    /// The last event seq read, per `server|company` (`EventCursor.key`) — the stream's resume point.
    var cursors: [String: Int64] = [:]
}
