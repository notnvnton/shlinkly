//
//  ShortURLFormView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The focusable text fields of the link form. File-scoped so the tag editor
/// subview can share the same `@FocusState` and the keyboard "Done" can clear
/// focus from any of them.
private enum ShortURLFormField: Hashable {
    case longURL, title, tag, slug, visitLimit
}

/// The create/edit short-URL form, presented as a sheet on both platforms, as
/// layout v3 draws it (`MacLinkSheet`, `PhoneLinkForm`).
///
/// One view, two modes (driven by ``ShortURLFormModel/Mode``): create starts
/// blank and offers a custom short code; edit pre-fills from the short URL and
/// shows the code read-only (it is immutable). Mac: one sheet with the fields,
/// Tags and Advanced cards. iPhone: labeled cards, with the advanced options one
/// level down behind "Advanced ›". The main button stays disabled until a
/// destination URL is entered.
struct ShortURLFormView: View {
    @State private var model: ShortURLFormModel
    private let tagsStore: TagsStore
    /// Called with the created/updated short URL so the presenter can update its
    /// store(s). The sheet dismisses itself on success.
    private let onComplete: (ShortURL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    /// Set after a successful *create* to swap the form for the success screen
    /// (edits dismiss straight away). `nil` while the form is showing.
    @State private var createdURL: ShortURL?
    /// Which text field holds focus, so the iOS keyboard's "Done" can dismiss it.
    @FocusState private var focusedField: ShortURLFormField?
    /// The tag being typed, shared by the tag field and its suggestions.
    @State private var tagDraft = ""

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

    var body: some View {
        if let createdURL {
            // After a create, the form gives way to the "Link created" screen.
            CreatedShortURLView(shortURL: createdURL) { dismiss() }
        } else {
            formBody
                .task { tagsStore.loadIfNeeded() }
        }
    }

    /// "New link" / "Edit link".
    private var title: String { model.isCreate ? "New link" : "Edit link" }
    /// "Create link" / "Save": the form's one main action.
    private var submitTitle: String { model.isCreate ? "Create link" : "Save" }

    #if os(macOS)
    // MARK: - Mac (MacLinkSheet)

    private var formBody: some View {
        @Bindable var model = model
        return MacSheet(title) {
            if let submissionError = model.submissionError {
                Footnote(submissionError, color: Palette.danger)
            }

            VStack(alignment: .leading, spacing: 0) {
                MacCard(solid: true) {
                    VStack(spacing: 0) {
                        macField("Long URL") {
                            TextField("Long URL", text: $model.longURL,
                                      prompt: Text("https://example.com/page").foregroundStyle(Palette.text2))
                                .focused($focusedField, equals: .longURL)
                                .multilineTextAlignment(.trailing)
                        }
                        RowSeparator()
                        macField("Title") {
                            TextField("Title", text: $model.title,
                                      prompt: Text("Optional title").foregroundStyle(Palette.text2))
                                .focused($focusedField, equals: .title)
                                .multilineTextAlignment(.trailing)
                        }
                        RowSeparator()
                        macField("Short code") {
                            shortCodeValue
                        }
                    }
                }
                if let slugError = model.slugError {
                    Footnote(slugError, color: Palette.danger)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                MacLabel("Tags")
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                MacCard(solid: true) {
                    TagsEditor(model: model, draft: $tagDraft, focused: $focusedField)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TagSuggestions(model: model, tagsStore: tagsStore, draft: $tagDraft)
            }

            VStack(alignment: .leading, spacing: 0) {
                MacLabel("Advanced")
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                MacCard(solid: true) {
                    VStack(spacing: 0) {
                        OptionalDateRow(title: "Active from", date: $model.validSince, defaultDate: Date())
                            .macField(height: 36)
                        RowSeparator()
                        OptionalDateRow(title: "Active until", date: $model.validUntil,
                                        defaultDate: Date().addingTimeInterval(7 * 24 * 60 * 60))
                            .macField(height: 36)
                        RowSeparator()
                        macField("Visit limit", height: 36) {
                            TextField("Visit limit", text: visitLimitText,
                                      prompt: Text("e.g. 100").foregroundStyle(Palette.text2))
                                .focused($focusedField, equals: .visitLimit)
                                .multilineTextAlignment(.trailing)
                        }
                        RowSeparator()
                        SwitchRow(title: "Allow in robots.txt", isOn: $model.crawlable,
                                  infoTitle: "Allow in robots.txt", infoMessage: Self.robotsHelp)
                            .macField(height: 36)
                        RowSeparator()
                        SwitchRow(title: "Forward UTM tags and parameters", isOn: $model.forwardQuery,
                                  infoTitle: "Parameter forwarding", infoMessage: Self.forwardQueryHelp)
                            .macField(height: 36)
                    }
                }
                if model.datesInvalid {
                    Footnote("“Active until” must be later than “Active from”.", color: Palette.danger)
                }
            }
        } bar: {
            Spacer(minLength: 8)
            if model.isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.mac)
                .keyboardShortcut(.cancelAction)
            Button(submitTitle) { submit() }
                .buttonStyle(.macPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmit || model.isSubmitting)
        }
        .frame(width: 500)
        .frame(minHeight: 420, idealHeight: 600)
    }

    /// A `.mfield`: the 96 pt label on the left, the value on the right.
    private func macField<Value: View>(_ label: String, height: CGFloat = 30,
                                       @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            FieldLabel(label)
            value()
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .macField(height: height)
    }

    /// Create: the server's host in `--text2`, then the custom code (110 pt,
    /// left-aligned). Edit: the short URL, read-only, with a copy button.
    @ViewBuilder
    private var shortCodeValue: some View {
        @Bindable var model = model
        if model.isCreate {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let slugPrefix {
                    Text("\(slugPrefix)/")
                        .foregroundStyle(Palette.text2)
                        .lineLimit(1)
                }
                TextField("Custom slug", text: $model.customSlug,
                          prompt: Text("custom-slug").foregroundStyle(Palette.text2))
                    .focused($focusedField, equals: .slug)
                    .multilineTextAlignment(.leading)
                    .frame(width: 110)
                    .onChange(of: model.customSlug) { _, _ in model.clearSlugError() }
            }
        } else {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(model.editingShortURL?.shortUrl ?? "")
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                CopyButton(value: model.editingShortURL?.shortUrl ?? "", label: "Copy short URL")
            }
        }
    }
    #endif

