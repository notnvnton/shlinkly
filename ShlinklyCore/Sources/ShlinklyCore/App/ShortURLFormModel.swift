import Foundation
import Observation

/// Backs the create/edit short-URL form: it owns the editable fields, the light
/// client-side validation, and the submit that hits ``ShlinkClient`` and maps
/// the result back to the UI.
///
/// One model serves both modes. In ``Mode/create`` the fields start blank (with
/// the API's own defaults: forwarding on, crawlable off); in ``Mode/edit(_:)``
/// they pre-fill from the existing short URL — including the validity window and
/// visit cap that reads nest under `meta`.
@MainActor
@Observable
public final class ShortURLFormModel {

    /// Which operation the form performs. Drives field visibility (the custom
    /// slug is create-only) and which request the submit builds.
    public enum Mode: Equatable {
        case create
        case edit(ShortURL)
    }

    // MARK: Editable fields (bound to the form)

    /// The destination. Required; a missing scheme is filled in on submit.
    public var longURL: String
    /// Optional title. Empty clears it on edit / omits it on create.
    public var title: String
    /// Tags to attach. Empty clears all tags on edit.
    public var tags: [String]
    /// Custom slug — create-only; ignored in edit mode.
    public var customSlug: String
    /// Lower validity bound, or `nil` for none.
    public var validSince: Date?
    /// Upper validity bound, or `nil` for none.
    public var validUntil: Date?
    /// Visit cap as entered text. Empty means no cap (∞).
    public var maxVisitsText: String
    /// Whether crawlers may follow the short URL.
    public var crawlable: Bool
    /// Whether the query string is forwarded to the destination on redirect.
    public var forwardQuery: Bool

    // MARK: Status

    /// True while a submit is in flight; disables the confirm button.
    public private(set) var isSubmitting = false
    /// Inline error shown under the slug field (the slug is already taken).
    public private(set) var slugError: String?
    /// A general submission error shown as a banner in the form.
    public private(set) var submissionError: String?

    // MARK: Dependencies

    private let mode: Mode
    private let client: ShlinkClient

    public init(mode: Mode, client: ShlinkClient) {
        self.mode = mode
        self.client = client
        switch mode {
        case .create:
            longURL = ""
            title = ""
            tags = []
            customSlug = ""
            validSince = nil
            validUntil = nil
            maxVisitsText = ""
            crawlable = false
            forwardQuery = true
        case .edit(let url):
            longURL = url.longUrl
            title = url.title ?? ""
            tags = url.tags
            customSlug = ""
            validSince = url.meta.validSince
            validUntil = url.meta.validUntil
            maxVisitsText = url.meta.maxVisits.map(String.init) ?? ""
            crawlable = url.crawlable
            forwardQuery = url.forwardQuery
        }
    }

    // MARK: - Derived state

    /// Whether the form is creating (vs editing) — drives create-only UI.
    public var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    /// The short URL being edited, for the read-only short-code block. `nil` in
    /// create mode.
    public var editingShortURL: ShortURL? {
        if case .edit(let url) = mode { return url }
        return nil
    }

    /// The destination with a scheme guaranteed: a value lacking `://` gets
    /// `https://` prepended (matching Shlink, which doesn't probe reachability).
    public var normalizedLongURL: String {
        let trimmed = longURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    }

    /// The visit cap parsed from ``maxVisitsText``: a positive integer, or `nil`
    /// (no cap) for empty / non-numeric / non-positive input.
    public var maxVisitsValue: Int? {
        let trimmed = maxVisitsText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// Soft client check: an end date, when set, must be after the start date.
    public var datesInvalid: Bool {
        if let since = validSince, let until = validUntil { return until <= since }
        return false
    }

    /// Whether the confirm button is enabled: a non-empty URL, a valid date
    /// window, and no submit already running.
    public var canSubmit: Bool {
        !longURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !datesInvalid
            && !isSubmitting
    }

    // MARK: - Tag editing

    /// Adds `raw` (trimmed) as a tag unless it's blank or a case-insensitive
    /// duplicate of one already present.
    public func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        else { return }
        tags.append(tag)
    }

    /// Removes a tag chip.
    public func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    /// Clears the inline slug error — call when the user edits the slug again.
    public func clearSlugError() {
        slugError = nil
    }

    // MARK: - Submit

    /// Sends the create/update request. Returns the resulting ``ShortURL`` on
    /// success; on failure it records either the inline ``slugError`` (slug
    /// taken) or a general ``submissionError`` and returns `nil`.
    public func submit() async -> ShortURL? {
        guard canSubmit else { return nil }
        slugError = nil
        submissionError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleValue = trimmedTitle.isEmpty ? nil : trimmedTitle

        do {
            switch mode {
            case .create:
                let slug = customSlug.trimmingCharacters(in: .whitespacesAndNewlines)
                let request = CreateShortURLRequest(
                    longUrl: normalizedLongURL,
                    title: titleValue,
                    tags: tags,
                    customSlug: slug.isEmpty ? nil : slug,
                    validSince: validSince,
                    validUntil: validUntil,
                    maxVisits: maxVisitsValue,
                    crawlable: crawlable,
                    forwardQuery: forwardQuery
                )
                return try await client.createShortURL(request)

            case .edit(let url):
                let request = EditShortURLRequest(
                    longUrl: normalizedLongURL,
                    title: titleValue,
                    tags: tags,
                    validSince: validSince,
                    validUntil: validUntil,
                    maxVisits: maxVisitsValue,
                    crawlable: crawlable,
                    forwardQuery: forwardQuery
                )
                return try await client.updateShortURL(shortCode: url.shortCode, domain: url.domain, request)
            }
        } catch ShlinkError.slugInUse {
            slugError = "This slug is already taken."
            return nil
        } catch {
            submissionError = ShlinkError.userFacingMessage(for: error)
            return nil
        }
    }
}
