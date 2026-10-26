import AinkradAppKit
import SwiftUI

/// Company settings › Notifications (`settings.js` Notifications): the event × channel matrix, quiet hours on the
/// 24-hour track, what breaks through, and "Send a test". From API minor 18 the server stores all of it; below that
/// the matrix is drawn disabled and says what happens today: toasts on this Mac.
struct NotificationsSection: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin

    private var events: [String] { NotificationPrefs.events.map(\.title) }

    var body: some View {
        SettingsScroll {
            if store.notificationsOn {
                SettingsHero(section: .notifications) {
                    AinkradDockButton("Send a test", systemImage: "paperplane") { store.sendTestNotification() }
                }
                if let prefs = store.model?.notifications {
                    matrix(prefs)
                    quietHours(prefs)
                } else {
                    VStack(spacing: skin.size.s8) {
                        ForEach(0..<3, id: \.self) { _ in AinkradSkeletonRow().ainkradShimmer() }
                    }
                }
            } else {
                legacy
            }
        }
        .task { store.loadNotifications() }
    }

    private func matrix(_ prefs: NotificationPrefs) -> some View {
        SettingsCard(hint: nil) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                header
                ForEach(NotificationPrefs.events, id: \.key) { event in
                    GridRow {
                        Text(event.title).citadelFont("t13").foregroundStyle(skin.color(skin.text.primary))
                            .padding(.vertical, skin.size.s10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(NotificationPrefs.channels, id: \.self) { channel in
                            AinkradToggle(
                                isOn: Binding(
                                    get: { prefs.isOn(event.key, channel) },
                                    set: { store.setNotification(event: event.key, channel: channel, on: $0) })
                            )
                            .frame(width: skin.size.s92)
                        }
                    }
                }
            }
            .padding(.bottom, skin.size.s6)
        }
    }

    private func quietHours(_ prefs: NotificationPrefs) -> some View {
        SettingsCard(title: "Quiet hours") {
            AinkradDayRangeTrack(
                start: hours(prefs.quietStart) { store.setQuiet(start: $0) },
                end: hours(prefs.quietEnd) { store.setQuiet(end: $0) }, wraps: true, isOn: prefs.quietOn
            )
            .padding(.top, skin.size.s8).padding(.bottom, skin.size.s4)
            SettingsRow(label: "Mute pushes", hint: "drag the bar or type the times") {
                timePill(prefs.quietStart) { store.setQuiet(start: $0) }
                Text("to").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                timePill(prefs.quietEnd) { store.setQuiet(end: $0) }
                AinkradToggle(isOn: Binding(get: { prefs.quietOn }, set: { store.setQuiet(on: $0) }))
            }
            SettingsRow(label: "Break through for", hint: "still pushes during quiet hours") {
                AinkradSegmentedPicker(
                    items: ["stalled", "nothing"],
                    selection: Binding(get: { prefs.breakthrough }, set: { store.setQuiet(breakthrough: $0) })
                ) { $0 == "stalled" ? "Stalled production work" : "Nothing" }
                .controlSize(.small).fixedSize()
            }
        }
    }

    /// The track's 0 to 24 hours over minutes from midnight; a drag writes once, when it settles.
    private func hours(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Double> {
        Binding(get: { Double(minutes) / 60 }, set: { set(min(1439, Int(($0 * 60).rounded()))) })
    }

    private func timePill(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        AinkradValuePill(text: NotificationPrefs.clock(minutes), help: "hh:mm") { text in
            if let parsed = NotificationPrefs.minutes(text) {
                set(parsed)
            } else {
                store.toast(
                    AinkradRichToast(
                        title: "Time is hh:mm", body: "“\(text)” was refused · 22:00, 7:30", status: .danger))
            }
        }
    }

    private var header: some View {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            channel("iphone", "Phone push", skin.color(skin.palette.accentPrimary))
            channel("bubble.left", "Signal", skin.color(skin.palette.accentViolet))
            channel("envelope", "Email", skin.color(CompanySettingsSection.notificationsPink))
        }
    }

    @ViewBuilder private var legacy: some View {
        SettingsHero(section: .notifications)
        SettingsCard(hint: nil) {
            Text(
                "Citadel stores no notification preferences yet — today what needs you arrives as a toast on this Mac."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).padding(.top, skin.size.s10)
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    channel("iphone", "Phone push", skin.color(skin.palette.accentPrimary))
                    channel("bubble.left", "Signal", skin.color(skin.palette.accentViolet))
                    channel("envelope", "Email", skin.color(CompanySettingsSection.notificationsPink))
                }
                ForEach(events, id: \.self) { event in
                    GridRow {
                        Text(event).citadelFont("t13").foregroundStyle(skin.color(skin.text.primary))
                            .padding(.vertical, skin.size.s10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<3, id: \.self) { _ in
                            AinkradToggle(isOn: .constant(false)).disabled(true).frame(width: skin.size.s92)
                        }
                    }
                }
            }
            .padding(.bottom, skin.size.s6)
        }
        SettingsCard(title: "Quiet hours") {
            SettingsRow(label: "Mute pushes", hint: "drag the bar or type the times") {
                ServerSoonChip()
                AinkradValuePill(text: "22:00") { _ in }.editable(false)
                Text("to").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                AinkradValuePill(text: "07:30") { _ in }.editable(false)
                AinkradToggle(isOn: .constant(false)).disabled(true)
            }
            SettingsRow(label: "Break through for", hint: "still pushes during quiet hours") {
                AinkradSegmentedPicker(
                    items: ["Stalled production work", "Nothing"], selection: .constant("Stalled production work"),
                    label: { $0 }
                )
                .controlSize(.small).fixedSize().disabled(true)
            }
        }
    }

    private func channel(_ icon: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: skin.size.s6) {
            Image(systemName: icon).citadelFont("t14").foregroundStyle(tint)
                .frame(width: skin.size.s34, height: skin.size.s34)
                .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
            Text(title).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
        }
        .frame(width: skin.size.s92)
        .padding(.top, skin.size.s12)
        .padding(.bottom, skin.size.s10)
    }
}
