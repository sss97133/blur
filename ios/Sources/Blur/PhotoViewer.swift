// PhotoViewer.swift — the full-screen photo view, like Photos.
//
// Tap a photo in the grid → here: full-bleed on black, pinch + pan + double-tap
// to zoom, swipe left/right between photos. Info (the inspector) and Blur move
// to buttons, so the primary gesture is looking at the picture — exactly the
// Photos-app feel.

import SwiftUI
import Photos

struct PhotoViewer: View {
    let assetIDs: [String]
    @State var index: Int
    @EnvironmentObject private var library: LibraryEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    private var currentID: String { assetIDs[min(index, assetIDs.count - 1)] }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(assetIDs.enumerated()), id: \.offset) { i, assetID in
                    ZoomableImage(
                        assetID: assetID,
                        blurred: library.viewMode != .reveal && library.isHidden(assetID)
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        library.toggleHidden(currentID)
                        Haptics.impact(.light)
                    } label: {
                        let hidden = library.isHidden(currentID)
                        Label(hidden ? "Reveal" : "Blur", systemImage: hidden ? "eye" : "eye.slash")
                    }
                }
            }
            .sheet(isPresented: $showInfo) { PhotoInspectorView(assetID: currentID) }
        }
    }
}

/// One pinch/pan/double-tap zoomable photo.
private struct ZoomableImage: View {
    let assetID: String
    var blurred: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    private var effectiveScale: CGFloat { max(1, scale * pinch) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .blur(radius: blurred ? 40 : 0)
            } else {
                Color.black
            }
        }
        .scaleEffect(effectiveScale)
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
        .gesture(
            MagnificationGesture()
                .updating($pinch) { value, state, _ in state = value }
                .onEnded { value in
                    scale = min(max(scale * value, 1), 6)
                    if scale == 1 { offset = .zero }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .updating($drag) { value, state, _ in
                    if effectiveScale > 1 { state = value.translation }
                }
                .onEnded { value in
                    if scale > 1 { offset.width += value.translation.width; offset.height += value.translation.height }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 }
            }
        }
        .task(id: assetID) {
            image = await AssetImageLoader.load(
                identifier: assetID,
                target: CGSize(width: 2200, height: 2200),
                mode: .aspectFit, crisp: true, allowsNetwork: true
            )
        }
    }
}
