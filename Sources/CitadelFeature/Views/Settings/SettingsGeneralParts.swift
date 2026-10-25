// design-lint: allow-file hex-color the seven colours the prototype offers, stored by the server as #rrggbb
import AinkradAppKit
import AppKit
import CitadelClient
import SwiftUI
import UniformTypeIdentifiers

/// The values General offers for a company the server stores none for yet: the prototype's colours and zones, and
/// the working hours and days it starts from.
enum SettingsCompanyDefaults {
    /// The prototype's seven colours (`SX_COLORS`), stored as `#rrggbb`.
    static let colors = ["#2563eb", "#10b981", "#a855f7", "#f59e0b", "#ef4444", "#0ea5e9", "#ec4899"]
    /// The time zones the menu offers (`SX_TZ`).
    static let zones = [
        "Europe/Warsaw", "Europe/London", "Asia/Dubai", "Africa/Cairo", "America/New_York", "America/Los_Angeles",
        "Asia/Tokyo", "UTC",
    ]
    /// Minutes from midnight: 08:00 to 20:00.
    static let start: Int32 = 480
    static let end: Int32 = 1200
    /// Monday to Friday (bit 0 Monday).
    static let days: Int32 = 31
}

/// The colour row: the seven swatches, the company's own ringed; disabled with "not stored yet" on an older server.
struct SettingsColorSwatches: View {
    @Binding var color: String?
    let enabled: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            ForEach(SettingsCompanyDefaults.colors, id: \.self) { hex in
                let rgb = CompanyLook.rgb(hex)
                let fill = Color(.sRGB, red: rgb?.red ?? 0, green: rgb?.green ?? 0, blue: rgb?.blue ?? 0)
                AinkradTapArea(help: hex) {
                    if enabled { color = hex }
                } label: {
                    RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous).fill(fill)
                        .frame(width: skin.size.s24, height: skin.size.s24)
                        .padding(skin.size.s2)
                        .overlay(
                            RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                                .strokeBorder(fill, lineWidth: color == hex ? skin.size.s2 : 0))
                }
            }
            if !enabled { ServerSoonChip() }
        }
        .help(enabled ? "The company's colour" : "The server stores no company colour yet")
    }
}

/// The time zone menu: the zones the prototype offers, the company's shown by its IANA name.
struct SettingsTimeZoneMenu: View {
    @Binding var zone: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradMenuButton(
            items: SettingsCompanyDefaults.zones.map { id in AinkradMenuItem(title: id) { zone = id } }
        ) {
            HStack(spacing: skin.size.s6) {
                Image(systemName: "globe")
                Text(zone ?? "Not set").citadelFont("t12", mono: true)
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s6)
            .background(skin.color(.palette("foreground", skin.opacity.o05)), in: Capsule())
        }
        .fixedSize()
    }
}

/// The working-hours track (`sx-range`): both ends dragged on a 24 h bar, snapped to 30 minutes and at least an hour
/// apart. The end nearest where a drag starts is the one it moves.
struct SettingsWorkTrack: View {
    @Binding var start: Int32
    @Binding var end: Int32
    /// The end the current drag moves: `true` for the start.
    @State private var dragging: Bool?
    @Environment(\.ainkradSkin) private var skin

    private static let day: Int32 = 1440
    private static let step: Int32 = 30
    private static let minimum: Int32 = 60

    var body: some View {
        let width = skin.size.s380
        VStack(spacing: skin.size.s4) {
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("background", 1)).opacity(skin.opacity.o25))
                Capsule().fill(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o35))
                    .frame(width: position(end, width) - position(start, width), height: skin.size.s10)
                    .offset(x: position(start, width))
                handle(at: position(start, width))
                handle(at: position(end, width))
            }
            .frame(width: width, height: skin.size.s18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag(to: $0.location.x, from: $0.startLocation.x, width: width) }
                    .onEnded { _ in dragging = nil }
            )
            HStack {
                Text("\(Self.clock(start)) – \(Self.clock(end))")
                    .citadelFont("t11", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
                Spacer()
            }
            .frame(width: width)
        }
        .help("Drag the ends · 30 minute steps, at least an hour")
    }

    private func handle(at x: CGFloat) -> some View {
        Circle().fill(skin.color(skin.palette.accentPrimary))
            .overlay(Circle().strokeBorder(skin.color(.palette("background", 1)), lineWidth: skin.size.s2))
            .frame(width: skin.size.s18, height: skin.size.s18)
            .offset(x: x - skin.size.s18 / 2)
    }

    private func position(_ minute: Int32, _ width: CGFloat) -> CGFloat {
        CGFloat(minute) / CGFloat(Self.day) * width
    }

    private func drag(to x: CGFloat, from origin: CGFloat, width: CGFloat) {
        let movesStart =
            dragging
            ?? (abs(origin - position(start, width)) <= abs(origin - position(end, width)))
        dragging = movesStart
        let raw = Int32((x / width * CGFloat(Self.day)).rounded())
        let minute = (raw + Self.step / 2) / Self.step * Self.step
        if movesStart {
            start = min(max(minute, 0), end - Self.minimum)
        } else {
            end = max(min(minute, Self.day), start + Self.minimum)
        }
    }

    /// `09:30` for 570 minutes.
    static func clock(_ minutes: Int32) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// The seven working-day toggles; the bits of `days` (bit 0 Monday).
struct SettingsWorkDays: View {
    @Binding var days: Int32
    @Environment(\.ainkradSkin) private var skin

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: skin.size.s4) {
            ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                let bit = Int32(1) << index
                let on = days & bit != 0
                AinkradTapArea {
                    days ^= bit
                } label: {
                    Text(letter).citadelFont("t11", weight: "semibold")
                        .foregroundStyle(skin.color(on ? skin.text.primary : skin.text.faint))
                        .frame(width: skin.size.s28, height: skin.size.s28)
                        .background(
                            on
                                ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o25)
                                : skin.color(.palette("foreground", skin.opacity.o05)),
                            in: RoundedRectangle(cornerRadius: skin.size.s8))
                }
            }
        }
    }
}

/// The logo file General uploads: PNG, JPEG or WebP up to 2 MB, what the server takes. Anything else is a toast, not
/// a silent drop.
enum SettingsLogoFile {
    @MainActor
    static func choose(for name: String, store: CitadelStore) -> (data: Data, type: String)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.message = "Choose a logo for \(name)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
        guard let data = try? Data(contentsOf: url), data.count <= 2 << 20,
            let type, ["image/png", "image/jpeg", "image/webp"].contains(type), NSImage(data: data) != nil
        else {
            store.toast(
                AinkradRichToast(title: "Logo not used", body: "Use a PNG, JPG or WebP up to 2 MB.", status: .danger))
            return nil
        }
        return (data, type)
    }
}
