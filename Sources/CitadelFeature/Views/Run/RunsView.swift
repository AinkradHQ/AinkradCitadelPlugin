import AinkradAppKit
import SwiftUI

/// The Runs screen (prototype `runs.js`): a live stage on top — one card per run in flight, its decision inline
/// when it waits or stalls — and the history underneath as a day-grouped timeline. State tabs with counts, agent
/// and project pickers; any run opens the peek drawer, the transcript is one click further.
struct RunsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RunsPage { model.runsPage }

    var body: some View {
        let now = Date()
        let matching = model.runsMatching(tab: page.tab, agent: page.agentID, project: page.projectID, now: now)
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(title: "Runs", crumb: crumb(now)) {
                    AinkradDockButton("Pause all", systemImage: "pause", height: skin.size.s30) { store.pauseAll() }
                        .ainkradTooltip("Pause all runs")
                }
                bar(now).zIndex(2)
                Group {
                    if model.companyRuns == nil {
                        FirstLoadView()
                    } else if model.knownRuns.isEmpty {
                        AinkradEmptyState(
                            icon: "play", title: "No runs yet",
                            message: "A run starts when an agent is woken on an issue; it shows here, newest first.")
                    } else {
                        stage(matching, now: now)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay {
                    if page.openPicker != nil {
                        Color.clear.contentShape(Rectangle()).onTapGesture { page.openPicker = nil }
                    }
                }
                .offlineDimmed()
            }
            if let id = page.peekID, let run = model.runs[id] ?? model.knownRuns.first(where: { $0.id == id }) {
                RunsPeek(store: store, model: model, run: run)
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: page.peekID == nil)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: page.openPicker)
        .onAppear { store.loadRunsPage() }
    }

    /// `5 live runs · 7 finished runs today · $7.65 priced · ● live`.
    private func crumb(_ now: Date) -> Text {
        let today = Calendar.current.startOfDay(for: now)
        let finished = model.knownRuns.filter { !$0.isLive && ($0.endedAt ?? .distantPast) >= today }
        let priced = finished.compactMap(\.costMicros).reduce(0, +)
        let muted = skin.color(skin.text.muted)
        var text = Text("\(Wording.count(model.liveRuns.count, "live run")) · ").foregroundStyle(muted)
        text = text + Text("\(Wording.count(finished.count, "finished run")) today · ").foregroundStyle(muted)
        text = text + Text("\(Fmt.dollars(micros: priced)) priced").foregroundStyle(muted)
        if store.streamStatus == .live {
            text = text + Text(" · ").foregroundStyle(muted) + Text("● live").foregroundStyle(status.success)
        }
        return text
    }

    // MARK: - Filter bar

    private func bar(_ now: Date) -> some View {
        HStack(spacing: skin.size.s8) {
            AinkradGlideTabs(
                RunsTab.allCases.map {
                    AinkradGlideTab(
                        $0, title: $0.title, systemImage: $0.icon, count: "\(model.runsCount($0, now: now))")
                },
                selection: Binding(get: { page.tab }, set: { page.tab = $0 })
            )
            .frame(maxWidth: skin.size.s860)
            Spacer(minLength: 0)
            RunsAgentPicker(model: model, page: page)
            RunsProjectPicker(model: model, page: page)
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s12)
    }

    // MARK: - Stage and history

    private func stage(_ matching: [RunInfo], now: Date) -> some View {
        let live = matching.filter(\.isLive)
        let ended = matching.filter { !$0.isLive }
        return ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s22) {
                if !live.isEmpty {
                    VStack(alignment: .leading, spacing: skin.size.s10) {
                        RunsSectionHead(
                            title: "Live now", count: live.count,
                            note: "tokens vs run cap · warn at \(Int(model.warnFraction * 100))%")
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: skin.size.s268), spacing: skin.size.s12)],
                            spacing: skin.size.s12
                        ) {
                            ForEach(live) { run in
                                LiveRunCard(store: store, model: model, run: run) { store.peek(run: run.id) }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    RunsSectionHead(title: "History", count: ended.count, note: retention)
                    if ended.isEmpty && live.isEmpty {
                        empty
                    } else {
                        RunsHistory(store: store, model: model, runs: ended, now: now)
                    }
                }
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.top, skin.size.s2)
            .padding(.bottom, skin.size.s20)
        }
    }

    /// "transcripts kept 30 days", from the company's retention setting.
    private var retention: String? {
        model.limits["transcript.retention_secs"].map { "transcripts kept \(Wording.count($0.value / 86_400, "day"))" }
    }

    private var empty: some View {
        BentoTile {
            VStack(spacing: skin.size.s10) {
                AinkradEmptyState(icon: "play", title: "No runs match", message: "Clear a filter to see more.")
                AinkradDockButton("Clear filters", height: skin.size.s26) { page.clear() }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// `.rs-h`: an 11 pt label, a mono count chip, a faint note pushed right.
struct RunsSectionHead: View {
    let title: String
    let count: Int
    var note: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(title).citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
            Text("\(count)").citadelFont("t10", weight: "semibold", mono: true)
                .foregroundStyle(skin.color(skin.text.muted))
                .padding(.horizontal, skin.size.s6)
                .padding(.vertical, skin.size.s2)
                .background(
                    skin.color(.palette("foreground", skin.opacity.o07)),
                    in: RoundedRectangle(cornerRadius: skin.size.s6))
            Spacer(minLength: skin.size.s8)
            if let note { Text(note).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
        }
    }
}
