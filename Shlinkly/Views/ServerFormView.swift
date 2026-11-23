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
/// and reacts to ``onConnected`` by saving and dismissing/advancing. Laid out as
/// layout v3 draws it: `MacServerSheet` and `PhoneServerForm`.
struct ServerFormView: View {
    @State private var model: ServerFormModel
    /// Called after the green confirmation with the validated instance + key. It
    /// performs the actual save and may **throw** — saving the key to the
    /// Keychain can fail (notably on macOS without the Keychain Sharing
    /// capability), in which case the form stays put and shows the error.
    private let onConnected: (ServerInstance, String) throws -> Void
    /// When set (edit mode), a destructive "Remove Server…" / "Remove server"
    /// action is shown (the Mac's bottom bar, the iPhone's bottom); the host
    /// removes the instance and dismisses. Gives macOS — where Settings has no
    /// swipe — a way to delete a server, and works on iOS too.
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

    /// The API key how-to under the Server card (`MacServerSheet`,
    /// `PhoneServerForm`): the command in monospace, "unrestricted (admin)"
    /// semibold.
    private static var keyHelp: Text {
        Text("On your server, run \(Text("shlink api-key:generate").monospaced()) and copy the key. You can only see it once. Use an \(Text("unrestricted (admin)").fontWeight(.semibold)) key, or you'll only see part of your links.")
    }

    var body: some View {
        form
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

    /// "Edit Server" / "Connect Server" (Mac), "Edit server" / "Connect server"
    /// (iPhone), as the artboards case them.
    private var title: String {
        #if os(macOS)
        model.isEdit ? "Edit Server" : "Connect Server"
        #else
        model.isEdit ? "Edit server" : "Connect server"
        #endif
    }

    #if os(macOS)
    // MARK: - Mac (MacServerSheet)

    /// One card of label-left rows (Name, Server URL, API key), the Key storage
    /// row with its footnote, and the bottom bar: Remove Server… (edit only),
    /// Cancel (sheet only), Save / Connect.
    private var form: some View {
        @Bindable var model = model
        return MacSheet(title) {
            MacCard(solid: true) {
                VStack(spacing: 0) {
                    macField("Name") {
                        TextField("Name", text: $model.name, prompt: Text(""))
                            .focused($focusedField, equals: .name)
                            .macPlaceholder("My Shlink (optional)", isEmpty: model.name.isEmpty)
                    }
                    RowSeparator()
                    macField("Server URL") {
                        TextField("Server URL", text: $model.urlText, prompt: Text(""))
                            .focused($focusedField, equals: .url)
                            .macPlaceholder("https://shlink.example.com", isEmpty: model.urlText.isEmpty)
                    }
                    RowSeparator()
                    macField("API key") {
                        SecretField(placeholder: "API key", text: $model.apiKey, focus: $focusedField,
                                    focusValue: .key, alignment: .trailing, toggleSize: 12)
                    }
                }
            }
            // `MacServerSheet`: the how-to sits right under the card (the
            // artboard pulls it up 8 pt into the 14 pt gap).
            Footnote(Self.keyHelp)
                .padding(.top, -14)

            VStack(alignment: .leading, spacing: 0) {
                MacCard(solid: true) {
                    HStack(spacing: 8) {
                        Text("Key storage")
                            .layoutFont(13)
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 8)
                        MacSegmented("Key storage", selection: $model.keyStorage, options: [
                            .init(value: .local, label: "On this device"),
                            .init(value: .iCloud, label: "iCloud sync"),
                        ])
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(height: 44)
                }
                Footnote(storageCaption)
            }

            statusNote
        } bar: {
            if onRemove != nil {
                Button("Remove Server…") { showRemoveConfirm = true }
                    .buttonStyle(.macDanger)
            }
            Spacer(minLength: 8)
            if presentedAsSheet {
                Button("Cancel") { attemptClose() }
                    .buttonStyle(.mac)
                    .keyboardShortcut(.cancelAction)
            }
            submitButton
                .buttonStyle(.macPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A `.mfield`: the 96 pt label on the left, the value right-aligned.
    private func macField<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            FieldLabel(label)
            value()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .macField()
    }
    #endif

    #if os(iOS)
    // MARK: - iPhone (PhoneServerForm)

    /// The "Server" card (Name, URL, API key) with the key how-to, the Key
    /// storage control with its footnote, then Save / Connect and (edit only)
    /// "Remove server" at the bottom. As a sheet it draws its own title bar
    /// with Cancel; pushed from onboarding it keeps the back button.
    private var form: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            SheetHeader(title, inSheet: presentedAsSheet) {
                if presentedAsSheet {
                    Button("Cancel") { attemptClose() }
                        .buttonStyle(.navLink())
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Server")
                        LayoutCard {
                            VStack(spacing: 0) {
                                phoneField("Name") {
                                    TextField("Name", text: $model.name,
                                              prompt: Text("My Shlink (optional)").foregroundStyle(Palette.text2))
                                        .focused($focusedField, equals: .name)
                                }
                                RowSeparator()
                                phoneField("URL") {
                                    TextField("Server URL", text: $model.urlText,
                                              prompt: Text("https://shlink.example.com").foregroundStyle(Palette.text2))
                                        .focused($focusedField, equals: .url)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.URL)
                                }
                                RowSeparator()
                                phoneField("API key") {
                                    SecretField(placeholder: "API key", text: $model.apiKey,
                                                focus: $focusedField, focusValue: .key, toggleSize: 14)
                                }
                            }
                        }
                        Footnote(Self.keyHelp)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Key storage")
                        Picker("Key storage", selection: $model.keyStorage) {
                            Text("On this device").tag(KeyStorage.local)
                            Text("iCloud sync").tag(KeyStorage.iCloud)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Footnote(storageCaption)
                    }

                    statusNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            BottomBar(vertical: true, spacing: 6) {
                submitButton
                    .buttonStyle(.layoutPrimary)
                if onRemove != nil {
                    Button("Remove server") { showRemoveConfirm = true }
                        .buttonStyle(.layoutDangerText)
                }
            }
        }
        .canvasBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(presentedAsSheet ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
            }
            // Native keyboard-accessory "Done", shown only while a field is
            // focused. The glass capsule on iOS 26 is the system's styling of
            // keyboard toolbar items, not chrome we add.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
            }
        }
    }

