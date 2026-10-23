import Foundation
import Observation

/// Screen 15 Accounts: the provider account pool, usage windows and fallback chains.
@MainActor
@Observable
final class AccountsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
}
