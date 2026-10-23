import AinkradAppKit
import CitadelClient
import Foundation
import Observation

/// Screen 10 Runners: each runner's state, harnesses and disk.
@MainActor
@Observable
final class RunnersPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
    var runners: [RunnerInfo] = []
    /// Each runner's disk as it last reported it.
    var disk: [Int64: RunnerDiskInfo] = [:]
    /// Why a runner's last action was refused (mockup 11 G, on its card).
    var failures: [Int64: ActionFailure] = [:]
    /// Each runner's limits at `runner:<id>` (decision #57: server → runner, never per company).
    var settings: [Int64: [String: ScopedSetting]] = [:]
    /// The server's values, what a runner's ↺ goes back to.
    var serverSettings: [String: ScopedSetting] = [:]

    /// The limits a runner card edits under its disk bar, in the mockup's order.
    static let limitKeys = ["runner.disk_cap_bytes", "workspace.idle_secs", "runner.disk_evict_percent"]

    /// `1 online · 1 unhealthy · 1 offline · disk 87 GB used`.
    var counts: (online: Int, unhealthy: Int, offline: Int, diskUsed: Int64) {
        (
            runners.filter { $0.status == "online" }.count, runners.filter { $0.status == "unhealthy" }.count,
            runners.filter { $0.status == "offline" }.count, disk.values.map(\.used).reduce(0, +)
        )
    }
}

/// One runner as `GET /runners` reports it.
struct RunnerInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    /// `online`, `unhealthy` (up, a probe fails), `offline` (no heartbeat).
    var status: String
    /// Why it is unhealthy, in the engine's words.
    var healthReason: String?
    var lastSeenAt: Date?
    var tags: [String]
    /// A wake asked for and not yet answered: `now` ("Wake now", pushed to the Mac) or `when_back` (its work waits).
    var wakeMode: String?
    var wakeRequestedAt: Date?

    /// A wake asked for and not yet answered: "Wake requested 2m ago." and what happens next.
    func wakeLine(now: Date) -> (title: String, detail: String)? {
        guard let wakeMode else { return nil }
        let age = wakeRequestedAt.map { " \(Fmt.age(now.timeIntervalSince($0))) ago" } ?? ""
        return wakeMode == "when_back"
            ? (
                "Runs when you're back\(age.isEmpty ? "" : " — asked\(age)").",
                "Nothing was pushed; its work waits until it connects."
            )
            : ("Wake requested\(age).", "Pushed to your Mac; its queued work starts when it connects.")
    }

    /// The reason block: unhealthy says why; offline says how long it has been silent.
    func reason(now: Date) -> (title: String, detail: String)? {
        switch status {
        case "unhealthy":
            guard let reason = healthReason, !reason.isEmpty else {
                return ("Unhealthy.", "A probe fails, so the engine stopped sending it work.")
            }
            // The engine's first sentence is the headline, bold.
            guard let end = reason.range(of: ". ") else { return (reason, "") }
            return (
                String(reason[..<end.upperBound]).trimmingCharacters(in: .whitespaces),
                String(reason[end.upperBound...])
            )
        case "offline":
            let silent = lastSeenAt.map { "No heartbeat for \(Fmt.span(now.timeIntervalSince($0)))." }
            return (silent ?? "No heartbeat yet.", "No work goes to it until it connects again.")
        default: return nil
        }
    }
}

/// A runner's work root (`GET /runners/{id}/disk`), split as the bar draws it.
struct RunnerDiskInfo: Equatable, Sendable {
    var capBytes: Int64
    var used: Int64
    /// Shared build caches and repo mirrors: one per repo, shared by every worktree.
    var shared: Int64
    var active: Int64
    var idle: Int64
    var evictPercent: Int
    var full: Bool
    var measuredAt: Date
    var worktrees: [WorktreeDiskInfo]

    var fraction: Double { capBytes > 0 ? Double(used) / Double(capBytes) : 0 }
    /// Within 5 points of the evict threshold (or full): the bar's total turns amber and the card names what goes
    /// next.
    var isNearCap: Bool { full || fraction * 100 >= Double(evictPercent - 5) }
    var activeCount: Int { worktrees.filter(\.active).count }
    var idleWorktrees: [WorktreeDiskInfo] { worktrees.filter { !$0.active }.sorted { $0.idleSecs > $1.idleSecs } }
}

/// One issue's workspace on a runner: one worktree per repo the issue touches (decision #51), aged and removed
/// together.
struct WorktreeDiskInfo: Equatable, Sendable {
    var issueID: Int64
    var bytes: Int64
    var active: Bool
    var idleSecs: Int64
    /// Seconds after `measuredAt` until the runner removes it.
    var removedInSecs: Int64?

    /// "3h 12m" left at `now`, counted from when the runner measured it; nil while active.
    func removalCountdown(measuredAt: Date, now: Date) -> String? {
        guard !active, let removedInSecs else { return nil }
        let left = measuredAt.addingTimeInterval(TimeInterval(removedInSecs)).timeIntervalSince(now)
        return left <= 0 ? "removing now" : "removed in \(Fmt.hoursMinutes(left))"
    }

    /// "cit-61 · citadel + plugin · 2 worktrees · idle".
    func line(key: String?, repos: [String]?) -> String {
        var parts = [(key ?? "issue \(issueID)").lowercased()]
        if let repos, !repos.isEmpty { parts.append(repos.joined(separator: " + ")) }
        if let count = repos?.count, count > 1 { parts.append("\(count) worktrees") }
        parts.append(active ? "active" : "idle")
        return parts.joined(separator: " · ")
    }
}

extension RunnerInfo {
    init(_ runner: Schemas.Runner) {
        self.init(
            id: runner.id, name: runner.name, status: runner.status.word, healthReason: runner.healthReason,
            lastSeenAt: runner.lastSeenAt, tags: runner.tags, wakeMode: runner.wakeMode,
            wakeRequestedAt: runner.wakeRequestedAt)
    }
}

extension RunnerDiskInfo {
    init(_ disk: Schemas.RunnerDisk) {
        self.init(
            capBytes: disk.capBytes, used: disk.usedBytes, shared: disk.cachesBytes + disk.mirrorsBytes,
            active: disk.activeBytes, idle: disk.idleBytes, evictPercent: Int(disk.evictPercent), full: disk.full,
            measuredAt: disk.measuredAt,
            worktrees: disk.worktrees.map {
                WorktreeDiskInfo(
                    issueID: $0.issueId, bytes: $0.bytes, active: $0.active, idleSecs: $0.idleSecs,
                    removedInSecs: $0.removedInSecs)
            })
    }
}

extension Fmt {
    /// `3h 12m`, `21h 40m`, `45m`.
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// `3 days`, `5 hours`, `12 minutes`.
    static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if s >= 86_400 { return plural(s / 86_400, "day") }
        if s >= 3600 { return plural(s / 3600, "hour") }
        return plural(max(1, s / 60), "minute")
    }
}
