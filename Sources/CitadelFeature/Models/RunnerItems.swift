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
    /// The runner "+ Add runner" just registered, with its key: shown once, until the sheet closes.
    var registered: RegisteredRunnerInfo?
    /// Why the last "+ Add runner" was refused.
    var registerFailure: ActionFailure?
    /// The log tail a card's "Probe log" / "Show last log" opened.
    var log: (runner: Int64, lines: [String])?
    /// Each runner's limits at `runner:<id>` (decision #57: server → runner, never per company).
    var settings: [Int64: [String: ScopedSetting]] = [:]
    /// The server's values, what a runner's ↺ goes back to.
    var serverSettings: [String: ScopedSetting] = [:]
    /// The log drawer's level filter: `all`, `err`, `warn`, `info`.
    var logFilter = "all"
    /// The runner the Re-login drawer is open for, and whether "I've logged in" was pressed (waiting for its probe).
    var relogin: Int64?
    var reloginWaiting = false
    /// The Add runner drawer: open, its step (0 Machine, 1 Install, 2 Connect) and what was entered.
    var adding = false
    var addStep = 0
    var addDraft = AddRunnerDraft()
    /// Runners a "Wake now" is in flight for (the button spins).
    var waking: Set<Int64> = []
    /// The card a fleet chip just focused (it flashes).
    var flashed: Int64?

    /// The limits a runner card edits under its disk bar, in the mockup's order.
    static let limitKeys = ["runner.disk_cap_bytes", "workspace.idle_secs", "runner.disk_evict_percent"]

    /// `1 online · 1 unhealthy · 1 asleep · 1 offline · disk 87 GB used`.
    var counts: (online: Int, unhealthy: Int, asleep: Int, offline: Int, diskUsed: Int64) {
        (
            runners.filter { $0.state == "online" }.count, runners.filter { $0.state == "unhealthy" }.count,
            runners.filter { $0.state == "asleep" }.count, runners.filter { $0.state == "offline" }.count,
            disk.values.map(\.used).reduce(0, +)
        )
    }

    /// `5 of 8 slots free`: the slots of the runners that take work, less the live runs on them.
    func freeSlots(running: [Int64: Int]) -> (free: Int, total: Int)? {
        let up = runners.filter { $0.status != "offline" && $0.drainedAt == nil }
        let total = up.compactMap(\.slots).reduce(0, +)
        guard total > 0 else { return nil }
        let busy = up.map { min($0.slots ?? 0, running[$0.id] ?? 0) }.reduce(0, +)
        return (total - busy, total)
    }
}

/// What "Add runner" step 1 holds: a name, the machine kind (which sets the default tags) and the tags.
struct AddRunnerDraft: Equatable, Sendable {
    /// `linux`, `arm`, `mac`.
    var machine = "linux"
    var name = ""
    var tags: [String] = ["linux", "docker"]
    /// Tags beyond the chips, comma-separated.
    var extraTags = ""

    static let machines: [(id: String, title: String, mac: Bool, tags: [String])] = [
        ("linux", "Linux · x86_64", false, ["linux", "docker"]), ("arm", "Linux · arm64", false, ["linux", "arm64"]),
        ("mac", "macOS · arm64", true, ["macos", "xcode-27", "swift"]),
    ]
    static let tagChoices: [(tag: String, title: String)] = [
        ("linux", "Linux"), ("docker", "Docker"), ("rust", "Rust"), ("arm64", "arm64"), ("macos", "macOS"),
        ("xcode-27", "Xcode 27"), ("swift", "Swift"),
    ]

