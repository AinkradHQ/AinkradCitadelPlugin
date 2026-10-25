import AppKit
import Foundation

@testable import CitadelFeature

/// The prototype's Runs, Run and Artifacts data (`data.js` RUNS / RUN_HISTORY, `artifacts.js` ARTIFACTS) on the
/// mockups' company: five live runs (running, waiting, stalling) and eight ended ones.
@MainActor
extension CompanyFixture {
    static func runsParity(_ model: CompanyModel) {
        runPage(model)
        model.approvals.removeAll { $0.id == 9 }
        for (id, key, title, project, requirement) in [
            (Int64(49), "CIT-49", "Retry budget for runner_lost", Int64(1), Int64?(8)),
            (57, "CIT-57", "QA: rate-limit device key auth", 1, 12), (58, "CIT-58", "Device registration", 1, 12),
            (54, "CIT-54", "Notification events", 1, 12), (61, "CIT-61", "Runner lease heartbeat", 1, 12),
            (64, "CIT-64", "OpenAPI spec diff in make test", 1, 8),
            (9, "AMC-9", "Signed build on the Mac runner", 2, nil),
        ] {
            model.issues[id] = IssueInfo(id: id, key: key, title: title, projectID: project, requirementID: requirement)
        }
        model.requirements.append(
            RequirementInfo(
                id: 8, key: "R-8", title: "Never miss events on reconnect", state: "in_progress", ownerAgentID: 3,
                points: 18, donePoints: 15, percentDone: 83, eta: nil))
        model.accounts[3] = AccountInfo(id: 3, label: "claude-personal", billing: "subscription", status: "active")
        model.runners[4] = "oracle-arm"

        func live(
            _ id: Int64, agent: Int64, issue: Int64, minutes: Double, tokens: Int64, cost: Int64, account: Int64,
            runner: Int64, silent: Double = 5, harness: String = "claude", modelName: String = "Sonnet 5"
        ) -> RunInfo {
            var run = run(
                id, agent: agent, issue: issue, minutes: minutes, tokens: tokens, silentFor: silent, harness: harness,
                model: modelName)
            run.inputTokens = tokens * 47 / 100
            run.cacheTokens = tokens * 27 / 100
            run.outputTokens = tokens - run.inputTokens - run.cacheTokens
            run.costMicros = cost
            run.accountID = account
            run.runnerID = runner
            return run
        }
        var kestrel = live(
            418, agent: 4, issue: 42, minutes: 4.2, tokens: 82_400, cost: 940_000, account: 2, runner: 1,
            harness: "codex", modelName: "gpt-5.5")
        kestrel.diffRepos = model.runs[418]?.diffRepos ?? []
        let liveRuns = [
            kestrel,
            live(433, agent: 11, issue: 12, minutes: 1.1, tokens: 18_100, cost: 310_000, account: 3, runner: 3),
            live(427, agent: 15, issue: 8, minutes: 12.4, tokens: 42_000, cost: 4_200_000, account: 3, runner: 4),
            live(
                430, agent: 8, issue: 64, minutes: 24.3, tokens: 66_000, cost: 710_000, account: 3, runner: 1,
                silent: 560),
            live(431, agent: 9, issue: 57, minutes: 0.7, tokens: 9_200, cost: 120_000, account: 3, runner: 2),
        ]
        model.runs = Dictionary(uniqueKeysWithValues: liveRuns.map { ($0.id, $0) })
        model.limits["run.token_cap.agent.15"] = LimitSetting(value: 50_000, source: "agent:15")
        model.limits["run.token_cap.agent.9"] = LimitSetting(value: 120_000, source: "agent:9")
        model.toolNow = [
            418: "Edit Sources/CitadelClient/EventStream.swift", 433: "Edit Sources/Citadel/CitadelApp.swift",
            431: "Read docs/rate-limits.md",
        ]
        model.approvals.removeAll { $0.id == 3 }
        model.approvals += [
            ApprovalInfo(
                id: 3, kind: "permission_escalation", agentID: 15, issueID: 8, requestedBy: 15, expiresAt: nil,
                fields: [
                    "run": "427", "tool": "WebFetch", "input.url": "ainkrad.io/press",
                    "prompt": "asks to fetch ainkrad.io/press", "ask": "$6",
                ]),
            ApprovalInfo(
                id: 11, kind: "permission_escalation", agentID: 11, issueID: 12, requestedBy: 11, expiresAt: nil,
                fields: [
                    "run": "433", "tool": "Bash", "input.command": "xcodebuild -allowProvisioningUpdates",
                    "prompt": "asks to run xcodebuild -allowProvisioningUpdates",
                ]),
        ]

        let realNow = Date()
        func ended(
            _ id: Int64, agent: Int64, issue: Int64, state: String, minutesAgo: Double, minutes: Double, tokens: Int64,
            cost: Int64?, account: Int64 = 3, runner: Int64 = 1, reason: String? = nil, endOverride: Date? = nil
        ) -> RunInfo {
            var run = live(
                id, agent: agent, issue: issue, minutes: minutes, tokens: tokens, cost: cost ?? 0, account: account,
                runner: runner)
            let end = endOverride ?? realNow.addingTimeInterval(-minutesAgo * 60)
            run.contextTokens = nil
            run.costMicros = cost
            run.state = state
            run.terminalReason = reason
            run.queuedAt = end.addingTimeInterval(-minutes * 60 - 9)
            run.wokenAt = run.queuedAt
            run.claimedAt = run.queuedAt.addingTimeInterval(0.4)
            run.startedAt = end.addingTimeInterval(-minutes * 60)
            run.harnessStartedAt = run.startedAt?.addingTimeInterval(5.9)
            run.firstTokenAt = run.harnessStartedAt?.addingTimeInterval(2.2)
            run.endedAt = end
            run.lastProgressAt = end
            return run
        }
        let end422 =
            Calendar.current.date(bySettingHour: 9, minute: 58, second: 0, of: realNow)
            ?? realNow.addingTimeInterval(-18 * 60)
        var lost = ended(
            422, agent: 8, issue: 49, state: "runner_lost", minutesAgo: 18, minutes: 31, tokens: 96_000,
            cost: 1_040_000, runner: 2, reason: "lease expired after 30 s", endOverride: end422)
        lost.diffRepos = [RepoDiffInfo(repo: "citadel", files: 1, insertions: 8, deletions: 0)]
        model.companyRuns = [
            ended(
                426, agent: 8, issue: 61, state: "succeeded", minutesAgo: 12, minutes: 18, tokens: 141_000,
                cost: 1_620_000),
            ended(
                425, agent: 9, issue: 61, state: "succeeded", minutesAgo: 6, minutes: 9, tokens: 64_000,
                cost: 580_000),
            ended(
                424, agent: 5, issue: 58, state: "succeeded", minutesAgo: 42, minutes: 22, tokens: 118_000,
                cost: nil),
            lost,
            ended(
                421, agent: 4, issue: 54, state: "succeeded", minutesAgo: 65, minutes: 100, tokens: 96_000,
                cost: 1_310_000, account: 2),
            ended(
                419, agent: 15, issue: 8, state: "failed", minutesAgo: 125, minutes: 26, tokens: 50_000,
                cost: 3_100_000,
                reason: "token cap: stopped at the 50k cap"),
            ended(
                416, agent: 16, issue: 8, state: "succeeded", minutesAgo: 185, minutes: 12, tokens: 38_000,
                cost: nil, account: 2),
            ended(
                414, agent: 11, issue: 9, state: "cancelled", minutesAgo: 24 * 60, minutes: 4, tokens: 7_000,
                cost: 80_000),
        ]
        model.runs[422] = lost
        model.issueRepos[49] = ["citadel", "ainkrad-citadel-plugin"]
        model.issueCosts[42] = IssueCost(issueID: 42, tokens: 164_000, costMicros: 2_310_000, runs: 2, unpricedRuns: 0)
        model.issueCosts[49] = IssueCost(issueID: 49, tokens: 164_000, costMicros: 1_900_000, runs: 2, unpricedRuns: 0)
        model.limits["issue.token_cap"] = LimitSetting(value: 600_000, source: "company:1")
        model.limits["transcript.retention_secs"] = LimitSetting(value: 30 * 86_400, source: nil)
        model.projectsPage.policies[1] = PolicyInfo(mode: "accept_edits", allow: [], sandboxed: true)
        model.transcripts[418] = live418Transcript()
        model.transcripts[422] = lostTranscript(end: lost.endedAt ?? realNow)
    }

