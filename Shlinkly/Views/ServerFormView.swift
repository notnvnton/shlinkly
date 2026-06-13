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
    /// Called after the green confirmation with the validated instance + key.
    private let onConnected: (ServerInstance, String) -> Void

    init(
        mode: ServerFormModel.Mode,
        existingKey: String = "",
        onConnected: @escaping (ServerInstance, String) -> Void
    ) {
        _model = State(initialValue: ServerFormModel(mode: mode, existingKey: existingKey))
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
            }

            Section("Server URL") {
                TextField("Server URL", text: $model.urlText, prompt: Text("https://shlink.example.com"))
                    .labelsHidden()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif
            }

            Section {
                SecretField(placeholder: "API key", text: $model.apiKey)
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
        }
        .navigationTitle(model.isEdit ? "Edit Server" : "Connect server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        #endif
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
            return "Stored only on this device. Add the server again on your other devices."
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
            onConnected(validated.instance, validated.apiKey)
        }
    }
}
