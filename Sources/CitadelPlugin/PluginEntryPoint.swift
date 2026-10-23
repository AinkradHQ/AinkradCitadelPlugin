import AinkradAppKit
import Foundation
import CitadelFeature

/// The bundle's principal class (matches `NSPrincipalClass` in Info.plist).
@objc(CitadelPluginEntryPoint)
final class CitadelPluginEntryPoint: NSObject, AinkradPluginEntryPoint {
    static func app() -> any AinkradApp.Type { CitadelApp.self }
}