    /// #418's full transcript (`RUN_TRANSCRIPTS["418"]` in `run.js`).
    static func live418Transcript() -> [TranscriptChunkInfo] {
        func chunk(_ seq: Int64, _ ago: Double, _ kind: String, _ fields: [String: String]) -> TranscriptChunkInfo {
            TranscriptChunkInfo(seq: seq, at: now.addingTimeInterval(-ago), kind: kind, fields: fields)
        }
        return [
            chunk(
                1, 240, "assistant_text",
                [
                    "text":
                        "The stream drops events when a client reconnects while the broadcaster's ring buffer is rotating. Reading the subscriber loop first."
                ]),
            chunk(
                2, 230, "tool_use",
                [
                    "id": "t1", "name": "Read", "input.file_path": "citadel/crates/citadel-server/src/stream.rs",
                    "summary": "412 lines",
                ]),
            chunk(3, 228, "tool_result", ["id": "t1", "status": "ok", "summary": "412 lines"]),
            chunk(
                4, 210, "tool_use",
                [
                    "id": "t2", "name": "Edit", "input.file_path": "citadel/crates/citadel-server/src/stream.rs",
                    "added": "38", "removed": "6",
                    "input.old_string": "let since = cursor.unwrap_or(self.head);\nself.ring.slice_from(since)",
                    "input.new_string":
                        "// Replay from the database before reading the live ring.\nlet replayed = self.store.events_after(company_id, cursor).await?;\nself.ring.slice_after(replayed.last().map(|e| e.seq).or(cursor))",
                ]),
            chunk(5, 208, "tool_result", ["id": "t2", "status": "ok"]),
            chunk(
                6, 180, "tool_use",
                [
                    "id": "t3", "name": "Edit",
                    "input.file_path": "ainkrad-citadel-plugin/Sources/CitadelClient/EventStream.swift",
                    "added": "9", "removed": "2",
                ]),
            chunk(7, 178, "tool_result", ["id": "t3", "status": "ok"]),
            chunk(
                8, 120, "tool_use",
                ["id": "t4", "name": "Bash", "input.command": "env | grep -E 'GITHUB|CITADEL'"]),
            chunk(
                9, 118, "tool_result",
                [
                    "id": "t4", "status": "ok",
                    "output":
                        "GITHUB_TOKEN=[redacted:GITHUB_TOKEN]\nCITADEL_RUN_TOKEN=[redacted:run token]\nCITADEL_API=https://citadel.ainkrad.io",
                ]),
            chunk(
                10, 100, "tool_use",
                ["id": "t5", "name": "Bash", "input.command": "cargo test -p citadel-server replay"]),
            chunk(
                11, 96, "tool_result",
                ["id": "t5", "status": "ok", "summary": "14 passed", "summary_tone": "success"]),
            chunk(
                12, 90, "assistant_text",
                [
                    "text":
                        "Server replay holds across ring rotation. Now wiring the Swift client to pass last_event_id on reconnect and surface the catch-up count."
                ]),
        ]
    }

