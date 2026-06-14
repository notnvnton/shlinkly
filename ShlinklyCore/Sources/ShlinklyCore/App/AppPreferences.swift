import Foundation
import Observation

/// User-facing app preferences that aren't tied to a specific server. Backed by
/// `UserDefaults`; each property writes through on change.
///
/// Currently the two delete-confirmation switches. Both default to **on** — the
/// safe choice — which means treating an unset key as `true` rather than letting
/// `UserDefaults`'s `false`-for-missing fool us.
@MainActor
@Observable
public final class AppPreferences {
    /// Ask before deleting a single link.
    public var confirmBeforeDeletingOne: Bool {
        didSet { defaults.set(confirmBeforeDeletingOne, forKey: Self.oneKey) }
    }
    /// Ask before deleting several links at once.
    public var confirmBeforeDeletingSeveral: Bool {
        didSet { defaults.set(confirmBeforeDeletingSeveral, forKey: Self.severalKey) }
    }

    private let defaults: UserDefaults
    private static let oneKey = "shlinkly.confirmDeleteOne"
    private static let severalKey = "shlinkly.confirmDeleteSeveral"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.confirmBeforeDeletingOne = Self.boolDefaultingTrue(defaults, Self.oneKey)
        self.confirmBeforeDeletingSeveral = Self.boolDefaultingTrue(defaults, Self.severalKey)
    }

    /// Reads a `Bool` that defaults to `true` when the key has never been set.
    private static func boolDefaultingTrue(_ defaults: UserDefaults, _ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
