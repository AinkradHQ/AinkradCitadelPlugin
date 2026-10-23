import AinkradAppKit
import SwiftUI

/// Citadel's settings: which server, which key (shown masked), and a way to forget the key.
struct SettingsView: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            AinkradFormRow(title: "Server", help: "Plain http is accepted only for a server on this Mac.") {
                Text(store.settings.document.server ?? "Not set")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"), typography: typo))
                    .textSelection(.enabled)
            }
            AinkradFormRow(title: "Device key", help: "Kept in your Keychain; sent only as a bearer header.") {
                Text(store.storedKey.map { DeviceKeyStore.masked($0) } ?? "Not set")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"), typography: typo))
            }
            HStack(spacing: skin.size.s8) {
                AinkradButton(title: "Change server or key…", style: .secondary) { store.editConnection() }
                    .fixedSize()
                AinkradButton(title: "Forget this key", style: .danger) { store.disconnect() }
                    .fixedSize()
                    .disabled(store.storedKey == nil)
            }
        }
        .padding(.horizontal, skin.size.s20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