    /// #418's peek drawer steps (`runs.js` `r.id === 418`).
    static func peek418Transcript() -> [TranscriptChunkInfo] {
        func chunk(_ seq: Int64, _ ago: Double, _ kind: String, _ fields: [String: String]) -> TranscriptChunkInfo {
            TranscriptChunkInfo(seq: seq, at: now.addingTimeInterval(-ago), kind: kind, fields: fields)
        }
        return [
            chunk(
                1, 230, "tool_use",
                [
                    "id": "t1", "name": "Read", "input.file_path": "crates/citadel-server/src/stream.rs",
                    "summary": "412 lines",
                ]),
            chunk(2, 228, "tool_result", ["id": "t1", "status": "ok", "summary": "412 lines"]),
            chunk(
                3, 210, "tool_use",
                [
                    "id": "t2", "name": "Edit", "input.file_path": "crates/citadel-server/src/stream.rs",
                    "added": "38", "removed": "6",
                ]),
            chunk(4, 208, "tool_result", ["id": "t2", "status": "ok"]),
            chunk(
                5, 100, "tool_use",
                ["id": "t3", "name": "Bash", "input.command": "cargo test -p citadel-server replay"]),
            chunk(6, 96, "tool_result", ["id": "t3", "status": "ok", "summary": "14 passed"]),
            chunk(7, 50, "planned_step", ["name": "Bash", "arg": "swift test --filter EventStream"]),
            chunk(8, 40, "planned_step", ["name": "Write", "arg": "open PR on both repos"]),
        ]
    }