    /// The chips and the typed extras, deduplicated in order.
    var allTags: [String] {
        let extra = extraTags.split { $0 == "," || $0 == " " }.map(String.init).filter { !$0.isEmpty }
        var seen = Set<String>()
        return (tags + extra).filter { seen.insert($0).inserted }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
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
    /// An offline Mac that most likely sleeps: "☾ asleep", the wake actions.
    var asleep = false
    /// Drained by the admin: it takes no new run; its runs finish.
    var drainedAt: Date? = nil
    /// Harness → version, from its last hello.
    var harnesses: [String: String] = [:]
    var logins: [RunnerLoginInfo] = []
    /// Each harness judged against Citadel's tested versions (API minor 10).
    var harnessStatus: [RunnerHarnessInfo] = []
    /// Runs it works at once, as it reported.
    var slots: Int? = nil
    /// Seconds it had been up at `reportedAt`.
    var uptimeSecs: Int64? = nil
    var reportedAt: Date? = nil
    /// The admin's Power Nap preference ("Keep awake while jobs queue"), and the one the runner says it holds.
    var powerNap: Bool? = nil
    var powerNapApplied: Bool? = nil

    /// The pill's word: `asleep` for a sleeping Mac, else the server's status.
    var state: String { status == "offline" && asleep ? "asleep" : status }

    /// "up 6d", counted on from when it reported.
    func uptime(now: Date) -> String? {
        guard let uptimeSecs, status != "offline" else { return nil }
        let since = reportedAt.map { now.timeIntervalSince($0) } ?? 0
        return "up \(Fmt.age(TimeInterval(uptimeSecs) + max(0, since)))"
    }

    /// One row per harness, in name order: its version and whether it is logged in on the runner.
    var harnessRows: [(name: String, version: String, login: String?, status: RunnerHarnessInfo?)] {
        let order = ["claude", "codex", "opencode", "agy"]
        let names = Set(harnesses.keys).union(harnessStatus.filter { $0.status != "missing" }.map(\.name)).sorted {
            (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1)
        }
        return names.map { name in
            let states = logins.filter { $0.harness == name && !$0.dir.hasPrefix("accounts/") }.map(\.state)
            let status = harnessStatus.first { $0.name == name }
            return (name, harnesses[name] ?? status?.version ?? "", states.first, status)
        }
    }

    /// The logins to redo: every one the runner reports logged out.
    var loggedOut: [RunnerLoginInfo] { logins.filter { $0.state == "logged_out" } }

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

    /// Drained: "Drained 2h ago." and what that means.
    func drainLine(now: Date) -> (title: String, detail: String)? {
        drainedAt.map {
            ("Drained \(Fmt.age(now.timeIntervalSince($0))) ago.", "It takes no new run; its runs finish.")
        }
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
        case "offline" where asleep:
            let since = lastSeenAt.map { " since \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return ("Asleep\(since).", "Its queued work waits; the launchd agent reconnects on wake.")
        case "offline":
            let silent = lastSeenAt.map { "No heartbeat for \(Fmt.span(now.timeIntervalSince($0)))." }
            return (silent ?? "No heartbeat yet.", "No work goes to it until it connects again.")
        default: return nil
        }
    }
}

/// Where a harness or account logs in on a runner's host (`dir` under its config root), and whether it is.
struct RunnerLoginInfo: Equatable, Sendable {
    /// `claude`, `accounts/claude-a`, or `credentials/<file>` for an account's token file.
    var dir: String
    var harness: String?
    /// `logged_in`, `logged_out` or `unknown` (the login lives in the keychain).
    var state: String
    var accountIDs: [Int64] = []

    /// What to run on the runner's host to log it in again, per `citadel-runner`'s usage; Citadel never handles the
    /// secret itself.
    var command: String {
        let root = "$HOME/.citadel-runner"
        if dir.hasPrefix("credentials/") { return "install -m 600 /dev/stdin \(root)/\(dir)  # paste the token" }
        let path = "\(root)/\(dir)"
        switch harness ?? dir {
        case "claude": return "CLAUDE_CONFIG_DIR=\(path) claude /login"
        case "codex": return "CODEX_HOME=\(path) codex login"
        case "opencode": return "XDG_DATA_HOME=\(path)/data opencode auth login"
        case "agy": return "HOME=\(path) agy"
        default: return "# log \(harness ?? "the harness") in with its config dir \(path)"
        }
    }
}

/// A runner registered from "+ Add runner": its key, shown this once.
struct RegisteredRunnerInfo: Equatable, Sendable {
    var runner: RunnerInfo
    var key: String

    /// The one-line start command for a runner host: the key rides in the environment, never as a flag
    /// (`citadel-runner` refuses a key on its command line).
    func command(server: URL) -> String {
        var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = parts.scheme == "http" ? "ws" : "wss"
        parts.path = "/runner/v1/connect"
        let tags = runner.tags.isEmpty ? "" : " \\\n  --tags \(runner.tags.joined(separator: ","))"
        return "CITADEL_RUNNER_KEY=\(key) \\\n  citadel-runner \(parts.string ?? "")\(tags)"
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

/// A harness on a runner against the versions Citadel was tested with: `supported`, `untested_newer` (runs unless
/// the settings refuse it), `too_old`, `known_bad`, `missing`, `unreadable`, `unknown_harness`, or a newer word.
struct RunnerHarnessInfo: Equatable, Sendable {
    var name: String
    var version: String?
    var status: String
    var testedUpTo: String?
    /// Whether runs are dispatched to it.
    var offered: Bool
    var reason: String?

    /// "✓ tested", "newer than tested (2.1.200)", or why it is refused.
    var word: String {
        switch status {
        case "supported": "✓ tested"
        case "untested_newer": "newer than tested\(testedUpTo.map { " (\($0))" } ?? "")"
        default: reason ?? status.replacingOccurrences(of: "_", with: " ")
        }
    }
}

extension RunnerInfo {
    init(_ runner: Schemas.Runner) {
        self.init(
            id: runner.id, name: runner.name, status: runner.status.word, healthReason: runner.healthReason,
            lastSeenAt: runner.lastSeenAt, tags: runner.tags, wakeMode: runner.wakeMode,
            wakeRequestedAt: runner.wakeRequestedAt, asleep: runner.asleep, drainedAt: runner.drainedAt,
            harnesses: runner.harnesses.additionalProperties,
            logins: runner.logins.map {
                RunnerLoginInfo(dir: $0.dir, harness: $0.harness, state: $0.state, accountIDs: $0.accountIds)
            },
            harnessStatus: runner.harnessStatus.map {
                RunnerHarnessInfo(
                    name: $0.name, version: $0.version, status: $0.status, testedUpTo: $0.testedUpTo,
                    offered: $0.offered, reason: $0.reason)
            },
            slots: runner.slots.map(Int.init), uptimeSecs: runner.uptimeSecs, reportedAt: runner.reportedAt,
            powerNap: runner.powerNap, powerNapApplied: runner.powerNapApplied)
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
