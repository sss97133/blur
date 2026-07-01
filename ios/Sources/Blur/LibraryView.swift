// LibraryView.swift — the Library tab. Blur opens here, on your whole photo
// library, exactly like the Photos app opens to your library. The tag inspector
// and Show mode ride on top (the premium layer); the base feels native.

import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryEngine
    @State private var showSettings = false

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
                } else {
                    PhotoGrid(title: "Library", assetIDs: library.allPhotoIDs)
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
