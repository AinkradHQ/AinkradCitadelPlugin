import Foundation
import Observation

/// Screen 10 Runners: each runner's state, harnesses and disk.
@MainActor
@Observable
final class RunnersPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
}
