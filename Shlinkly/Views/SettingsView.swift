//
//  SettingsView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The Settings sheet: manage servers (switch / edit / add / remove), tune the
/// delete-confirmation switches, and the About section. Presented as a sheet with
/// a Done button on both platforms.
///
/// Switching or editing the active server rebuilds the app's client; because the
/// sheet is hosted above that rebuild (in ``RootView``), it stays open and the
/// active checkmark just moves.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// The add/edit server form to present, or `nil`.
    @State private var formRoute: ServerFormRoute?
    /// The server awaiting remove confirmation.
    @State private var pendingRemoval: ServerInstance?

    private enum ServerFormRoute: Identifiable {
        case add
        case edit(ServerInstance)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let instance): return "edit-\(instance.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                serversSection
                deletionSection
                aboutSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 560)
            #endif
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $formRoute) { route in
                serverForm(route)
            }
            .alert(
                pendingRemoval.map { "Remove \($0.displayName)?" } ?? "Remove server?",
                isPresented: removalBinding,
                presenting: pendingRemoval
            ) { server in
                Button("Remove", role: .destructive) { appModel.removeInstance(server.id) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its API key will be removed from this device. The links on the server itself aren't affected.")
            }
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    // MARK: - Servers

    private var serversSection: some View {
        Section {
            ForEach(appModel.instanceStore.instances) { instance in
                ServerRow(
                    instance: instance,
                    isActive: instance.id == appModel.activeInstance?.id,
                    onSelect: { select(instance) },
                    onEdit: { formRoute = .edit(instance) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingRemoval = instance
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        formRoute = .edit(instance)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }

            Button {
                formRoute = .add
            } label: {
                Label("Add Server", systemImage: "plus")
            }
        } header: {
            Text("Servers")
        }
    }

    /// Tapping the active server edits it; tapping another switches to it.
    private func select(_ instance: ServerInstance) {
        if instance.id == appModel.activeInstance?.id {
            formRoute = .edit(instance)
        } else {
            appModel.selectInstance(instance.id)
        }
    }

    // MARK: - Deletion preferences

    private var deletionSection: some View {
        @Bindable var preferences = appModel.preferences
        return Section {
            Toggle("Confirm before deleting a link", isOn: $preferences.confirmBeforeDeletingOne)
            Toggle("Confirm before deleting several links", isOn: $preferences.confirmBeforeDeletingSeveral)
        } header: {
            Text("Deletion")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://ahodge.de")!) {
                aboutRow(title: "Website", systemImage: "globe")
            }
            Link(destination: URL(string: "https://github.com/notnvnton/shlinkly")!) {
                aboutRow(title: "Source code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shlinkly is open source. There's no Shlinkly cloud — your links and keys stay yours.")
                Text(versionString)
            }
        }
    }

    private func aboutRow(title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// `v{CFBundleShortVersionString}` from the app bundle.
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    // MARK: - Server form sheet

    @ViewBuilder
    private func serverForm(_ route: ServerFormRoute) -> some View {
        NavigationStack {
            switch route {
            case .add:
                ServerFormView(mode: .add) { instance, key in
                    // On a save failure this throws *before* dismissing, so the
                    // sheet stays open and the form shows the error.
                    try appModel.addInstance(instance, apiKey: key)
                    formRoute = nil
                }
                .toolbar { cancelFormButton }
            case .edit(let instance):
                ServerFormView(
                    mode: .edit(instance),
                    existingKey: appModel.instanceStore.apiKey(for: instance.id) ?? "",
                    onRemove: {
                        formRoute = nil
                        appModel.removeInstance(instance.id)
                    }
                ) { updated, key in
                    try appModel.updateInstance(updated, apiKey: key)
                    formRoute = nil
                }
                .toolbar { cancelFormButton }
            }
        }
    }

    @ToolbarContentBuilder
    private var cancelFormButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { formRoute = nil }
        }
    }
}

/// One server row: an active checkmark, the name + host, and a trailing info
/// button that opens the edit form. The row body itself selects (switch / edit).
private struct ServerRow: View {
    let instance: ServerInstance
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .opacity(isActive ? 1 : 0)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.displayName)
                            .foregroundStyle(.primary)
                        if instance.name?.isEmpty == false, let host = instance.baseURL.host {
                            Text(host)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if instance.keyStorage == .iCloud {
                        Image(systemName: "icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Key synced via iCloud")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(instance.displayName)")
        }
    }
}
