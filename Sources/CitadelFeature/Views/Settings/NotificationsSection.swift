import AinkradAppKit
import SwiftUI

/// Company settings › Notifications (`settings.js` Notifications): the event × channel matrix and quiet hours. The
/// server stores none of it yet (no preferences, channels or quiet hours), so the matrix is drawn disabled and says
/// what happens today: toasts on this Mac.
struct NotificationsSection: View {
    @Environment(\.ainkradSkin) private var skin

    private let events = [
        "Approval waiting on you", "Run waiting on a permission", "Agent asks you a question",
        "Issue stuck / stalled run",
        "Budget past warn %", "Account at a window limit", "Run finished", "Requirement done",
    ]

    var body: some View {
        SettingsScroll {
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