    #if os(iOS)
    // MARK: - iPhone (PhoneLinkForm)

    private var formBody: some View {
        @Bindable var model = model
        return NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.navLink())
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let submissionError = model.submissionError {
                            Footnote(submissionError, color: Palette.danger)
                        }

                        group("Long URL") {
                            LayoutCard {
                                TextField("Long URL", text: $model.longURL,
                                          prompt: Text("https://example.com/page").foregroundStyle(Palette.text2))
                                    .focused($focusedField, equals: .longURL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .layoutRow()
                            }
                        }

                        group("Title") {
                            LayoutCard {
                                TextField("Title", text: $model.title,
                                          prompt: Text("Optional title").foregroundStyle(Palette.text2))
                                    .focused($focusedField, equals: .title)
                                    .layoutRow()
                            }
                        }

                        group("Short code") {
                            LayoutCard {
                                phoneShortCode
                                    .layoutRow()
                            }
                            Footnote("Can't be changed after creation.")
                            if let slugError = model.slugError {
                                Footnote(slugError, color: Palette.danger)
                            }
                        }

                        group("Tags") {
                            LayoutCard {
                                TagsEditor(model: model, draft: $tagDraft, focused: $focusedField)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            TagSuggestions(model: model, tagsStore: tagsStore, draft: $tagDraft)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            LayoutCard {
                                NavigationLink {
                                    AdvancedOptionsPage(model: model, focused: $focusedField)
                                } label: {
                                    HStack {
                                        Text("Advanced")
                                        Spacer(minLength: 8)
                                        Text("›")
                                            .layoutFont(15)
                                            .foregroundStyle(Palette.text2)
                                    }
                                    .layoutRow()
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Footnote("Dates, UTM forwarding, robots.txt and a visit limit.")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                BottomBar {
                    Button(action: submit) {
                        Text(submitTitle)
                            .opacity(model.isSubmitting ? 0 : 1)
                            .overlay {
                                if model.isSubmitting {
                                    ProgressView()
                                        .tint(Palette.onBrand)
                                }
                            }
                    }
                    .buttonStyle(.layoutPrimary)
                    .disabled(!model.canSubmit || model.isSubmitting)
                }
            }
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                // Native keyboard-accessory "Done", shown only while a field is
                // focused (the glass capsule on iOS 26 is the system's).
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// A `.label` over its card.
    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(label)
            content()
        }
    }

    /// Create: the server's host in `--text2`, then the custom code. Edit: the
    /// short URL, read-only, with a copy button.
    @ViewBuilder
    private var phoneShortCode: some View {
        @Bindable var model = model
        if model.isCreate {
            HStack(spacing: 0) {
                if let slugPrefix {
                    Text("\(slugPrefix)/")
                        .foregroundStyle(Palette.text2)
                        .lineLimit(1)
                }
                TextField("Custom slug", text: $model.customSlug,
                          prompt: Text("custom-slug").foregroundStyle(Palette.text2))
                    .focused($focusedField, equals: .slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: model.customSlug) { _, _ in model.clearSlugError() }
            }
        } else {
            HStack(spacing: 8) {
                Text(model.editingShortURL?.shortUrl ?? "")
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                CopyButton(value: model.editingShortURL?.shortUrl ?? "", label: "Copy short URL", targetSide: 44)
            }
        }
    }
    #endif

    // MARK: - Helpers

    /// The visit limit as one field (Mac, as drawn): empty is unlimited, any
    /// digits set the cap. Keeps the model's "limits visits" flag in step.
    private var visitLimitText: Binding<String> {
        Binding(
            get: { model.limitsVisits ? model.maxVisitsText : "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                model.maxVisitsText = digits
                model.limitsVisits = !digits.isEmpty
            }
        )
    }

    /// The active server's host (e.g. `go.ahodge.de`) for the short-code prefix.
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

    // MARK: - Help texts

    /// The forwarding explanation shown in the info popover beside the switch.
    /// Markdown: `**bold**` and `` `code` `` render in the popover.
    fileprivate static let forwardQueryHelp = """
    What you add to a short link after **`?`**, usually **UTM tags**, is forwarded to the destination page when this is on.

    So **one link covers every channel**: `example.com/sale?utm_source=email` for email, `?utm_source=twitter` for social. Your analytics still sees the source.

    Off: visitors reach the same page, without the extra parameters.
    """

    /// Explanation shown in the info popover beside the visit limit.
    fileprivate static let visitLimitHelp = """
    Caps how many times this link can be opened. **Off = unlimited.**
    When the limit is reached, the link **stops redirecting** and visitors get a "not found" page (unless your server has a fallback redirect set). The link stays in your list; it isn't deleted.
    Handy for one-time links or limited campaigns.
    """

    /// Explanation shown in the info popover beside the robots.txt switch.
    fileprivate static let robotsHelp = """
    Controls whether search engines (Google, etc.) may crawl this short link.
    **Off (default):** crawlers are asked not to follow it. That keeps bots from inflating your visit stats and keeps the link out of search results.
    **On:** search engines may index and follow it.
    """
}

#if os(iOS)
// MARK: - Advanced (iPhone)

/// The iPhone's advanced options, one level below "Advanced ›" (not drawn; the
/// same controls as before, in the layout's cards and rows).
private struct AdvancedOptionsPage: View {
    @Bindable var model: ShortURLFormModel
    let focused: FocusState<ShortURLFormField?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Dates")
                    LayoutCard {
                        VStack(spacing: 0) {
                            OptionalDateRow(title: "Active from", date: $model.validSince, defaultDate: Date())
                                .layoutRow()
                            RowSeparator()
                            OptionalDateRow(title: "Active until", date: $model.validUntil,
                                            defaultDate: Date().addingTimeInterval(7 * 24 * 60 * 60))
                                .layoutRow()
                        }
                    }
                    if model.datesInvalid {
                        Footnote("“Active until” must be later than “Active from”.", color: Palette.danger)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Visit limit")
                    LayoutCard {
                        VStack(spacing: 0) {
                            SwitchRow(title: "Visit limit", isOn: $model.limitsVisits,
                                      infoTitle: "Visit limit", infoMessage: ShortURLFormView.visitLimitHelp)
                                .layoutRow()
                            if model.limitsVisits {
                                RowSeparator()
                                TextField("Visit limit", text: $model.maxVisitsText,
                                          prompt: Text("e.g. 100").foregroundStyle(Palette.text2))
                                    .focused(focused, equals: .visitLimit)
                                    .keyboardType(.numberPad)
                                    .onChange(of: model.maxVisitsText) { _, newValue in
                                        // Keep it a positive integer: strip anything non-numeric.
                                        let digits = newValue.filter(\.isNumber)
                                        if digits != newValue { model.maxVisitsText = digits }
                                    }
                                    .layoutRow()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Options")
                    LayoutCard {
                        VStack(spacing: 0) {
                            SwitchRow(title: "Allow in robots.txt", isOn: $model.crawlable,
                                      infoTitle: "Allow in robots.txt", infoMessage: ShortURLFormView.robotsHelp)
                                .layoutRow()
                            RowSeparator()
                            SwitchRow(title: "Forward UTM tags and parameters", isOn: $model.forwardQuery,
                                      infoTitle: "Parameter forwarding",
                                      infoMessage: ShortURLFormView.forwardQueryHelp)
                                .layoutRow()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .canvasBackground()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
#endif

// MARK: - Tags

/// The tag card: the current tags as "name ×" `.tag`s and an "Add a tag" field
/// (Return commits), 6 pt apart, wrapping.
private struct TagsEditor: View {
    let model: ShortURLFormModel
    @Binding var draft: String
    /// The host form's focus, so the tag entry shares the same `@FocusState` and
    /// the keyboard "Done" dismisses it like the other fields.
    let focused: FocusState<ShortURLFormField?>.Binding

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(model.tags, id: \.self) { tag in
                TagView(text: tag, size: Self.tagSize, onRemove: { model.removeTag(tag) })
            }
            TextField("Tag", text: $draft, prompt: Text("Add a tag").foregroundStyle(Palette.text2))
                .labelsHidden()
                .textFieldStyle(.plain)
                .layoutFont(Self.fieldSize)
                .foregroundStyle(Palette.text)
                .focused(focused, equals: .tag)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .onSubmit(commitDraft)
                .frame(minWidth: Self.fieldMinWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commitDraft() {
        model.addTag(draft)
        draft = ""
    }

    #if os(macOS)
    private static let tagSize: TagView.Size = .regular
    private static let fieldSize: CGFloat = 13
    private static let fieldMinWidth: CGFloat = 80
    #else
    private static let tagSize: TagView.Size = .large
    private static let fieldSize: CGFloat = 15
    private static let fieldMinWidth: CGFloat = 90
    #endif
}

/// One-tap suggestions from the shared tag cache while a tag is being typed
/// (not drawn; kept), as `.tag`s under the card.
private struct TagSuggestions: View {
    let model: ShortURLFormModel
    let tagsStore: TagsStore
    /// The tag field's current draft, shared with ``TagsEditor``.
    @Binding var draft: String

    var body: some View {
        let suggestions = tagsStore.suggestions(for: draft).filter { candidate in
            !model.tags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
        if !suggestions.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    TagView(text: "+ \(suggestion)", action: {
                        model.addTag(suggestion)
                        draft = ""
                    })
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Rows

/// A switch row: the label, an info "?" button, and a native switch tinted
/// `--switch-on` (small on the Mac). The "?" isn't drawn; it keeps the help.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    let infoTitle: String
    let infoMessage: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(Palette.text)
            InfoPopoverButton(title: infoTitle, message: infoMessage)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                #if os(macOS)
                .controlSize(.small)
                #endif
                .tint(Palette.switchOn)
        }
    }
}

/// A date that can be unset: "Not set" in `--text2` until chosen (as drawn);
/// choosing seeds `defaultDate` and shows a compact date picker with a clear
/// button.
private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    let defaultDate: Date

    var body: some View {
        HStack(spacing: 8) {
            FieldLabel(title)
            Spacer(minLength: 8)
            if date != nil {
                DatePicker(title, selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            } else {
                Button("Not set") {
                    date = defaultDate
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.text2)
                .accessibilityLabel("\(title), not set")
                .accessibilityHint("Sets a date")
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date ?? defaultDate },
            set: { date = $0 }
        )
    }
}

// MARK: - Preview

#if DEBUG
private struct LinkFormPreview: View {
    var body: some View {
        let client = ShlinkClient(baseURL: URL(string: "https://preview.invalid/rest/v3/")!, apiKey: "preview")
        ShortURLFormView(mode: .create, client: client, tagsStore: TagsStore(client: client)) { _ in }
            .environment(AppModel(spotlight: nil))
            .brandTint()
    }
}

#if os(macOS)
#Preview("MacLinkSheet light") {
    LinkFormPreview()
        .preferredColorScheme(.light)
}

#Preview("MacLinkSheet dark") {
    LinkFormPreview()
        .preferredColorScheme(.dark)
}
#else
#Preview("PhoneLinkForm light") {
    LinkFormPreview()
        .preferredColorScheme(.light)
        .previewAsSheet()
}

#Preview("PhoneLinkForm dark") {
    LinkFormPreview()
        .preferredColorScheme(.dark)
        .previewAsSheet()
}
#endif
#endif
