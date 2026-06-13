//
//  ShortURLFormView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The create/edit short-URL form, presented as a sheet on both platforms.
///
/// One view, two modes (driven by ``ShortURLFormModel/Mode``): create starts
/// blank and shows a custom-slug field; edit pre-fills from the short URL and
/// replaces the slug with a read-only short-code block (the code is immutable).
/// The destination URL, title and tags are always visible; dates, the visit cap
/// and the two toggles live under a collapsed "Advanced" disclosure. The confirm
/// button stays disabled until a destination URL is entered.
struct ShortURLFormView: View {
    @State private var model: ShortURLFormModel
    private let tagsStore: TagsStore
    /// Called with the created/updated short URL so the presenter can update its
    /// store(s). The sheet dismisses itself on success.
    private let onComplete: (ShortURL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var advancedExpanded = false
    /// Set after a successful *create* to swap the form for the success screen
    /// (edits dismiss straight away). `nil` while the form is showing.
    @State private var createdURL: ShortURL?

    init(
        mode: ShortURLFormModel.Mode,
        client: ShlinkClient,
        tagsStore: TagsStore,
        initialLongURL: String? = nil,
        onComplete: @escaping (ShortURL) -> Void
    ) {
        _model = State(initialValue: ShortURLFormModel(mode: mode, client: client, initialLongURL: initialLongURL))
        self.tagsStore = tagsStore
        self.onComplete = onComplete
    }

    /// The forwarding explanation shown in the info popover beside the toggle.
    /// Markdown: `**bold**` and `` `code` `` render in the popover.
    private static let forwardQueryHelp = """
    What you add to a short link after **`?`** — usually **UTM tags** — is forwarded to the destination page when this is on.

    So **one link covers every channel**: `example.com/sale?utm_source=email` for email, `?utm_source=twitter` for social — your analytics still sees the source.

    Off: visitors reach the same page, without the extra parameters.
    """

    /// Explanation shown in the info popover beside the Visit limit toggle.
    private static let visitLimitHelp = """
    Caps how many times this link can be opened. **Off = unlimited.**
    When the limit is reached, the link **stops redirecting** — visitors get a "not found" page (unless your server has a fallback redirect set). The link stays in your list; it isn't deleted.
    Handy for one-time links or limited campaigns.
    """

    /// Explanation shown in the info popover beside the robots.txt toggle.
    private static let robotsHelp = """
    Controls whether search engines (Google, etc.) may crawl this short link.
    **Off (default):** crawlers are asked not to follow it — keeps bots from inflating your visit stats and keeps the link out of search results.
    **On:** search engines may index and follow it.
    """

    var body: some View {
        if let createdURL {
            // After a create, the form gives way to a focused success screen.
            CreatedShortURLView(shortURL: createdURL) { dismiss() }
        } else {
            formBody
        }
    }

    private var formBody: some View {
        @Bindable var model = model
        return NavigationStack {
            Form {
                if let submissionError = model.submissionError {
                    Section {
                        Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section("Long URL") {
                    // labelsHidden + in-field prompt so macOS doesn't render a
                    // left label column; the field is full width as on iOS.
                    TextField("Long URL", text: $model.longURL, prompt: Text("https://example.com/page"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        #endif
                }

                Section("Title") {
                    TextField("Title", text: $model.title, prompt: Text("Optional title"))
                        .labelsHidden()
                }

                Section("Tags") {
                    TagsField(model: model, tagsStore: tagsStore)
                }

                if model.isCreate {
                    slugSection
                } else {
                    shortCodeSection
                }

                advancedSection
            }
            .navigationTitle(model.isCreate ? "New Link" : "Edit Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task { tagsStore.loadIfNeeded() }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: - Sections

    /// Create-only: the custom slug, prefixed with the active server's host so
    /// it reads like the eventual short URL. The host is pulled from the config,
    /// never hardcoded. An inline error appears below if the slug is taken.
    private var slugSection: some View {
        @Bindable var model = model
        return Section {
            HStack(spacing: 1) {
                if let slugPrefix {
                    Text("\(slugPrefix)/")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField("Custom slug", text: $model.customSlug, prompt: Text("custom-slug"))
                    .labelsHidden()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onChange(of: model.customSlug) { _, _ in model.clearSlugError() }
            }
        } header: {
            Text("Custom slug")
        } footer: {
            if let slugError = model.slugError {
                Text(slugError).foregroundStyle(.red)
            }
        }
    }

    /// Edit-only: a read-only block showing the full short URL with a copy
    /// button, plus a note that the code can't change.
    private var shortCodeSection: some View {
        Section {
            HStack {
                Text(model.editingShortURL?.shortUrl ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                CopyButton(value: model.editingShortURL?.shortUrl ?? "", label: "Copy short URL")
            }
        } header: {
            Text("Short code")
        } footer: {
            Text("Can't be changed after creation (API limitation).")
        }
    }

    private var advancedSection: some View {
        @Bindable var model = model
        return Section {
            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                OptionalDateRow(title: "Active from", date: $model.validSince, defaultDate: Date())
                OptionalDateRow(
                    title: "Active until",
                    date: $model.validUntil,
                    defaultDate: Date().addingTimeInterval(7 * 24 * 60 * 60)
                )
                if model.datesInvalid {
                    Label("“Active until” must be later than “Active from”.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ToggleRowWithInfo(
                        title: "Visit limit",
                        isOn: $model.limitsVisits,
                        infoTitle: "Visit limit",
                        infoMessage: Self.visitLimitHelp
                    )
                    if model.limitsVisits {
                        TextField("Visit limit", text: $model.maxVisitsText, prompt: Text("e.g. 100"))
                            .labelsHidden()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: model.maxVisitsText) { _, newValue in
                                // Keep it a positive integer: strip anything non-numeric.
                                let digits = newValue.filter(\.isNumber)
                                if digits != newValue { model.maxVisitsText = digits }
                            }
                    }
                }

                ToggleRowWithInfo(
                    title: "Allow in robots.txt",
                    isOn: $model.crawlable,
                    infoTitle: "Allow in robots.txt",
                    infoMessage: Self.robotsHelp
                )

                ToggleRowWithInfo(
                    title: "Forward UTM tags & parameters",
                    isOn: $model.forwardQuery,
                    infoTitle: "Parameter forwarding",
                    infoMessage: Self.forwardQueryHelp
                )
            }
        } footer: {
            Text("Advanced options let you set dates, UTM tags, and a visit limit.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSubmitting {
                ProgressView()
            } else {
                Button(model.isCreate ? "Create" : "Done") { submit() }
                    .disabled(!model.canSubmit)
            }
        }
    }

    // MARK: - Helpers

    /// The active server's host (e.g. `go.ahodge.de`) for the slug prefix.
    /// Comes from the configured base URL, never hardcoded.
    private var slugPrefix: String? {
        appModel.activeInstance?.baseURL.host
    }

    private func submit() {
        Task {
            guard let result = await model.submit() else {
                // On failure the model surfaces the error inline; the sheet stays open.
                return
            }
            // Update the list behind the sheet either way.
            onComplete(result)
            if model.isCreate {
                // Copy the new short URL up front, then show the success screen.
                Clipboard.copy(result.shortUrl)
                createdURL = result
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Tag editor

/// Edits the form's tags: removable chips for the current tags, a text field to
/// add new ones (Return commits), and one-tap suggestions drawn from the shared
/// tag cache as the user types.
private struct TagsField: View {
    let model: ShortURLFormModel
    let tagsStore: TagsStore
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(model.tags, id: \.self) { tag in
                        RemovableTagChip(text: tag) { model.removeTag(tag) }
                    }
                }
            }

            TextField("Tag", text: $draft, prompt: Text("Add a tag"))
                .labelsHidden()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .onSubmit(commitDraft)

            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            model.addTag(suggestion)
                            draft = ""
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text(suggestion)
                            }
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Cached tags matching the draft, minus any already added.
    private var suggestions: [String] {
        tagsStore.suggestions(for: draft).filter { candidate in
            !model.tags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
    }

    private func commitDraft() {
        model.addTag(draft)
        draft = ""
    }
}

// MARK: - Toggle row with info

/// An advanced-options toggle row: a label, an info "?" button, and a trailing
/// switch. The label and the "?" share an HStack aligned to the last text
/// baseline, so when the label wraps to two lines the "?" sits beside the
/// bottom line rather than floating in the vertical centre.
private struct ToggleRowWithInfo: View {
    let title: String
    @Binding var isOn: Bool
    let infoTitle: String
    let infoMessage: String

    var body: some View {
        HStack {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(title)
                InfoPopoverButton(title: infoTitle, message: infoMessage)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

/// A tag chip with a trailing remove button, for the form's tag editor.
private struct RemovableTagChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(text)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.14), in: Capsule())
        .foregroundStyle(.secondary)
    }
}

// MARK: - Optional date row

/// A date field that can be unset: a toggle enables it, revealing a date picker.
/// Turning it off clears the bound optional; turning it on seeds `defaultDate`.
private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    let defaultDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabledBinding)
            if date != nil {
                DatePicker(title, selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { date != nil },
            set: { isOn in date = isOn ? (date ?? defaultDate) : nil }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date ?? defaultDate },
            set: { date = $0 }
        )
    }
}
