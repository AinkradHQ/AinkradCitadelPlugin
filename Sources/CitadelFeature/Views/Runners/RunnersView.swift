import AinkradAppKit
import SwiftUI

/// Screen 10 (prototype `runners.js`): the fleet overview — machines, capacity, disk, tag coverage — then one machine
/// card per runner with live vitals. Log, Re-login and Add runner open in the inset drawer.
struct RunnersView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RunnersPage { model.runnersPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(
                title: "Runners",
                crumb: Text("machines that run agents · server-wide").foregroundStyle(skin.color(skin.text.muted))
            ) {
                AinkradDockButton("Add runner", systemImage: "plus", tone: .primary) { openAdd() }
                    .help("Registers a runner and shows its start command with its key, once")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if page.isLoaded && page.runners.isEmpty {
                        AinkradEmptyState(
                            icon: "server.rack", title: "No runners yet",
                            message: "A runner is a machine that takes work. Register one with its install command."
                        )
                        .frame(maxWidth: .infinity).padding(.top, skin.size.s60)
                    } else if !page.isLoaded {
                        FirstLoadView()
                    } else {
                        VStack(alignment: .leading, spacing: skin.size.s12) {
                            RunnerOverview(page: page, running: running) { focus($0, proxy: proxy) }
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: skin.size.s460), spacing: skin.size.s14, alignment: .top)
                                ],
                                alignment: .leading, spacing: skin.size.s14
                            ) {
                                ForEach(Array(page.runners.enumerated()), id: \.element.id) { index, runner in
                                    RunnerCard(
                                        store: store, model: model, runner: runner, running: running[runner.id] ?? 0
                                    )
                                    .id(runner.id)
                                    .ainkradRiseIn(delay: 0.07 * Double(index))
                                }
                            }
                            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: page.runners)
                        }
                        .padding(.horizontal, skin.size.s20)
                        .padding(.bottom, skin.size.s20)
                    }
                }
                .scrollIndicators(.never)
            }
            .offlineDimmed()
        }
        .task { store.loadRunnersPage() }
        .onChange(of: page.runners.map(\.id)) { old, new in
            // A runner that joins while the page is open arrives flashed; the first load does not flash them all.
            guard !old.isEmpty, let joined = new.first(where: { !old.contains($0) }) else { return }
            flash(joined, for: 1.6)
        }
        .modifier(RunnerDrawers(store: store, page: page))
    }

    /// Live runs per runner: the slot pips.
    private var running: [Int64: Int] {
        Dictionary(grouping: model.liveRuns.compactMap(\.runnerID), by: { $0 }).mapValues(\.count)
    }

    private func openAdd() {
        page.registered = nil
        page.registerFailure = nil
        page.addStep = 0
        page.addDraft = AddRunnerDraft()
        page.adding = true
    }

    /// A fleet chip: scroll its card into view and flash it.
    private func focus(_ id: Int64, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : skin.animation(skin.motion.present)) { proxy.scrollTo(id, anchor: .center) }
        flash(id, for: 1.2)
    }

    /// Lights a card's ring for a moment (the prototype's `arrive` / fleet flash).
    private func flash(_ id: Int64, for seconds: Double) {
        page.flashed = id
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if page.flashed == id { page.flashed = nil }
        }
    }
}

/// The three drawers over the screen: the log, Re-login and Add runner.
private struct RunnerDrawers: ViewModifier {
    let store: CitadelStore
    let page: RunnersPage
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        let logRunner = page.runners.first { $0.id == page.log?.runner }
        let reloginRunner = page.runners.first { $0.id == page.relogin }
        let logOpen = Binding(get: { page.log != nil }, set: { if !$0 { page.log = nil } })
        let reloginOpen = Binding(get: { page.relogin != nil }, set: { if !$0 { page.relogin = nil } })
        let addOpen = Binding(get: { page.adding }, set: { if !$0 { closeAdd() } })
        content
            .ainkradFloatingDrawer(isPresented: logOpen, top: skin.size.s62) {
                AinkradDrawerPanel(
                    style: .form, isTranslucent: true, onClose: { logOpen.wrappedValue = false },
                    header: { AinkradDrawerCrumb(["Runners", "\(logRunner?.name ?? "Runner") · log"]) },
                    content: {
                        if let logRunner {
                            RunnerLogDrawer(page: page, runner: logRunner, lines: page.log?.lines ?? [])
                        }
                    })
            }
            .ainkradFloatingDrawer(isPresented: reloginOpen, top: skin.size.s62) {
                AinkradDrawerPanel(
                    style: .form, isTranslucent: true, onClose: { reloginOpen.wrappedValue = false },
                    header: { AinkradDrawerCrumb(["Runners", "Re-login on \(reloginRunner?.name ?? "runner")"]) },
                    content: {
                        if let reloginRunner { RunnerReloginDrawer(page: page, runner: reloginRunner) }
                    },
                    footer: {
                        if let reloginRunner { ReloginFoot(page: page, runner: reloginRunner) }
                    })
            }
            .ainkradFloatingDrawer(isPresented: addOpen, top: skin.size.s62) {
                AinkradDrawerPanel(
                    style: .form, isTranslucent: true, onClose: { addOpen.wrappedValue = false },
                    header: { AinkradDrawerCrumb(["Runners", "Add a runner"]) },
                    content: { AddRunnerDrawer(store: store, page: page) },
                    footer: { AddRunnerFoot(store: store, page: page, close: closeAdd) })
            }
    }

    private func closeAdd() {
        page.adding = false
        page.registered = nil
        page.registerFailure = nil
    }
}
