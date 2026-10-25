import AppKit
import CitadelClient
import Foundation

/// A company role (API minor 18): what the Roles tab edits and the hire wizard's role grid reads — a purpose, a
/// glyph, skills, standing instructions, and the harness, model and month budget a new agent of the role starts on.
struct RoleInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var purpose: String
    /// A glyph name the client draws (free text on the wire): an SF Symbol, else a generic person.
    var icon: String
    var skills: [String]
    var instructions: String
    var harness: String?
    var model: String?
    var budgetTokens: Int64?

    /// The hire wizard's role: the role's own choices where it has them, else the first role's.
    var catalogRole: HireCatalog.Role {
        let base = HireCatalog.roles[0]
        let harness = harness ?? base.harness
        return HireCatalog.Role(
            name: name, purpose: purpose, symbol: Self.symbol(icon), harness: harness,
            model: model ?? HireCatalog.models[harness]?.first?.wire ?? base.model,
            budget: budgetTokens ?? base.budget, instructions: instructions)
    }

    static func symbol(_ icon: String) -> String {
        NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil ? "person" : icon
    }
}

extension RoleInfo {
    init(_ role: Schemas.RoleOut) {
        self.init(
            id: role.id, name: role.name, purpose: role.purpose, icon: role.icon, skills: role.skills,
            instructions: role.instructions, harness: role.harness?.word, model: role.model,
            budgetTokens: role.budgetTokens)
    }

    var body: Schemas.RoleBody {
        Schemas.RoleBody(
            budgetTokens: budgetTokens, harness: harness.map { .init(value1: .init(rawValue: $0), value2: $0) },
            icon: icon, instructions: instructions, model: model, name: name, purpose: purpose, skills: skills)
    }
}
