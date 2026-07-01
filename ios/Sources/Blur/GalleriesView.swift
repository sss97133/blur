// GalleriesView.swift — the home screen: every gallery as a cover card.
//
// RE-SKIN of the capture app's TodayView. Instead of sync counters, this is a
// grid of the user's galleries (seeded from Apple's albums in v0). Tap a cover
// to open it in the focus view, where you can curate and enter Show mode.

import SwiftUI
import UIKit

struct GalleriesView: View {
    @EnvironmentObject private var library: LibraryEngine
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if library.authorizationDenied {
                    permissionPrompt
                } else if library.galleries.isEmpty {
                    if library.didCompleteInitialScan {
                        emptyState
                    } else {
                        ProgressView().controlSize(.large)
                    }
                } else {
                    grid
                }
            }
            .navigationTitle("Albums")
            .toolbar {
                if library.accessIsLimited {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            library.presentLimitedPicker()
                        } label: {
                            Label("Add Photos", systemImage: "plus")
                        }
                        .accessibilityLabel("Add more photos")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable { await library.rescan() }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(library.galleries) { gallery in
                    NavigationLink {
                        PhotoGrid(title: gallery.title, assetIDs: gallery.assetIDs)
                    } label: {
                        GalleryCard(gallery: gallery)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No albums yet",
            systemImage: "rectangle.stack",
            description: Text("Albums you create in Photos appear here. Your whole library is on the Library tab.")
        )
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

// ─── Gallery cover card ───────────────────────────────────────────────────────

private struct GalleryCard: View {
    let gallery: Gallery

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let cover = gallery.coverAssetID {
                    AssetThumbnail(assetIdentifier: cover, side: 160, cornerRadius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 160, height: 160)
                }
                if gallery.source == .clustered {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
            Text(gallery.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text("\(gallery.count) photo\(gallery.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gallery.title), \(gallery.count) photo\(gallery.count == 1 ? "" : "s")")
        .accessibilityAddTraits(.isButton)
    }
}
