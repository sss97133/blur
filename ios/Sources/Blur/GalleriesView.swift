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

    // Pinch-to-zoom column count (matches the photo grid). Default 3 — denser
    // than the old adaptive 2-per-row.
    @State private var columns = 3
    @GestureState private var pinch: CGFloat = 1
    private let minColumns = 2
    private let maxColumns = 5
    private let spacing: CGFloat = 12

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
        GeometryReader { geo in
            let tile = (geo.size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns)
            let cols = Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: columns)
            ScrollView {
                LazyVGrid(columns: cols, spacing: spacing) {
                    ForEach(library.galleries) { gallery in
                        NavigationLink {
                            PhotoGrid(title: gallery.title, assetIDs: gallery.assetIDs)
                        } label: {
                            GalleryCard(gallery: gallery, side: tile)
                        }
                        .buttonStyle(.plain)
                        // The "right click": hold an album for its actions. Blur
                        // is a toggle here — one of its many access points.
                        .contextMenu {
                            let on = library.isCategoryBlurred(gallery.id)
                            Button {
                                library.setCategoryBlur(gallery.id, !on)
                            } label: {
                                Label(on ? "Unblur album" : "Blur album",
                                      systemImage: on ? "eye" : "eye.slash")
                            }
                        }
                    }
                }
                .padding(spacing)
                .scaleEffect(min(max(pinch, 0.6), 1.7), anchor: .center)
            }
            .scrollDisabled(pinch != 1)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        let next: Int
                        if value.magnification > 1.15 { next = max(minColumns, columns - 1) }
                        else if value.magnification < 0.87 { next = min(maxColumns, columns + 1) }
                        else { next = columns }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { columns = next }
                    }
            )
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
    var side: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let cover = gallery.coverAssetID {
                    AssetThumbnail(assetIdentifier: cover, side: side, cornerRadius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: side, height: side)
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
        .frame(width: side, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gallery.title), \(gallery.count) photo\(gallery.count == 1 ? "" : "s")")
        .accessibilityAddTraits(.isButton)
    }
}
