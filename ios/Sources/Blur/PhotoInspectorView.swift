// PhotoInspectorView.swift — tap a photo, see the data Photos hides.
//
// The first surface that makes Blur's thesis tangible: the photo at the top
// (like Photos), and below it the full factual tag table Apple never exposes —
// capture, place, image, camera/EXIF, library state. Plus the one premium
// action: hide this photo so it blurs when you hand someone your phone.
//
// All native: NavigationStack + List + LabeledContent. The data comes from the
// shared engine (TagExtractor); this view is a thin client.

import SwiftUI
import Photos

struct PhotoInspectorView: View {
    let assetID: String
    @EnvironmentObject private var library: LibraryEngine
    @Environment(\.dismiss) private var dismiss
    @State private var tags: PhotoTags?

    private let groupOrder = ["Capture", "Image", "Camera", "Library"]

    private var grouped: [(String, [TagField])] {
        let dict = Dictionary(grouping: tags?.fields ?? []) { $0.group }
        return groupOrder.compactMap { key in dict[key].map { (key, $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AssetThumbnail(assetIdentifier: assetID, side: 240, cornerRadius: 12,
                                   blurred: library.isHidden(assetID))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                ForEach(grouped, id: \.0) { group, items in
                    Section(group) {
                        ForEach(items) { field in
                            LabeledContent(field.label, value: field.value)
                        }
                    }
                }

                Section {
                    Button {
                        library.toggleHidden(assetID)
                    } label: {
                        Label(library.isHidden(assetID) ? "Blurred — tap to reveal" : "Blur this photo",
                              systemImage: library.isHidden(assetID) ? "eye" : "eye.slash")
                    }
                } footer: {
                    Text("Blurring is private to Blur and reversible — the photo blurs in the grid and drops out of Show mode so you can hand someone your phone. Nothing is deleted; your Photos library is untouched.")
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: assetID) {
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
                else { return }
                tags = TagExtractor.fastTags(for: asset)        // instant
                tags = await TagExtractor.fullTags(for: asset)  // + EXIF
            }
        }
    }
}
