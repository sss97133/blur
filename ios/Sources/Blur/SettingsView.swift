// SettingsView.swift — about, the privacy promise, and the upgrade teaser.
//
// v0 has no account and no purchases — the upgrade row is a teaser only. When
// the paid "automatic image handling" phase ships, this is where the StoreKit
// paywall and (once accounts exist) sign-in + account deletion (App Store
// 5.1.1(v)) live.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Automatic organization", value: "Coming soon")
                } footer: {
                    Text("Let Blur organize for you, powered by AI you bring. Optional — free stays free and anonymous.")
                }

                Section {
                    LabeledContent("Galleries", value: "\(library.galleries.count)")
                    LabeledContent("Hidden photos", value: "\(library.hiddenAssetIDs.count)")
                    if let scan = library.lastScan {
                        LabeledContent("Last scan",
                                       value: "\(scan.photos) photos · \(scan.userAlbums) albums")
                    }
                } header: {
                    Text("On this device")
                } footer: {
                    Text("Everything Blur does happens on your phone. Your photos and your choices never leave this device.")
                }

                Section("About") {
                    LabeledContent("App", value: Config.appName)
                    Text("A Nuke product.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
