import Foundation
import Testing

@testable import CitadelFeature

/// The Runners screen's client-side reading of what the server sends: log lines split into time / source / level /
/// message, the card's state word, the Add runner draft's tags, and the Limits gauge's step.
struct RunnerViewModelTests {
    @Test func aLogLineSplitsIntoTimeSourceLevelAndMessage() {
        let line = RunnerLogLine("10:01:00 probe claude: not logged in (exit 1)")
        #expect(line.time == "10:01:00")
        #expect(line.source == "probe")
        #expect(line.level == "err")
        #expect(line.message == "claude: not logged in (exit 1)")
        #expect(RunnerLogLine("14:10:05 probe agy 0.9.1 newer than tested (0.9.0)").level == "warn")
        #expect(RunnerLogLine("09:41:12 probe codex ok (0.88.0)").level == "info")
        #expect(RunnerLogLine("12:00:00 runner WARN disk at 88%").level == "warn")
        #expect(RunnerLogLine("no time here").time == "")
    }

    @Test func aDrainedOnlineRunnerReadsDraining() {
        var runner = RunnerInfo(id: 1, name: "h", status: "online", healthReason: nil, lastSeenAt: nil, tags: ["linux"])
        #expect(RunnerLook(runner: runner).state == "online")
        runner.drainedAt = Date(timeIntervalSince1970: 0)
        #expect(RunnerLook(runner: runner).state == "draining")
        runner.status = "offline"
        runner.asleep = true
        #expect(RunnerLook(runner: runner).state == "asleep")
        #expect(!RunnerLook(runner: runner).isMac)
        runner.tags = ["macos"]
        #expect(RunnerLook(runner: runner).isMac)
    }

    @Test func theDraftsTagsAreTheChipsThenTheTypedOnesOnce() {
        var draft = AddRunnerDraft()
        draft.extraTags = "gpu, docker  cuda"
        #expect(draft.allTags == ["linux", "docker", "gpu", "cuda"])
    }

    @Test func theGaugeStepsInWholeUnits() {
        func setting(_ unit: String, _ min: Int64, _ max: Int64) -> ScopedSetting {
            ScopedSetting(
                key: "k", description: "", value: min, defaultValue: min, min: min, max: max, unit: unit, scopes: [],
                source: nil)
        }
        #expect(LimitRowView.step(setting("seconds", 60, 7_200)) == 60)
        #expect(LimitRowView.step(setting("seconds", 3_600, 604_800)) == 3_600)
        #expect(LimitRowView.step(setting("bytes", 1_000_000_000, 500_000_000_000)) == 1_000_000_000)
        #expect(LimitRowView.step(setting("percent", 50, 99)) == 1)
    }
}
