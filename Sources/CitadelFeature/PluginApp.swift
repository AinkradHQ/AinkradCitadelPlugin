import AinkradAppKit
import SwiftUI

/// Citadel: watch and run your agent company on a Citadel server — org, live runs, approvals, chat, cost. Read
/// theme via `host.theme.tokens`, persist via `host.documents`, keep the device key in `host.secrets` — never host
/// internals.
public struct CitadelApp: AinkradApp, AinkradAppTeardown {
    public static let id = "citadel"
    public static let displayName = "Citadel"
    public static let icon = "building.columns"

    /// One connection per host-minted instance, so the settings page and every open window of that instance share
    /// it, and `teardown` stops it.
    private static let stores = PluginInstanceStorage<CitadelStore>()

    /// The instance a host stands for. A host that does not identify itself
    /// (see `PluginInstanceIdentity`) gets one id minted per process.
    private static let fallbackInstance = PluginInstanceID()

    static func store(host: HostServices) -> CitadelStore {
        let instance = (host as? PluginInstanceIdentity)?.instanceID ?? fallbackInstance
        return stores.value(for: instance) {
            CitadelStore(settings: SettingsStore(documents: host.documents), secrets: host.secrets)
        }
    }

    public static func teardown(instance: PluginInstanceID) {
        stores.remove(instance)?.stop()
    }

    public static func makeRootView(host: HostServices) -> AnyView {
        AnyView(RootView(store: store(host: host), theme: host.theme))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(SettingsView(store: store(host: host)).ainkradHostTheme(host.theme))
    }
}
