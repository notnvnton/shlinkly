//
//  SettingsView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// Settings, as layout v3 draws it: on the Mac its own window (`MacSettings`,
/// the `Settings` scene: app menu "Settings…", ⌘,), on the iPhone a sheet
/// (`PhoneSettings`). Manage servers (switch / edit / add / remove), the Dock
/// presence (Mac), the delete-confirmation switches, and About.
///
/// Switching or editing the active server rebuilds the app's client; Settings
/// is hosted above that rebuild, so it stays open and the active dot just moves.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    /// Whether Shlinkly lives in the menu bar only (no Dock icon). `false` (the
    /// default) → `.regular` (Dock + menu bar); `true` → `.accessory` (menu-bar
    /// only). ``AppDelegate`` reads this key early at launch (no Dock flicker),
    /// and ``MacWindowManager`` applies it when the main window closes.
    @AppStorage("macMenuBarOnly") private var macMenuBarOnly = false
    #endif

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
        content
            .sheet(item: $formRoute) { route in
                serverForm(route)
                    .brandTint()
            }
            .alert(
                pendingRemoval.map { "Remove \"\($0.displayName)\"?" } ?? "Remove server?",
                isPresented: removalBinding,
                presenting: pendingRemoval
            ) { server in
                Button(server.keyStorage == .iCloud ? "Remove from All Devices" : "Remove", role: .destructive) {
                    appModel.removeInstance(server.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { server in
                Text(server.keyStorage == .iCloud
                    ? "This server is synced via iCloud. If you remove it here, you'll be signed out on your other devices too."
                    : "This server is stored only on this device, so removing it won't affect your other devices.")
            }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// Tapping the active server edits it; tapping another switches to it.
    private func select(_ instance: ServerInstance) {
        if instance.id == appModel.activeInstance?.id {
            formRoute = .edit(instance)
        } else {
            appModel.selectInstance(instance.id)
        }
    }

    private var instances: [ServerInstance] { appModel.instanceStore.instances }

    /// The bundle's marketing version, e.g. "2.3".
    private var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static let sourceURL = URL(string: "https://github.com/notnvnton/shlinkly")!
    private static let aboutFootnote = "Shlinkly is open source. There's no Shlinkly cloud, so your links and keys stay yours."

    #if os(macOS)
    // MARK: - Mac (MacSettings)

    private var content: some View {
        @Bindable var preferences = appModel.preferences
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                group("Servers") {
                    MacCard {
                        VStack(spacing: 0) {
                            ForEach(instances) { instance in
                                macServerRow(instance)
                                if instance.id != instances.last?.id {
                                    RowSeparator()
                                }
                            }
                        }
                    }
                    Button("Add Server…") { formRoute = .add }
                        .buttonStyle(.macTint)
                        .padding(.top, 8)
                }

                group("Dock") {
                    MacCard {
                        macSwitchRow("Show in menu bar only", isOn: $macMenuBarOnly)
                    }
                    Footnote("When on, Shlinkly lives only in the menu bar, with no Dock icon.")
                }

                group("Deletion") {
                    MacCard {
                        VStack(spacing: 0) {
                            macSwitchRow("Confirm before deleting a link", isOn: $preferences.confirmBeforeDeletingOne)
                            RowSeparator()
                            macSwitchRow("Confirm before deleting several links",
                                         isOn: $preferences.confirmBeforeDeletingSeveral)
                        }
                    }
                }

                group("About") {
                    MacCard {
                        HStack(spacing: 12) {
                            Text(version.map { "Shlinkly \($0)" } ?? "Shlinkly")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Link("GitHub ↗", destination: Self.sourceURL)
                                .layoutFont(13)
                                .foregroundStyle(Palette.brand)
                        }
                        .macField(height: 40)
                    }
                    Footnote(Self.aboutFootnote)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 520)
        .frame(minHeight: 420, idealHeight: 508)
        .background { WindowBackdrop() }
    }

    /// An `.mlabel` (4 pt in, 6 pt above the card) over its content.
    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MacLabel(label)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            content()
        }
    }

    /// A server (48 pt): the active dot, name and host, an "iCloud" tag for a
    /// synced key, and Edit. Clicking the row switches to it (or edits the
    /// active one).
    private func macServerRow(_ instance: ServerInstance) -> some View {
        HStack(spacing: 12) {
            activeDot(instance)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.displayName)
                    .layoutFont(13, .medium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if instance.name?.isEmpty == false, let host = instance.baseURL.host {
                    Text(host)
                        .layoutFont(11)
                        .foregroundStyle(Palette.text2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if instance.keyStorage == .iCloud {
                TagView(text: "iCloud", size: .small)
                    .accessibilityLabel("Key synced via iCloud")
            }
            Button("Edit") { formRoute = .edit(instance) }
                .buttonStyle(MacButtonStyle(kind: .tint, minWidth: 56))
                .accessibilityLabel("Edit \(instance.displayName)")
        }
        .macField(height: 48)
        .contentShape(Rectangle())
        .onTapGesture { select(instance) }
        .accessibilityElement(children: .contain)
    }

    /// A 40 pt row with a small native switch tinted `--switch-on`.
    private func macSwitchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.switchOn)
        }
        .macField(height: 40)
    }
    #endif

    #if os(iOS)
    // MARK: - iPhone (PhoneSettings)

    private var content: some View {
        @Bindable var preferences = appModel.preferences
        return VStack(spacing: 0) {
            SheetHeader("Settings") {
                Button("Done") { dismiss() }
                    .buttonStyle(.navLink(.semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Servers")
                        LayoutCard {
                            VStack(spacing: 0) {
                                ForEach(instances) { instance in
                                    phoneServerRow(instance)
                                    RowSeparator()
                                }
                                Button {
                                    formRoute = .add
                                } label: {
                                    Text("Add server")
                                        .layoutFont(16, .medium)
                                        .foregroundStyle(Palette.brand)
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Deletion")
                        LayoutCard {
                            VStack(spacing: 0) {
                                phoneSwitchRow("Confirm before deleting a link",
                                               isOn: $preferences.confirmBeforeDeletingOne)
                                RowSeparator()
                                phoneSwitchRow("Confirm before deleting several",
                                               isOn: $preferences.confirmBeforeDeletingSeveral)
                                    .accessibilityLabel("Confirm before deleting several links")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("About")
                        LayoutCard {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Text("Version")
                                    Spacer(minLength: 8)
                                    Text(version ?? "")
                                        .layoutFont(15)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.text2)
                                }
                                .layoutRow()
                                RowSeparator()
                                Link(destination: Self.sourceURL) {
                                    HStack(spacing: 12) {
                                        Text("Source code on GitHub")
                                            .layoutFont(16, .medium)
                                            .foregroundStyle(Palette.brand)
                                        Spacer(minLength: 8)
                                        Text("↗")
                                            .layoutFont(15)
                                            .foregroundStyle(Palette.text2)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                        Footnote(Self.aboutFootnote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .canvasBackground()
    }

    /// A server (at least 60 pt): the active dot, name and host, an "iCloud"
    /// tag for a synced key, and "›". Tapping switches to it (or edits the
    /// active one); the context menu edits or removes it.
    private func phoneServerRow(_ instance: ServerInstance) -> some View {
        Button {
            select(instance)
        } label: {
            HStack(spacing: 12) {
                activeDot(instance)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.displayName)
                        .layoutFont(16, .medium)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if instance.name?.isEmpty == false, let host = instance.baseURL.host {
                        Text(host)
                            .layoutFont(13)
                            .foregroundStyle(Palette.text2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if instance.keyStorage == .iCloud {
                    TagView(text: "iCloud")
                        .accessibilityLabel("Key synced via iCloud")
                }
                Text("›")
                    .foregroundStyle(Palette.text2)
                    .accessibilityHidden(true)
            }
            .layoutRow(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                formRoute = .edit(instance)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingRemoval = instance
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// A `.row` with a native switch tinted `--switch-on`.
    private func phoneSwitchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .toggleStyle(.switch)
        .tint(Palette.switchOn)
        .layoutRow()
    }
    #endif

    /// The `--ok` dot marks the active server; other rows keep its space.
    @ViewBuilder
    private func activeDot(_ instance: ServerInstance) -> some View {
        if instance.id == appModel.activeInstance?.id {
            StatusDot()
                .accessibilityLabel("Active server")
        } else {
            Color.clear.frame(width: 7, height: 7)
        }
    }

    // MARK: - Server form sheet

    @ViewBuilder
    private func serverForm(_ route: ServerFormRoute) -> some View {
        NavigationStack {
            switch route {
            case .add:
                ServerFormView(mode: .add, presentedAsSheet: true) { instance, key in
                    // On a save failure this throws *before* dismissing, so the
                    // sheet stays open and the form shows the error.
                    try appModel.addInstance(instance, apiKey: key)
                    formRoute = nil
                }
            case .edit(let instance):
                ServerFormView(
                    mode: .edit(instance),
                    existingKey: appModel.instanceStore.apiKey(for: instance.id) ?? "",
                    presentedAsSheet: true,
                    onRemove: {
                        formRoute = nil
                        appModel.removeInstance(instance.id)
                    }
                ) { updated, key in
                    try appModel.updateInstance(updated, apiKey: key)
                    formRoute = nil
                }
            }
        }
    }
}

#if DEBUG
private struct SettingsPreview: View {
    var body: some View {
        SettingsView()
            .environment(AppModel(spotlight: nil))
            .brandTint()
    }
}

#if os(macOS)
#Preview("MacSettings light") {
    SettingsPreview()
        .preferredColorScheme(.light)
}

#Preview("MacSettings dark") {
    SettingsPreview()
        .preferredColorScheme(.dark)
}
#else
#Preview("PhoneSettings light") {
    SettingsPreview()
        .preferredColorScheme(.light)
        .previewAsSheet()
}

#Preview("PhoneSettings dark") {
    SettingsPreview()
        .preferredColorScheme(.dark)
        .previewAsSheet()
}
#endif
#endif