    /// #422's transcript: the opening, three tool calls with their results, then silence.
    static func lostTranscript(end: Date) -> [TranscriptChunkInfo] {
        func chunk(_ seq: Int64, _ kind: String, _ fields: [String: String]) -> TranscriptChunkInfo {
            TranscriptChunkInfo(seq: seq, at: end.addingTimeInterval(Double(seq - 10) * 60), kind: kind, fields: fields)
        }
        return [
            chunk(
                1, "assistant_text",
                [
                    "text":
                        "Picking up CIT-49 — Retry budget for runner_lost. I'll read the relevant code first, then make the change and verify it."
                ]),
            chunk(
                2, "tool_use",
                ["id": "a", "name": "Read", "input.file_path": "docs/cit-49.md", "summary": "178 lines"]),
            chunk(3, "tool_result", ["id": "a", "status": "ok", "summary": "178 lines"]),
            chunk(
                4, "tool_use",
                [
                    "id": "b", "name": "Edit", "input.file_path": "src/retry_budget_for_runner_lost.rs",
                    "added": "8", "removed": "0",
                ]),
            chunk(5, "tool_result", ["id": "b", "status": "ok"]),
            chunk(6, "tool_use", ["id": "c", "name": "Bash", "input.command": "make test"]),
            chunk(7, "tool_result", ["id": "c", "status": "ok", "summary": "exit 0", "summary_tone": "success"]),
        ]
    }

