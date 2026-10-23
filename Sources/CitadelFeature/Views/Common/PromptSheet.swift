import AinkradAppKit
import SwiftUI

/// A one-field sheet: a title, what happens, the field and its confirm (Rename…, Reject…, Cancel requirement…).
struct PromptSheet: View {
    let title: String
    let message: String
    let placeholder: String
    let confirmTitle: String
    var isDestructive = false
    /// An empty field is fine (an optional reason).
    var allowsEmpty = false
    @State var text: String
    @Binding var isPresented: Bool
    let confirm: (String) -> Void
    @Environment(\.ainkradSkin) private var skin

    private var canConfirm: Bool { allowsEmpty || !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text(title).citadelFont("t15", weight: "semibold")
            Text(message).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                .fixedSize(horizontal: false, vertical: true)
            AinkradTextField(text: $text, placeholder: placeholder).onSubmit(done)
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: confirmTitle, style: isDestructive ? .danger : .primary, action: done)
                    .fixedSize().disabled(!canConfirm)
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s440)
    }

    private func done() {
        guard canConfirm else { return }
        confirm(text)
        isPresented = false
    }
}
