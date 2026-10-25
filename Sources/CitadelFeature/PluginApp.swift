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

    /// One continuous glass surface (the prototype's window): the theme background at the user's surface opacity.
    /// Translucent, so the host draws its sky backdrop (blurred when Blur is on) behind the pane and no title strip.
    /// The observable settings read keeps the fill live while the slider moves.
    public static func chromeFill(host: HostServices) -> Color? {
        host.theme.tokens.background.opacity(store(host: host).settings.document.resolvedSurfaceOpacity)
    }

    /// The connection pane, and an Appearance group whose transparency slider also earns the host's Blur toggle.
    public static func settingsCatalog(host: HostServices) -> SettingsPage? {
        let settings = store(host: host).settings
        let root = SettingsPath(["appearance"])
        return SettingsPage(
            path: SettingsPath([id]), title: displayName, icon: icon, group: .installedApps, order: 0,
            groups: [
                SettingsGroup(
                    path: SettingsPath(["connection"]), title: "Connection",
                    fields: [
                        SettingsField(
                            path: SettingsPath(["connection", "server"]), label: "Server",
                            kind: .custom(makeSettingsView(host: host)))
                    ]),
                SettingsGroup(
                    path: root, title: "Appearance",
                    footerNote: "How much of the workspace shows through Citadel's window. The blur is the host's.",
                    fields: [
                        SettingsField(
                            path: root.appending("opacity"), label: "Surface opacity",
                            help: "Lower is more see-through.",
                            keywords: ["transparency", "translucent", "opacity", "glass", "blur", "appearance"],
                            kind: .slider(
                                range: SettingsDocument.surfaceOpacityRange, step: 0.05,
                                value: Binding(
                                    get: { settings.document.resolvedSurfaceOpacity },
                                    set: { value in settings.update { $0.surfaceOpacity = value } })),
                            defaultDescription: "\(Int(SettingsDocument.defaultSurfaceOpacity * 100))%",
                            isModified: { settings.document.surfaceOpacity != nil },
                            reset: { settings.update { $0.surfaceOpacity = nil } })
                    ]),
            ],
            appID: id)
    }
}