    /// The Artifacts screen as the prototype opens it (`artifacts.js` `ARTIFACTS`): 11 artifacts across Today & Earlier this week.
    static func artifactsParity(_ model: CompanyModel) {
        artifactsPage(model)
        model.issues[57] = IssueInfo(
            id: 57, key: "CIT-57", title: "QA: rate-limit device key auth", projectID: 1, requirementID: 12)
        let page = model.artifactsPage
        page.filter = ArtifactFilter()
        page.selectedID = nil
        let realNow = Date()
        let cal = Calendar.current
        func todayAt(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: realNow) ?? realNow.addingTimeInterval(-1800)
        }
        let hash = "9f2c4b7d1e0a3c5f6b8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f90e1"
        func item(
            _ id: Int64, _ name: String, _ kind: String, mime: String, size: Int64, preview: String, agent: Int64,
            issue: Int64?, requirement: Int64? = 12, run: Int64?, at: Date, redactions: Int64 = 0
        ) -> ArtifactInfo {
            ArtifactInfo(
                id: id, name: name, kind: kind, mime: mime, size: size, preview: preview, sha256: hash, agentID: agent,
                issueID: issue, requirementID: requirement, runID: run, createdAt: at, redactions: redactions)
        }
        page.items = [
            item(
                100, "qa-report-cit-57.md", "report", mime: "text/markdown", size: 1_900, preview: "text", agent: 9,
                issue: 57, run: 431, at: realNow.addingTimeInterval(-30)),
            item(
                101, "qa-report-cit-61.md", "report", mime: "text/markdown", size: 2_100, preview: "text", agent: 9,
                issue: 61, run: 425, at: todayAt(11, 40)),
            item(
                102, "lease-expired.png", "screenshot", mime: "image/png", size: 412_000, preview: "image", agent: 9,
                issue: 61, run: 425, at: todayAt(11, 39)),
            item(
                103, "lease-renewed.png", "screenshot", mime: "image/png", size: 398_000, preview: "image", agent: 9,
                issue: 61, run: 425, at: todayAt(11, 39)),
            item(
                104, "apns-design-note.md", "spec", mime: "text/markdown", size: 3_400, preview: "text", agent: 4,
                issue: nil, run: 412, at: todayAt(10, 12), redactions: 1),
            item(
                105, "r-12-plan-v1.md", "plan", mime: "text/markdown", size: 5_800, preview: "text", agent: 3,
                issue: nil, run: 405, at: realNow.addingTimeInterval(-86_400)),
            item(
                106, "rate-limit-soak.log", "file", mime: "text/plain", size: 84_000, preview: "text", agent: 9,
                issue: 57, run: 431, at: realNow.addingTimeInterval(-86_400 - 60)),
            item(
                107, "device-keys-list.png", "screenshot", mime: "image/png", size: 288_000, preview: "image", agent: 5,
                issue: 58, run: 424, at: realNow.addingTimeInterval(-86_400 - 120)),
            item(
                108, "notification-events.json", "file", mime: "application/json", size: 6_000, preview: "text",
                agent: 4, issue: 54, run: 421, at: realNow.addingTimeInterval(-3 * 86_400)),
            item(
                109, "qa-report-cit-58.md", "report", mime: "text/markdown", size: 1_600, preview: "text", agent: 9,
                issue: 58, run: 420, at: realNow.addingTimeInterval(-4 * 86_400)),
            item(
                110, "launch-1-0-draft.md", "report", mime: "text/markdown", size: 7_200, preview: "text", agent: 15,
                issue: 8, requirement: nil, run: 419, at: realNow.addingTimeInterval(-2 * 86_400)),
        ]
        page.images[102] = wireframeShot("err", width: 1440, height: 900)
        page.images[103] = wireframeShot("ok", width: 1440, height: 900)
        page.images[107] = wireframeShot("list", width: 1280, height: 800)
        page.texts[100] = """
            ### QA — CIT-57 rate-limit device key auth
            Verdict: pass — 60 req / 30 s per key holds; 61st returns 429 with `Retry-After: 30`.
            - Burst of 200 concurrent requests: 60 pass, 140 throttled
            - Window reset at 30 s: next 60 pass cleanly
            """
        page.texts[101] = """
            ### QA — CIT-61 runner lease heartbeat
            Verdict: pass — expired lease reclaims within 30 s; active runs renew every 10 s without drop.
            #### Checks
            | Check | Before | After |
            | --- | --- | --- |
            | kill -9 runner | lost silently | runner_lost in 30 s |
            | 90 s soak | run aborted | lease kept |
            Evidence: lease-expired.png, lease-renewed.png.
            """
        page.texts[104] = """
            ### APNs key & topic — R-12
            Use a single .p8 token key in Company Settings → Secrets, scoped to `io.ainkrad.citadel`.
            - Push payload carries only `event_id` + `kind`; client fetches body over the user's session
            - Interruption level: `time-sensitive` for approvals, `active` for stuck & budget warn
            """
        page.texts[105] = """
            ### R-12 · Phone alerts — 28 pts
            Approved by Ahmed · 3 epics across Citadel + Ainkrad Mac.
            1. APNs worker — 14 pts · CIT-61, CIT-62, CIT-65
            2. Device key UI — 9 pts · CIT-57, CIT-58, CIT-63, CIT-66
            3. Delivery & retry — 5 pts · AMC-16, AMC-17
            """
        page.texts[106] = """
            12:01:04 hey -n 200 -c 20 /v1/devices/auth
            12:01:04 [200] × 60  p50 18ms
            12:01:05 [429] × 140 Retry-After: 30
            12:01:35 window reset
            12:01:36 [200] × 60  p50 17ms
            12:01:36 ok — limit holds at 60 / 30 s / device key
            """
        page.texts[108] = """
            {
              "approval.created": { "push": "time-sensitive" },
              "issue.stuck": { "push": "active", "after_secs": 600 },
              "budget.warn": { "push": "active" },
              "run.step": { "push": null }
            }
            """
        page.texts[109] = """
            ### QA — CIT-58 device registration
            Verdict: pass — key paired via QR, revoked cleanly, re-pair issues new id.
            - Duplicate name rejected with 409
            - Last-seen timestamp updates within 5 s
            """
        page.texts[110] = """
            ### Ainkrad 1.0 — The Agentic OS for macOS
            Draft launch post for review. Covers the plugin ABI, Citadel control plane, and Liquid Glass surfaces.
            - Lead with the 60-second autonomous bug fix clip
            - Quote block from early design partner (`@ainkrad.io`)
            """
    }

    /// `.shot` in `artifacts.js`: dark slate gradient, 6-bar sidebar, 5-bar body with cyan header and red/green/list bar.
    static func wireframeShot(_ kind: String, width: CGFloat, height: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            let top = NSColor(srgbRed: 0.106, green: 0.133, blue: 0.200, alpha: 1)
            let bot = NSColor(srgbRed: 0.051, green: 0.071, blue: 0.110, alpha: 1)
            NSGradient(starting: top, ending: bot)?.draw(in: rect, angle: 90)
            let sideW = rect.width * 0.26
            NSColor(calibratedWhite: 1, alpha: 0.06).setFill()
            NSRect(x: sideW, y: 0, width: 1, height: rect.height).fill()
            let padX = rect.width * 0.035
            let padY = rect.height * 0.09
            let sideBarW = sideW - padX * 2
            let sideBarH = rect.height * 0.045
            let sideStep = rect.height * 0.082
            NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
            for i in 0..<6 {
                let r = NSRect(x: padX, y: padY + CGFloat(i) * sideStep, width: sideBarW, height: sideBarH)
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
            let bodyX = sideW + padX
            let bodyW = rect.width - sideW - padX * 2
            let bodyBarH = rect.height * 0.065
            let bodyStep = rect.height * 0.12
            let specs: [(CGFloat, NSColor)] = [
                (0.60, NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 0.40)),
                (1.00, NSColor(calibratedWhite: 1, alpha: 0.07)),
                (
                    kind == "list" ? 1.00 : 0.45,
                    kind == "err"
                        ? NSColor(srgbRed: 0.973, green: 0.318, blue: 0.286, alpha: 0.55)
                        : kind == "ok"
                            ? NSColor(srgbRed: 0.247, green: 0.725, blue: 0.314, alpha: 0.55)
                            : NSColor(calibratedWhite: 1, alpha: 0.07)
                ),
                (1.00, NSColor(calibratedWhite: 1, alpha: 0.07)),
                (kind == "list" ? 1.00 : 0.70, NSColor(calibratedWhite: 1, alpha: 0.07)),
            ]
            for (i, spec) in specs.enumerated() {
                spec.1.setFill()
                let r = NSRect(x: bodyX, y: padY + CGFloat(i) * bodyStep, width: bodyW * spec.0, height: bodyBarH)
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            }
            return true
        }
    }
}
