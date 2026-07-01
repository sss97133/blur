// LibraryView.swift — the Library tab. Blur opens here, on your whole photo
// library, exactly like the Photos app opens to your library. The tag inspector
// and Show mode ride on top (the premium layer); the base feels native.

import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryEngine
    @State private var showSettings = false
    @State private var searchText = ""

    /// Search filters the grid; empty = the whole library.
    private var results: [String] {
        searchText.isEmpty ? library.allPhotoIDs : library.search(searchText)
    }

    /// Subject autocompletions matching what's typed.
    private var suggestions: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return library.subjectFacets
            .filter { $0.label.lowercased().contains(q) }
            .prefix(6).map(\.label)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.authorizationDenied {
                    permissionPrompt
                } else if library.allPhotoIDs.isEmpty {
                    if library.didCompleteInitialScan {
                        ContentUnavailableView(
                            "No photos",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Photos you add to your library will appear here.")
                        )
                    } else {
                        ProgressView().controlSize(.large)
                    }
                } else if !searchText.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    PhotoGrid(title: searchText.isEmpty ? "Library" : "Results", assetIDs: results)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search your photos")
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { subject in
                    Label(subject, systemImage: "sparkle").searchCompletion(subject)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await library.rescan() }
        }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Photos access is off", systemImage: "lock")
        } description: {
            Text("Blur works entirely on this device — it needs to read your library to organize it. Enable it in Settings › Privacy & Security › Photos › Blur.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
            }
        }
    }
}
