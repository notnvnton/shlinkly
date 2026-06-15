import Foundation
import Observation

/// Backs the connect/edit server form shared by onboarding and Settings.
///
/// Owns the four editable fields, runs the two-step validation
/// (``ConnectionValidator``) before anything is saved, and produces the
/// ``ServerInstance`` + key to persist on success. It performs no persistence
/// itself — the caller hands the result to ``AppModel``.
@MainActor
@Observable
public final class ServerFormModel {
    /// Whether the form adds a new server or edits an existing one.
    public enum Mode: Equatable {
        case add
        case edit(ServerInstance)
    }

    // MARK: Editable fields

    /// Optional display name.
    public var name: String
    /// The server root the user types (no `/rest/v3/`). Normalised on submit.
    public var urlText: String
    /// The API key, sent as `X-Api-Key`. Pre-filled (and shown as dots) on edit.
    public var apiKey: String
    /// Where the key is stored.
    public var keyStorage: KeyStorage

    // MARK: Status

    /// True while the network probe is in flight; disables submit.
    public private(set) var isValidating = false
    /// A red error shown when validation fails, or `nil`.
    public private(set) var errorMessage: String?
    /// The green "Connected — N links found" confirmation on success, or `nil`.
    public private(set) var successMessage: String?

    // MARK: Dependencies

    private let mode: Mode
    private let originalNormalizedURL: URL?
    private let originalKey: String
    private let urlSession: URLSession

    // Snapshot of the fields when the form opened, for the unsaved-changes guard.
    private let initialName: String
    private let initialURLText: String
    private let initialKey: String
    private let initialKeyStorage: KeyStorage

    /// - Parameters:
    ///   - mode: Add, or edit a specific instance.
    ///   - existingKey: The current key when editing (pre-fills the field), so an
    ///     unchanged URL+key can skip re-validation.
    ///   - urlSession: Injected for testing; defaults to `.shared`.
    public init(mode: Mode, existingKey: String = "", urlSession: URLSession = .shared) {
        self.mode = mode
        self.urlSession = urlSession

        // Resolve the opening values once, then seed both the live fields and the
        // initial snapshot `isDirty` compares against — assigning from locals so we
        // never read `self` before every stored property is initialised.
        let startName: String
        let startURLText: String
        let startKey: String
        let startKeyStorage: KeyStorage
        switch mode {
        case .add:
            startName = ""
            startURLText = ""
            startKey = ""
            startKeyStorage = .local
            originalNormalizedURL = nil
            originalKey = ""
        case .edit(let instance):
            startName = instance.name ?? ""
            startURLText = instance.baseURL.absoluteString
            startKey = existingKey
            startKeyStorage = instance.keyStorage
            originalNormalizedURL = instance.baseURL
            originalKey = existingKey
        }
        name = startName
        urlText = startURLText
        apiKey = startKey
        keyStorage = startKeyStorage
        initialName = startName
        initialURLText = startURLText
        initialKey = startKey
        initialKeyStorage = startKeyStorage
    }

    // MARK: Derived

    public var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The persisted key-storage of the server being edited (the value the form
    /// opened with), or `nil` in add mode. The removal warning reads this — the
    /// same `keyStorage` source the Settings list's iCloud badge uses — so the two
    /// always agree, even if the user changed the picker without saving.
    public var editingKeyStorage: KeyStorage? {
        isEdit ? initialKeyStorage : nil
    }

    /// Whether any editable field differs from its value when the form opened
    /// (Add: an empty form; Edit: the server's current values). Drives the
    /// guard against closing the form with unsaved edits. The Key storage mode is
    /// included deliberately — it, like every field, only takes effect on Save.
    public var isDirty: Bool {
        name != initialName
            || urlText != initialURLText
            || apiKey != initialKey
            || keyStorage != initialKeyStorage
    }

    /// Submit is enabled once a URL and a key are present and no probe is running.
    public var canSubmit: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isValidating
    }

    // MARK: Validation

    /// Validates the current input and, on success, returns the instance + key
    /// the caller should persist (and sets ``successMessage``). On failure it sets
    /// ``errorMessage`` and returns `nil`. When editing with an unchanged URL and
    /// key, the network probe is skipped — only the name/storage are being saved.
    public func validate() async -> (instance: ServerInstance, apiKey: String)? {
        errorMessage = nil
        successMessage = nil

        guard let serverRoot = ServerURLNormalizer.normalize(urlText) else {
            errorMessage = Self.unreachableMessage
            return nil
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Editing without touching the URL or key only changes name/storage, so
        // there's nothing to re-probe.
        let urlUnchanged = serverRoot == originalNormalizedURL
        let keyUnchanged = key == originalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEdit && urlUnchanged && keyUnchanged {
            return (makeInstance(serverRoot: serverRoot), key)
        }

        isValidating = true
        defer { isValidating = false }

        switch await ConnectionValidator.validate(serverRoot: serverRoot, apiKey: key, urlSession: urlSession) {
        case .connected(let count):
            successMessage = Self.connectedMessage(linkCount: count)
            return (makeInstance(serverRoot: serverRoot), key)
        case .unreachable:
            errorMessage = Self.unreachableMessage
        case .notShlink:
            errorMessage = "That doesn't look like a Shlink server."
        case .invalidKey:
            errorMessage = "This API key was rejected. Generate an admin key and try again."
        case .failed(let message):
            errorMessage = message
        }
        return nil
    }

    /// Surfaces a failure that happened *after* a successful probe — saving the
    /// validated server to the Keychain failed. Replaces the green confirmation
    /// with a red error so the user stays on the form instead of advancing.
    public func reportSaveFailure(_ message: String) {
        successMessage = nil
        errorMessage = message
    }

    // MARK: Helpers

    private static let unreachableMessage =
        "Couldn't reach this server. Check the URL and your connection."

    static func connectedMessage(linkCount: Int) -> String {
        let noun = linkCount == 1 ? "link" : "links"
        return "Connected — \(linkCount) \(noun) found"
    }

    private func makeInstance(serverRoot: URL) -> ServerInstance {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? nil : trimmed
        switch mode {
        case .add:
            return ServerInstance(name: resolvedName, baseURL: serverRoot, keyStorage: keyStorage)
        case .edit(let instance):
            return ServerInstance(id: instance.id, name: resolvedName, baseURL: serverRoot, keyStorage: keyStorage)
        }
    }
}
