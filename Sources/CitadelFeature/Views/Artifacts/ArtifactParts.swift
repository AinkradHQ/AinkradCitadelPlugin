import AinkradAppKit
import SwiftUI

/// A type tile's words, hue and icon (`ART_KIND`).
struct ArtifactTypeLook {
    let type: String

    static let tiles = ["report", "spec", "plan", "screenshot", "log", "data"]

    var plural: String {
        switch type {
        case "report": "Reports"
        case "spec": "Specs"
        case "plan": "Plans"
        case "screenshot": "Screenshots"
        case "log": "Logs"
        case "data": "Data"
        case "": "All"
        default: "Files"
        }
    }

    var singular: String { type == "data" ? "Data" : String(plural.dropLast()) }

    var hue: Hue {
        switch type {
        case "report": .green
        case "spec": .violet
        case "plan": .blue
        case "screenshot": .pink
        case "log": .amber
        case "data": .cyan
        default: .slate
        }
    }

    var icon: String {
        switch type {
        case "report": "doc.text"
        case "spec": "diamond"
        case "plan": "list.bullet"
        case "screenshot": "photo"
        case "log": "chevron.right"
        case "data": "curlybraces"
        case "": "square.stack.3d.up"
        default: "doc"
        }
    }
}

/// What a card, the drawer and Quick Look show of an artifact: rendered Markdown, the image, coloured log / JSON
/// lines, or an icon when there is no preview.
struct ArtifactPreviewBody: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    /// `card` (a mini render under the badge), `drawer`, `quickLook`.
    var size: Size = .card

    enum Size { case card, sibling, drawer, quickLook }

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.artifactsPage
        let tint = ArtifactTypeLook(type: artifact.type).hue.color(skin)
        if let image = page.images[artifact.id] {
            Image(nsImage: image).resizable()
                .clipShape(RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                        .strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1)
                )
                .padding(.horizontal, size == .card ? skin.size.s10 : size == .sibling ? skin.size.s6 : skin.size.s14)
                .padding(.top, size == .card ? skin.size.s36 : size == .sibling ? skin.size.s6 : skin.size.s14)
                .padding(.bottom, size == .card ? skin.size.s8 : size == .sibling ? skin.size.s6 : skin.size.s14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(artifact.name)
        } else if let text = page.texts[artifact.id] {
            if artifact.isMarkdown {
                ArtifactDoc(text: text, size: size)
            } else {
                ArtifactCode(
                    lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), size: size)
            }
        } else {
            Image(systemName: ArtifactTypeLook(type: artifact.type).icon)
                .citadelFont(size == .card ? "t28" : "t34").foregroundStyle(tint.opacity(skin.opacity.o60))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// `.doc`: rendered Markdown for cards (`.doc.mini`, tables hidden), drawer (`.atd-pv .doc`), and Quick Look (`.ql-b .doc`).
private struct ArtifactDoc: View {
    let text: String
    let size: ArtifactPreviewBody.Size
    @Environment(\.ainkradSkin) private var skin

    private var isMini: Bool { size == .card || size == .sibling }
    private var h3Font: String { size == .quickLook ? "t22" : size == .drawer ? "t15" : "t11_5" }
    private var h4Font: String { size == .quickLook ? "t14" : size == .drawer ? "t12" : "t10" }
    private var bodyFont: String { size == .quickLook ? "t14" : size == .drawer ? "t12_5" : "t11" }

    var body: some View {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .leading, spacing: size == .quickLook ? skin.size.s6 : skin.size.s4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    EmptyView()
                } else if line.hasPrefix("#### ") {
                    let h4 = String(line.dropFirst(5))
                    Text(isMini ? h4.uppercased() : h4)
                        .citadelFont(h4Font, weight: "semibold")
                        .foregroundStyle(skin.color(isMini ? skin.text.faint : skin.text.muted))
                        .padding(.top, size == .quickLook ? skin.size.s10 : skin.size.s4)
                } else if line.hasPrefix("### ") || line.hasPrefix("# ") {
                    let h3 = line.hasPrefix("### ") ? String(line.dropFirst(4)) : String(line.dropFirst(2))
                    Text(h3)
                        .citadelFont(h3Font, weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary))
                        .padding(.bottom, skin.size.s2)
                } else if line.hasPrefix("|") {
                    if !isMini, !line.contains("---") { tableRow(line) }
                } else if line.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: skin.size.s6) {
                        Text("•").foregroundStyle(skin.color(skin.text.muted))
                        styled(String(line.dropFirst(2)))
                    }
                    .citadelFont(bodyFont)
                } else {
                    styled(line).citadelFont(bodyFont)
                }
            }
        }
        .foregroundStyle(skin.color(skin.text.muted))
        .frame(maxWidth: size == .quickLook ? skin.size.s860 * 0.884 : .infinity, alignment: .leading)
        .padding(.horizontal, isMini ? skin.size.s14 : size == .drawer ? skin.size.s18 : skin.size.s28)
        .padding(
            .top,
            size == .card
                ? skin.size.s38 : size == .sibling ? skin.size.s8 : size == .drawer ? skin.size.s16 : skin.size.s28
        )
        .padding(.bottom, isMini ? skin.size.s10 : size == .drawer ? skin.size.s16 : skin.size.s28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .quickLook ? .top : .topLeading)
    }

    private func tableRow(_ line: String) -> some View {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                let isErr = cell == "lost silently" || cell == "run aborted"
                let isOk = cell == "runner_lost in 30 s" || cell == "lease kept"
                let color: Color =
                    isErr
                    ? skin.color(skin.palette.danger)
                    : isOk
                        ? skin.color(skin.palette.success)
                        : idx == 0 ? skin.color(skin.text.primary) : skin.color(skin.text.muted)
                Text(cell)
                    .citadelFont(size == .quickLook ? "t13" : "t11_5", mono: idx == 0)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, size == .quickLook ? skin.size.s12 : skin.size.s8)
                    .padding(.vertical, size == .quickLook ? skin.size.s8 : skin.size.s5)
            }
        }
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)),
            in: RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous))
    }

    private func styled(_ line: String) -> Text {
        if let rest = line.split(separator: "Verdict: pass", maxSplits: 1, omittingEmptySubsequences: false).first,
            line.contains("Verdict: pass")
        {
            let tail = String(line.dropFirst(rest.count + "Verdict: pass".count))
            return Text("Verdict: ").fontWeight(.semibold).foregroundStyle(skin.color(skin.text.primary))
                + Text("pass").fontWeight(.semibold).foregroundStyle(skin.color(skin.palette.success))
                + inlineTokens(tail)
        }
        return inlineTokens(line)
    }

    private func inlineTokens(_ text: String) -> Text {
        var out = Text("")
        var rest = Substring(text)
        let pattern =
            /(\*\*[^*]+\*\*)|(`[^`]+`)|(lease-expired\.png|lease-renewed\.png|\.p8|time-sensitive|active|@ainkrad\.io)/
        while let match = rest.firstMatch(of: pattern) {
            out = out + Text(String(rest[rest.startIndex..<match.range.lowerBound]))
            let piece = String(rest[match.range])
            if match.output.1 != nil {
                out =
                    out
                    + Text(String(piece.dropFirst(2).dropLast(2))).fontWeight(.semibold)
                    .foregroundStyle(skin.color(skin.text.primary))
            } else {
                let clean = match.output.2 != nil ? String(piece.dropFirst().dropLast()) : piece
                out =
                    out
                    + Text(clean)
                    .font(skin.font(AinkradFontToken(sizeKey: isMini ? "t10_5" : "t11_5", mono: "family")))
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
            }
            rest = rest[match.range.upperBound...]
        }
        return out + Text(String(rest))
    }
}

/// `.art-code`: mono lines, `[2xx]` and `ok` green, `[4xx]` amber, JSON keys blue.
struct ArtifactCode: View {
    let lines: [String]
    var size: ArtifactPreviewBody.Size = .card
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shown = size == .card || size == .sibling ? Array(lines.prefix(6)) : lines
        VStack(alignment: .leading, spacing: skin.size.s1) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in colored(line) }
        }
        .citadelFont(size == .quickLook ? "t13" : size == .drawer ? "t11" : size == .sibling ? "t8" : "t10", mono: true)
        .foregroundStyle(skin.color(skin.text.muted))
        .lineLimit(size == .card || size == .sibling ? 1 : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, size == .quickLook ? skin.size.s24 : skin.size.s14)
        .padding(.top, size == .card ? skin.size.s40 : size == .quickLook ? skin.size.s24 : skin.size.s12)
    }

    private func colored(_ line: String) -> Text {
        var text = Text("")
        var rest = Substring(line)
        let pattern = /(\[2\d\d\]|\bok\b)|(\[4\d\d\])|("[^"]+")(?=:)/
        while let match = rest.firstMatch(of: pattern) {
            text = text + Text(String(rest[rest.startIndex..<match.range.lowerBound]))
            let piece = String(rest[match.range])
            let color: Color =
                match.output.1 != nil
                ? skin.color(skin.palette.success)
                : match.output.2 != nil ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentSecondary)
            text = text + Text(piece).foregroundStyle(color)
            rest = rest[match.range.upperBound...]
        }
        return text + Text(String(rest))
    }
}

/// `.ac2`: the grid card — a preview well washed in the type's colour, its badge, the publisher's orb, the name and
/// a line of issue · when · size; lifts and zooms on hover, ringed when selected, flashes when it arrives.
struct ArtifactGridCard: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let isSelected: Bool
    let isFresh: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var flash = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let look = ArtifactTypeLook(type: artifact.type)
        let tint = look.hue.color(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let well = RoundedRectangle(cornerRadius: skin.size.s13, style: .continuous)
        AinkradTapArea(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ArtifactPreviewBody(model: model, artifact: artifact)
                        .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    LinearGradient(
                        colors: [.clear, skin.color(.palette("background", skin.opacity.o90))], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: skin.size.s46)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    TypeBadge(look: look)
                        .padding(skin.size.s6)
                }
                .frame(height: skin.size.s150)
                .background(
                    well.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(skin.opacity.o14), skin.color(.palette("background", skin.opacity.o90)),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(well)
                .padding(skin.size.s6)
                .overlay(alignment: .bottomTrailing) {
                    if let agent = model.agent(artifact.agentID) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s26)
                            .background(Circle().fill(skin.color(.palette("background", 1))).padding(-skin.size.s3))
                            .padding(skin.size.s12)
                    }
                }
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    Text(artifact.name).citadelFont("t12_5", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary)
                    )
                    .lineLimit(1)
                    HStack(spacing: skin.size.s6) {
                        Text(model.issue(artifact.issueID)?.key ?? model.requirementKey(artifact) ?? "—")
                            .citadelFont("t11", mono: true)
                        Spacer(minLength: skin.size.s4)
                        Text("\(ArtifactsWhen.short(artifact.createdAt)) · \(ScopedSetting.bytes(artifact.size))")
                            .citadelFont("t11")
                    }
                    .foregroundStyle(skin.color(skin.text.faint))
                    .lineLimit(1)
                }
                .padding(.horizontal, skin.size.s14)
                .padding(.top, skin.size.s2)
                .padding(.bottom, skin.size.s12)
            }
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
            .overlay(
                shape.strokeBorder(
                    isSelected
                        ? tint.opacity(skin.opacity.o60)
                        : hovering
                            ? tint.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1)
            )
            .background(shape.stroke(tint.opacity(isSelected ? skin.opacity.o35 : 0), lineWidth: skin.size.s2 * 2))
            .shadow(
                color: (flash ? skin.color(skin.palette.warning) : skin.color(.palette("black", 1))).opacity(
                    flash ? skin.opacity.o45 : hovering ? skin.opacity.o35 : 0), radius: skin.size.s20,
                y: hovering ? skin.size.s18 : 0
            )
            .contentShape(shape)
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s4 : 0)
        .onHover { hovering = $0 }
        .animation(
            skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.72)), value: hovering
        )
        .onAppear {
            guard isFresh, !reduceMotion else { return }
            flash = true
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 1.6))) { flash = false }
        }
    }
}

/// The card's type badge: icon + singular label in the type's colour on a dark glass chip.
struct TypeBadge: View {
    let look: ArtifactTypeLook
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            Image(systemName: look.icon).citadelFont("t10")
            Text(look.singular).citadelFont("t10_5", weight: "semibold")
        }
        .foregroundStyle(look.hue.color(skin))
        .padding(.leading, skin.size.s6)
        .padding(.trailing, skin.size.s8)
        .frame(height: skin.size.s22)
        .background(
            skin.color(.palette("background", skin.opacity.o78)), in: RoundedRectangle(cornerRadius: skin.size.s7))
    }
}

/// `.at-row`: type tile · name over "Type · 1440×900" · orb + agent · key · when · size · chevron on hover.
struct ArtifactRow: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let look = ArtifactTypeLook(type: artifact.type)
        let agent = model.agent(artifact.agentID)
        let dims =
            model.artifactsPage.images[artifact.id].map { " · \(Int($0.size.width))×\(Int($0.size.height))" } ?? ""
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s12) {
                IconTile(systemName: look.icon, tint: look.hue.color(skin), size: skin.size.s28, radius: skin.size.s8)
                    .frame(width: skin.size.s34)
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(artifact.name).citadelFont("t12_5", weight: "medium").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text("\(look.singular)\(dims)").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: skin.size.s7) {
                    if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s20) }
                    Text(agent?.name ?? "—").foregroundStyle(skin.color(skin.text.muted))
                    if let key = model.issue(artifact.issueID)?.key ?? model.requirementKey(artifact) {
                        Text("· ").foregroundStyle(skin.color(skin.text.muted))
                            + Text(key).foregroundStyle(skin.color(skin.palette.accentSecondary))
                            .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family")))
                    }
                }
                .citadelFont("t11")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ArtifactsWhen.short(artifact.createdAt)).frame(width: skin.size.s70, alignment: .trailing)
                Text(ScopedSetting.bytes(artifact.size)).frame(width: skin.size.s60, alignment: .trailing)
                Text("›").opacity(hovering ? 1 : 0).frame(width: skin.size.s14)
            }
            .citadelFont("t11", mono: true)
            .foregroundStyle(skin.color(skin.text.faint))
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s7)
            .background(
                skin.color(.palette("foreground", hovering || isSelected ? skin.opacity.o05 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// "now", "11:40" today, "Yesterday", "Wed" this week, "Oct 18" before.
enum ArtifactsWhen {
    private static let hhmm: Date.VerbatimFormatStyle = .verbatim(
        "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current)

    static func short(_ date: Date, now: Date = Date()) -> String {
        if (0..<120).contains(now.timeIntervalSince(date)) { return "now" }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return date.formatted(hhmm) }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return now.timeIntervalSince(date) < 2.5 * 86_400
            ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension CompanyModel {
    /// The requirement an artifact belongs to (its own, else its issue's).
    func requirementKey(_ artifact: ArtifactInfo) -> String? {
        let id = artifact.requirementID ?? issue(artifact.issueID)?.requirementID
        return requirements.first { $0.id == id }?.key
    }
}
