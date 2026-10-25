// design-lint: allow-file hex-color,raw-color the project and epic colours the prototype offers, stored by the server as #rrggbb
import AppKit
import SwiftUI

/// A project's or epic's colour as the server stores it (`#rrggbb`, API minor 18): the prototype's eight colour pairs
/// (`PN_COLS`) by their light colour, and any other colour with a deeper shade derived from it.
enum ProjectIdentity {
    /// Light and deep of each pair; the light one is what the server stores.
    static let pairs: [(light: String, deep: String)] = [
        ("#22d3ee", "#2563eb"), ("#a78bfa", "#6d28d9"), ("#f59e0b", "#e11d48"), ("#3fb950", "#0d9488"),
        ("#f472b6", "#9333ea"), ("#60a5fa", "#7c3aed"), ("#fb923c", "#dc2626"), ("#94a3b8", "#334155"),
    ]

    /// `#rrggbb` as a colour; `nil` for anything else.
    static func color(_ hex: String?) -> Color? {
        guard let rgb = CompanyLook.rgb(hex) else { return nil }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// The light and deep colours of a stored colour, or `nil` when none (or not `#rrggbb`) is stored.
    static func pair(_ hex: String?) -> (Color, Color)? {
        guard let hex, let light = color(hex) else { return nil }
        if let known = pairs.first(where: { $0.light == hex.lowercased() }), let deep = color(known.deep) {
            return (light, deep)
        }
        let ns = NSColor(light).usingColorSpace(.sRGB) ?? NSColor(light)
        return (light, Color(nsColor: ns.blended(withFraction: 0.45, of: .black) ?? ns))
    }

    /// The same pair for a choice index (what the New project sheet stores).
    static func pair(at index: Int) -> (Color, Color) {
        pair(pairs[index % pairs.count].light) ?? (.clear, .clear)
    }
}
