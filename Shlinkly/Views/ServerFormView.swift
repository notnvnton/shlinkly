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
/// It owns no persistence and no navigation chrome: a host wraps it in a
/// `NavigationStack` (Settings adds a Cancel button; onboarding pushes it) and
/// reacts to ``onConnected`` by saving and dismissing/advancing.
struct ServerFormView: View {
    @State private var model: ServerFormModel
    /// Called after the green confirmation with the validated instance + key. It
    /// performs the actual save and may **throw** — saving the key to the
    /// Keychain can fail (notably on macOS without the Keychain Sharing
    /// capability), in which case the form stays put and shows the error.
    private let onConnected: (ServerInstance, String) throws -> Void
    /// When set (edit mode), a destructive "Remove Server" button is shown; the
    /// host removes the instance and dismisses. Gives macOS — where Settings has
    /// no swipe — a way to delete a server, and works on iOS too.
    private let onRemove: (() -> Void)?

    @State private var showRemoveConfirm = false
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
        onRemove: (() -> Void)? = nil,
        onConnected: @escaping (ServerInstance, String) throws -> Void
    ) {
        _model = State(initialValue: ServerFormModel(mode: mode, existingKey: existingKey))
        self.onRemove = onRemove
        self.onConnected = onConnected
    }

    /// Verbatim "?" popover beside the API key field. Markdown: `code` and
    /// **bold** render; the line break is preserved.
    private static let keyHelp = """
    On your server, run `shlink api-key:generate` and copy the key — you can only see it once.
    Use an **unrestricted (admin)** key, or you'll only see part of your links.
    """

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Name") {
                // labelsHidden + an in-field prompt so macOS doesn't render a
                // left label column (the section header is the title). The field
                // spans full width with the placeholder inside, matching iOS.
                TextField("Name", text: $model.name, prompt: Text("My Shlink (optional)"))
                    .labelsHidden()
                    .focused($focusedField, equals: .name)
            }

            Section("Server URL") {
                TextField("Server URL", text: $model.urlText, prompt: Text("https://shlink.example.com"))
                    .labelsHidden()
                    .focused($focusedField, equals: .url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif
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
                Picker("Key storage", selection: $model.keyStorage) {
                    Text("On this device").tag(KeyStorage.local)
                    Text("iCloud sync").tag(KeyStorage.iCloud)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Key storage")
            } footer: {
                Text(storageCaption)
            }

            submitSection

            if onRemove != nil {
                removeSection
            }
        }
        .navigationTitle(model.isEdit ? "Edit Server" : "Connect server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .alert("Remove \(displayName)?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) { onRemove?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its API key will be removed from this device. The links on the server itself aren't affected.")
        }
        .alert("Couldn't save the server", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
    }

    /// Drives the save-failure alert; clears the message when dismissed.
    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
    }

    /// Edit-only destructive action to delete this server (no swipe needed).
    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Remove Server")
                    Spacer()
                }
            }
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

    // MARK: - Submit

    private var submitSection: some View {
        Section {
            Button(action: submit) {
                HStack {
                    Spacer()
                    if model.isValidating {
                        ProgressView()
                    } else {
                        Text(model.isEdit ? "Save" : "Connect")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
            #if os(macOS)
            .controlSize(.large)
            #endif
        } footer: {
            statusFooter
        }
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
            return "Stored only on this device — it won't sync. Add this server separately on each of your devices."
        case .iCloud:
            return "Synced across your devices via iCloud Keychain — end-to-end encrypted by Apple. We never see it."
        }
    }

    private func submit() {
        Task {
            guard let validated = await model.validate() else { return }
            // Let the green "Connected — N links found" line register before the
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
