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
                        VStack(alignment: .leading) {
                            Text("At least \(library.stackMinCount) photos")
                            Slider(value: Binding(
                                get: { Double(library.stackMinCount) },
                                set: { library.stackMinCount = Int($0) }
                            ), in: 2...30, step: 1)
                        }
                        VStack(alignment: .leading) {
                            Text(library.stackGapSeconds < 60
                                 ? "Within \(Int(library.stackGapSeconds)) seconds"
                                 : "Within \(Int(library.stackGapSeconds / 60)) min \(Int(library.stackGapSeconds.truncatingRemainder(dividingBy: 60))) sec")
                            Slider(value: $library.stackGapSeconds, in: 1...300, step: 1)
                        }
                    }
                } header: {
                    Text("Stacks")
                } footer: {
                    Text("Collapse blasts of similar shots (bursts + rapid runs) into one tile. Tap a stack to open it; touch and hold to blur or select the whole blast.")
                }

                Section {
                    Picker("Analyze", selection: $library.indexIntensity) {
                        ForEach(IndexIntensity.allCases, id: \.self) { i in
                            Text(i.label).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    if library.indexing {
                        LabeledContent("Progress", value: "\(library.indexedCount)/\(library.allPhotoIDs.count)")
                    }
                } header: {
                    Text("Vision")
                } footer: {
                    Text("How hard Blur reads your photos on device. Gentle paces itself and backs off when the phone warms up; Fast is quicker but hotter; Off analyzes only when you tap “Read” in Tags. It runs below the app so scrolling stays smooth.")
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
