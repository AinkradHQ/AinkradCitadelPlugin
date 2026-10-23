import AinkradAppKit
import SwiftUI
import XCTest

@testable import CitadelFeature

/// The modal forms (propose an agent, new budget, set a price, plan tier) shot on their own, as their panel shows
/// them; a tool like `SweepTests`, run only with AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR set.
@MainActor
final class SweepFormTests: XCTestCase {
    func testShootForms() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["AINKRAD_SWEEP_DIR"], let themes = env["AINKRAD_THEMES_DIR"] else {
            throw XCTSkip("set AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR to shoot the forms")
        }
        let glass = try SweepTests.glassSkin(themes: URL(fileURLWithPath: themes))
        SweepTests.registerHostFonts()
        let model = CompanyFixture.model()
        let store = CitadelStore(
            settings: SettingsStore(documents: MemoryDocs()), secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.model = model
        let forms: [(String, AnyView, CGFloat)] = [
            (
                "11-a-propose-agent",
                AnyView(ProposeAgentSheet(store: store, model: model, isPresented: .constant(true))), 560
            ),
            (
                "09-cost-new-budget", AnyView(NewBudgetForm(store: store, model: model, isPresented: .constant(true))),
                400
            ),
            ("09-cost-set-price", AnyView(SetPriceForm(store: store, isPresented: .constant(true))), 420),
        ]
        for (theme, skin) in [("neon", AinkradSkin.standard), ("glass", glass)] {
            for (name, form, height) in forms {
                let size = CGSize(width: 480, height: height)
                try LiveCapture.shoot(
                    form.padding(skin.size.s20)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .background(skin.color(skin.palette.background))
                        .ainkradSkin(skin)
                        .environment(
                            \.ainkradTypography, AinkradTypography(fontFamilyName: theme == "neon" ? "Exo 2" : nil)
                        )
                        .environment(\.colorScheme, .dark),
                    size: size,
                    to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(theme).png"))
            }
        }
    }
}
