import AinkradAppKit
import SwiftUI

/// Screen 03 (prototype `org.js`): an org-chart canvas — CEO → departments → team clusters of agent figures, joined
/// by soft curves. Drag to pan, ⌘-scroll / pinch or the zoom buttons to zoom, Fit to see everything; a figure opens
/// the peek panel, right-click the agent menu; filters dim in place.
struct OrgView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let page = model.orgPage
        let layout = OrgLayout(model.departments)
        VStack(alignment: .leading, spacing: 0) {
            header
            ZStack {
                dotGrid
                PanZoomCanvas(
                    camera: Binding(get: { page.camera }, set: { page.camera = $0 }),
                    worldSize: CGSize(width: layout.width, height: layout.height)
                ) {
                    OrgWorld(store: store, model: model, layout: layout)
                }
                legend.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(skin.size.s14)
                zoom.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(skin.size.s14)
                if let id = page.picked, let agent = model.agents[id] {
                    OrgPeekPanel(store: store, model: model, agent: agent)
                        .padding(skin.size.s12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .offset(x: skin.size.s24)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous).strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o12)), lineWidth: 1)
            )
            .animation(
                reduceMotion
                    ? nil : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.9)),
                value: page.picked
            )
            .padding(.horizontal, skin.size.s20)
            .padding(.bottom, skin.size.s20)
            .offlineDimmed()
        }
        .orgSheets(store, model)
    }

    // MARK: - Header

    private var header: some View {
        let page = model.orgPage
        let pending = model.agents.values.filter(\.isHirePending).count
        let teams = model.departments.reduce(0) { $0 + $1.teams.count }
        return HStack(alignment: .center, spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("Org").citadelFont("t15", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                HStack(spacing: skin.size.s6) {
                    Text(Wording.count(model.agents.count, "agent"))
                    Text("·")
                    Text("\(Wording.count(model.departments.count, "department")) · \(Wording.count(teams, "team"))")
                    if pending > 0 {
                        Text("·")
                        HiresLink(count: pending) { page.sheet = .pendingHires }
                    }
                }
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1).fixedSize()
            }
            Spacer(minLength: skin.size.s10)
            AinkradGlideTabs(
                OrgFilter.allCases.map { filter in
                    AinkradGlideTab(
                        filter, title: filter.rawValue, systemImage: filter.icon,
                        count: "\(model.agents.values.filter(filter.matches).count)")
                }, selection: Binding(get: { page.filter }, set: { page.filter = $0 }), height: skin.size.s32
            )
            .frame(width: skin.size.s520)
            AinkradButton(title: "Structure", style: .secondary) { page.sheet = .structure(page.structureTab) }
                .fixedSize()
            AinkradDockButton("New agent", systemImage: "plus", tone: .primary, height: skin.size.s34) {
                page.sheet = .hire(team: nil, step: 0)
            }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s10)
    }

    // MARK: - Canvas furniture

    /// The canvas floor: a 22 pt dot grid over a faint wash.
    private var dotGrid: some View {
        Canvas { context, size in
            let step = skin.size.s22
            let dot = skin.color(.palette("foreground", skin.opacity.o07))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(dot))
                    x += step
                }
                y += step
            }
        }
        .background(skin.color(.palette("foreground", skin.opacity.o03)))
        .allowsHitTesting(false)
    }

    private var furniture: some ShapeStyle { skin.color(.palette("background", skin.opacity.o85)) }

    private var legend: some View {
        let counted = model.agents.values.filter { $0.orgRole != "ceo" }
        return HStack(spacing: skin.size.s14) {
            ForEach(OrgBucket.allCases, id: \.self) { bucket in
                let n = counted.filter { OrgBucket($0) == bucket }.count
                if n > 0 {
                    HStack(spacing: skin.size.s6) {
                        Circle().fill(bucket.tint(skin)).frame(width: skin.size.s7, height: skin.size.s7)
                        Text("\(bucket.label) \(n)")
                    }
                }
            }
        }
        .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
        .padding(.horizontal, skin.size.s12).frame(height: skin.size.s32)
        .background(furniture, in: RoundedRectangle(cornerRadius: skin.size.s10))
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }

    private var zoom: some View {
        let page = model.orgPage
        let animate = skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.28))
        return HStack(spacing: skin.size.s6) {
            AinkradIconButton(systemName: "minus", size: skin.size.s26, tooltip: "Zoom out") {
                withAnimation(reduceMotion ? nil : animate) { page.camera.zoom(by: 1 / 1.2) }
            }
            Text("\(page.camera.percent)%").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s44)
            AinkradIconButton(systemName: "plus", size: skin.size.s26, tooltip: "Zoom in") {
                withAnimation(reduceMotion ? nil : animate) { page.camera.zoom(by: 1.2) }
            }
            AinkradButton(title: "Fit", style: .secondary) {
                withAnimation(reduceMotion ? nil : animate) { page.camera.fit() }
            }
            .compact().fixedSize()
        }
        .padding(skin.size.s4)
        .background(furniture, in: RoundedRectangle(cornerRadius: skin.size.s12))
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }
}

/// `1 hire pending ›`: amber, underlined on hover; opens the pending hires sheet.
private struct HiresLink: View {
    let count: Int
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        AinkradTapArea(help: "Review pending hires", action: open) {
            Text("\(Wording.count(count, "hire")) pending ›").underline(hovering).foregroundStyle(status.warning)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
