//
//  ServerFormView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The connect/edit server form, shared by onboarding (add) and Settings
/// (add/edit). Collects name, URL, API key and key-storage choice, validates the
/// connection before saving (health + an authorized probe), and only on success
/// hands the validated instance back to the host via ``onConnected``.
///
/// It owns no persistence and no navigation: a host wraps it in a
/// `NavigationStack` (Settings presents it as a sheet; onboarding pushes it)
/// and reacts to ``onConnected`` by saving and dismissing/advancing. Its
/// actions follow each platform: one bottom bar on the Mac (Remove Server…,
/// Cancel, Save), the navigation bar on the iPhone.
struct ServerFormView: View {
    @State private var model: ServerFormModel
    /// Called after the green confirmation with the validated instance + key. It
    /// performs the actual save and may **throw** — saving the key to the
    /// Keychain can fail (notably on macOS without the Keychain Sharing
    /// capability), in which case the form stays put and shows the error.
    private let onConnected: (ServerInstance, String) throws -> Void
    /// When set (edit mode), a destructive "Remove Server" action is shown (the
    /// Mac's bottom bar, the iPhone's last row); the host removes the instance
    /// and dismisses. Gives macOS — where Settings has no swipe — a way to
    /// delete a server, and works on iOS too.
    private let onRemove: (() -> Void)?

    /// True when the form is presented modally (the Settings sheet): the form then
    /// owns its Cancel button and guards against discarding unsaved edits.
    /// Onboarding pushes the form instead and leaves this off — the nav back
    /// button stays the way out and there's nothing yet to lose.
    private let presentedAsSheet: Bool

    /// Dismisses the form when it's a sheet (Settings). Unused in the pushed
    /// onboarding flow, where the nav back button handles it.
    @Environment(\.dismiss) private var dismiss

    @State private var showRemoveConfirm = false
    /// Drives the "You have unsaved changes" confirmation before a dirty close.
    @State private var showDiscardConfirm = false
    /// The Keychain-save failure to show in an alert, or `nil`. Set when
    /// ``onConnected`` throws so the user sees *why* connecting didn't complete.
    @State private var saveErrorMessage: String?

