import AinkradAppKit
import SwiftUI

/// The connect card's status block (mockup 01 `.state`): a glyph or spinner, a bold line, muted detail, on a fill
/// tinted by the state. Nothing in `.setup`.
struct ConnectStatusBlock: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        switch store.phase {
        case .setup:
            EmptyView()
        case .connecting(let step, let label, let since):
            block(tint: nil) {
                AinkradSpinner(size: skin.size.s12)
            } content: {
                title(label, color: skin.color(skin.text.primary))
                TimelineView(.periodic(from: since, by: 0.1)) { context in
                    let ms = max(0, Int(context.date.timeIntervalSince(since) * 1000))
                    detail(Text(verbatim: "Step \(step) of \(CitadelStore.steps) · \(ms) ms"))
                }
            }
        case .connected:
            block(tint: status.success) {
                Text("●").foregroundStyle(status.success)
            } content: {
                title(connectedTitle, color: status.success)
                detail(Text(verbatim: connectedFacts), mono: true)
                detail(Text(verbatim: replayLine))
            }
        case .rejected:
            block(tint: status.danger) {
                Image(systemName: "xmark.circle").foregroundStyle(status.danger)
            } content: {
                title("This key was revoked or never existed", color: status.danger)
                detail(Text("The server answered 401. Nothing was stored."))
                if store.showsKeyHelp {
                    detail(
                        Text(
                            "A device key belongs to one Mac. Create one on the server with `citadel-server device add`, revoke it with `citadel-server device revoke`; it is sent only as a bearer header and kept in your Keychain."
                        ))
                }
            }
        case .offline(let attempt, let retryAt, _):
            block(tint: status.warning) {
                Image(systemName: "circle.dotted").foregroundStyle(status.warning)
            } content: {
                title("Can't reach \(store.host)", color: status.warning)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    detail(
                        Text(lastSeen(at: context.date)) + Text("Retrying in ")
                            + Text(verbatim: "\(Self.seconds(until: retryAt, from: context.date))s")
                            .font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"), typography: typo))
                            + Text(verbatim: " · attempt \(attempt)"))
                }
            }
        }
    }

    private var connectedTitle: String {
        let name = store.company?.name ?? store.host
        guard let agents = store.agentCount else { return name }
        return "\(name) · \(agents) agent\(agents == 1 ? "" : "s")"
    }

    /// The server's version is not on the API yet (follow-up), so: host, API, round trip.
    private var connectedFacts: String {
        var facts = ["\(store.host)", "api 1"]
        if let latency = store.latency {
            facts.append("\(Int(latency / .milliseconds(1))) ms")
        }
        return facts.joined(separator: " · ")
    }

    private var replayLine: String {
        let replayed = store.replayed
        guard replayed > 0 else { return "Streaming live events." }
        return "Replayed \(replayed.formatted()) event\(replayed == 1 ? "" : "s") since you were last here."
    }

    private func lastSeen(at now: Date) -> String {
        guard let seen = store.settings.document.lastSeen else { return "" }
        let minutes = Int(now.timeIntervalSince(seen) / 60)
        return minutes < 1 ? "Last seen just now. " : "Last seen \(minutes) min ago. "
    }

    static func seconds(until date: Date, from now: Date) -> Int {
        max(0, Int(date.timeIntervalSince(now).rounded(.up)))
    }

    private func title(_ text: String, color: Color) -> some View {
        Text(text)
            .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "bold"), typography: typo))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: Text, mono: Bool = false) -> some View {
        text
            .font(
                skin.font(
                    AinkradFontToken(sizeKey: mono ? "t11" : "t12", mono: mono ? "family" : nil), typography: typo)
            )
            .foregroundStyle(skin.color(skin.text.muted))
            .lineSpacing(skin.size.s2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func block<Glyph: View, Content: View>(
        tint: Color?, @ViewBuilder glyph: () -> Glyph, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
            glyph()
                .font(skin.font(AinkradFontToken(sizeKey: "t12"), typography: typo))
                .frame(width: skin.size.s14)
            VStack(alignment: .leading, spacing: skin.size.s2) { content() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                .fill(
                    tint.map { $0.opacity(skin.opacity.o10) }
                        ?? skin.color(skin.palette.white).opacity(skin.opacity.o05))
        )
        .transition(.opacity)
    }
}
