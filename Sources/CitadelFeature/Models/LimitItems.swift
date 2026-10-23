import Foundation
import Observation

/// Screen 16 Limits: every scoped setting at this company, its overrides below and recent changes.
@MainActor
@Observable
final class LimitsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
}
