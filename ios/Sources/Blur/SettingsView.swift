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

                // Auto-blur-by-tag moved to its own home: the Tags tab (tap a
                // tag to browse it, swipe/long-press to blur the whole group).

                Section {
                    Toggle("Stack blasts", isOn: $library.stacksEnabled)
                    if library.stacksEnabled {
                        Stepper("At least \(library.stackMinCount) photos", value: $library.stackMinCount, in: 2...20)
                        Picker("Within", selection: $library.stackGapSeconds) {
                            Text("3 seconds").tag(3.0)
                            Text("10 seconds").tag(10.0)
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                        }
                    }
                } header: {
                    Text("Stacks")
                } footer: {
                    Text("Collapse blasts of similar shots (bursts + rapid runs) into one tile. Tap a stack to open it; touch and hold to blur or select the whole blast.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Face matching: \(Int(library.faceThreshold))")
                        Slider(value: $library.faceThreshold, in: 5...40, step: 1)
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("How close two faces must be to count as the same person. Lower = stricter (more separate people); higher = merges more. Tune after your library is read.")
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