    /// A `.field`: the 96 pt label, then the value. 48 pt, 16 pt text.
    private func phoneField<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 0) {
            FieldLabel(label)
            value()
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.text)
        }
        .layoutRow()
    }
    #endif

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

    /// The connection check's result (not drawn; kept): a footnote in `--ok`
    /// or `--danger`.
    @ViewBuilder
    private var statusNote: some View {
        if let error = model.errorMessage {
            Footnote(error, color: Palette.danger)
        } else if let success = model.successMessage {
            Footnote(success, color: Palette.ok)
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
/// The Edit Server sheet as Settings presents it. Nothing is saved.
private struct EditServerPreview: View {
    var body: some View {
        NavigationStack {
            ServerFormView(
                mode: .edit(ServerInstance(name: "Main Server", baseURL: URL(string: "https://go.example.com")!,
                                           keyStorage: .iCloud)),
                existingKey: "preview-api-key",
                presentedAsSheet: true,
                onRemove: {}
            ) { _, _ in }
        }
        .brandTint()
    }
}

#if os(macOS)
#Preview("MacServerSheet light") {
    EditServerPreview()
        .preferredColorScheme(.light)
}

#Preview("MacServerSheet dark") {
    EditServerPreview()
        .preferredColorScheme(.dark)
}
#else
#Preview("PhoneServerForm light") {
    EditServerPreview()
        .preferredColorScheme(.light)
        .previewAsSheet()
}

#Preview("PhoneServerForm dark") {
    EditServerPreview()
        .preferredColorScheme(.dark)
        .previewAsSheet()
}
#endif
#endif