    /// Which text field holds focus, so the iOS keyboard's "Done" can dismiss it.
    /// Present on both platforms (focus is cross-platform); only the keyboard
    /// toolbar that clears it is iOS-only, so macOS layout is unaffected.
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, url, key }

    init(
        mode: ServerFormModel.Mode,
        existingKey: String = "",
        presentedAsSheet: Bool = false,
        onRemove: (() -> Void)? = nil,
        onConnected: @escaping (ServerInstance, String) throws -> Void
    ) {
        _model = State(initialValue: ServerFormModel(mode: mode, existingKey: existingKey))
        self.presentedAsSheet = presentedAsSheet
        self.onRemove = onRemove
        self.onConnected = onConnected
    }

    /// Verbatim "?" popover beside the API key field. Markdown: `code` and
    /// **bold** render; the line break is preserved.
    private static let keyHelp = """
    On your server, run `shlink api-key:generate` and copy the key. You can only see it once.
    Use an **unrestricted (admin)** key, or you'll only see part of your links.
    """

    var body: some View {
        form
            .navigationTitle(model.isEdit ? "Edit Server" : "Connect server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { iOSToolbar }
            #else
            // The system Settings look: grouped rows, label left, control right.
            // The actions live in one bottom bar, never inside a section.
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) { macActionBar }
            .frame(minWidth: 460, minHeight: 420)
            #endif
            // Block the silent interactive dismiss (iOS swipe-down; macOS click-away)
            // while edits are pending, so changes can't be lost without a choice.
            .interactiveDismissDisabled(presentedAsSheet && model.isDirty)
            .alert("You have unsaved changes", isPresented: $showDiscardConfirm) {
                Button("Don't Save", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Remove \"\(displayName)\"?", isPresented: $showRemoveConfirm) {
                Button(model.editingKeyStorage == .iCloud ? "Remove from All Devices" : "Remove", role: .destructive) {
                    onRemove?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(model.editingKeyStorage == .iCloud
                    ? "This server is synced via iCloud. If you remove it here, you'll be signed out on your other devices too."
                    : "This server is stored only on this device, so removing it won't affect your other devices.")
            }
            .alert("Couldn't save the server", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                if let saveErrorMessage {
                    Text(saveErrorMessage)
                }
            }
    }

    // MARK: - Fields

    @ViewBuilder
    private var form: some View {
        @Bindable var model = model
        Form {
            #if os(macOS)
            // One section of related fields, each a labelled row.
            Section("Server") {
                TextField("Name", text: $model.name, prompt: Text("My Shlink (optional)"))
                    .focused($focusedField, equals: .name)
                TextField("Server URL", text: $model.urlText, prompt: Text("https://shlink.example.com"))
                    .focused($focusedField, equals: .url)
                LabeledContent {
                    SecretField(placeholder: "API key", text: $model.apiKey, focus: $focusedField, focusValue: .key)
                } label: {
                    HStack(spacing: 6) {
                        Text("API key")
                        InfoPopoverButton(title: "Where do I get a key?", message: Self.keyHelp)
                    }
                }
            }

            Section {
                keyStoragePicker
            } footer: {
                Text(storageCaption)
            }
            #else
            Section("Name") {
                // labelsHidden + an in-field prompt: the section header is the
                // title, the field spans the row.
                TextField("Name", text: $model.name, prompt: Text("My Shlink (optional)"))
                    .labelsHidden()
                    .focused($focusedField, equals: .name)
            }

            Section("Server URL") {
                TextField("Server URL", text: $model.urlText, prompt: Text("https://shlink.example.com"))
                    .labelsHidden()
                    .focused($focusedField, equals: .url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            Section {
                SecretField(placeholder: "API key", text: $model.apiKey, focus: $focusedField, focusValue: .key)
            } header: {
                HStack(spacing: 6) {
                    Text("API key")
                    InfoPopoverButton(title: "Where do I get a key?", message: Self.keyHelp)
                }
            }

            Section {
                keyStoragePicker
                    .labelsHidden()
            } header: {
                Text("Key storage")
            } footer: {
                Text(storageCaption)
            }

            if hasStatus {
                Section {
                    EmptyView()
                } footer: {
                    statusFooter
                }
            }

            // The iOS convention: a destructive row in its own last section.
            if onRemove != nil {
                Section {
                    Button("Remove Server", role: .destructive) {
                        showRemoveConfirm = true
                    }
                }
            }
            #endif
        }
    }

    /// The native segmented key-storage control, in brand color.
    private var keyStoragePicker: some View {
        Picker("Key storage", selection: $model.keyStorage) {
            Text("On this device").tag(KeyStorage.local)
            Text("iCloud sync").tag(KeyStorage.iCloud)
        }
        .pickerStyle(.segmented)
        .brandSegmented()
    }

    // MARK: - Actions

    /// Save (edit) or Connect (add). Disabled until the form can be submitted;
    /// while the connection is being checked the title stays in the layout
    /// (hidden) with a small spinner over it, so the button never resizes.
    private var submitButton: some View {
        Button(action: submit) {
            Text(model.isEdit ? "Save" : "Connect")
                .opacity(model.isValidating ? 0 : 1)
                .overlay {
                    if model.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .disabled(!model.canSubmit)
    }

    #if os(macOS)
    /// The sheet's one bottom bar, under a hairline: Remove Server… on the
    /// leading side (edit only, system red), Cancel (sheet only) and Save /
    /// Connect on the trailing side. The validation status sits above it.
    private var macActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: Space.tight) {
                if hasStatus {
                    statusFooter
                }
                HStack(spacing: Space.tight) {
                    if onRemove != nil {
                        Button(role: .destructive) {
                            showRemoveConfirm = true
                        } label: {
                            // Red set explicitly: the root brand tint must not
                            // turn a destructive action lavender.
                            Text("Remove Server…")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    Spacer(minLength: Space.tight)
                    if presentedAsSheet {
                        Button("Cancel") { attemptClose() }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction)
                    }
                    submitButton
                        .nativeProminentButtonStyle()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }
    #endif

    #if os(iOS)
    @ToolbarContentBuilder
    private var iOSToolbar: some ToolbarContent {
        // The form owns its Cancel when presented modally (Settings), so the
        // close routes through the unsaved-changes guard. Onboarding pushes the
        // form; the back button is the way out there.
        if presentedAsSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { attemptClose() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            submitButton
                .fontWeight(.semibold)
                .tint(Palette.accent)
        }
        // Native keyboard-accessory "Done": a plain text button pushed to the
        // trailing edge by a Spacer, shown only while a field is focused. No
        // custom background/buttonStyle/tint — the glass capsule seen on iOS 26
        // is the system Liquid Glass styling applied to keyboard toolbar items
        // themselves, not chrome we add (and .buttonStyle(.plain) is
        // unavailable on iOS 26, so it can't be flattened that way).
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
                .fontWeight(.semibold)
        }
    }
    #endif

    /// Drives the save-failure alert; clears the message when dismissed.
    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
    }

    /// Cancel/close intent. With unsaved edits it asks first (via the discard
    /// confirmation); otherwise it closes straight away, as before.
    private func attemptClose() {
        if model.isDirty {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    /// A label for the remove confirmation: the entered name, else the URL host.
    private var displayName: String {
        let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let url = ServerURLNormalizer.normalize(model.urlText), let host = url.host {
            return host
        }
        return "this server"
    }

    // MARK: - Status

    /// Whether there is a validation result (error or confirmation) to show.
    private var hasStatus: Bool {
        model.errorMessage != nil || model.successMessage != nil
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        } else if let success = model.successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        }
    }

    private var storageCaption: String {
        switch model.keyStorage {
        case .local:
            return "Stored only on this device. It won't sync, so add this server separately on each of your devices."
        case .iCloud:
            return "Synced across your devices with iCloud Keychain, end-to-end encrypted by Apple. We never see it."
        }
    }

    private func submit() {
        Task {
            guard let validated = await model.validate() else { return }
            // Let the green "Connected. N links found." line register before the
            // host swaps the screen (onboarding → list) or closes the sheet.
            try? await Task.sleep(for: .seconds(0.5))
            do {
                // Only the host's save can advance the flow. If it throws (the key
                // didn't reach the Keychain), stay on the form and show why.
                try onConnected(validated.instance, validated.apiKey)
            } catch let error as KeychainError {
                surfaceSaveFailure(error.message)
            } catch {
                surfaceSaveFailure("Couldn't save the API key. The server wasn't added.")
            }
        }
    }

    /// Replaces the green confirmation with a visible failure (red footer + an
    /// alert) and keeps the user on the form — the host only advances on success.
    private func surfaceSaveFailure(_ message: String) {
        model.reportSaveFailure(message)
        saveErrorMessage = message
    }
}

// MARK: - Preview

#if DEBUG
/// The Edit Server sheet as Settings presents it: on the Mac with its bottom
/// bar (Remove Server…, Cancel, Save), on the iPhone with Cancel / Save in the
/// navigation bar and Remove Server as the last row. Nothing is saved.
private struct EditServerPreview: View {
    var body: some View {
        NavigationStack {
            ServerFormView(
                mode: .edit(ServerInstance(name: "Home", baseURL: URL(string: "https://go.example.com")!,
                                           keyStorage: .iCloud)),
                existingKey: "preview-api-key",
                presentedAsSheet: true,
                onRemove: {}
            ) { _, _ in }
        }
        .brandTint()
    }
}

#Preview("Edit Server, light") {
    EditServerPreview()
        .preferredColorScheme(.light)
}

#Preview("Edit Server, dark") {
    EditServerPreview()
        .preferredColorScheme(.dark)
}
#endif
