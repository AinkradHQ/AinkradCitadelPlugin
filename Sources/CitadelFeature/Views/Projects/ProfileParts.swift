import AinkradAppKit
import CitadelClient
import SwiftUI

/// A profile group: a card with its title (and an optional note and action) over its rows.
struct ProfileGroup<Trailing: View, Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        // One section style across the config drawer: the same card as `ConfigSection`.
        ConfigSection(title: title, subtitle: note, trailing: { trailing }) {
            VStack(alignment: .leading, spacing: skin.size.s4) { content }
        }
    }
}

extension ProfileGroup where Trailing == EmptyView {
    init(title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, note: note, trailing: { EmptyView() }, content: content)
    }
}

/// A label and its value on one line (the mockup's `.srow`), the row lifting its fill on hover.
struct ProfileRow<Value: View, Trailing: View>: View {
    let label: String
    @ViewBuilder var value: Value
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            Text(label).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s96, alignment: .leading)
            value.citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: skin.size.s4)
            trailing
        }
        .padding(.vertical, skin.size.s4)
        .padding(.horizontal, skin.size.s4)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                .fill(skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .padding(.horizontal, -skin.size.s4)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

extension ProfileRow where Trailing == EmptyView {
    init(label: String, @ViewBuilder value: () -> Value) {
        self.init(label: label, value: value, trailing: { EmptyView() })
    }
}
