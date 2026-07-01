// SubjectDetailView.swift — drill into a Vision subject.
//
// Tapping a subject in the Tags tab lands here: how many photos carry it, its
// closest associates (subjects that co-occur — "Vehicle" → Wheel, Road,
// Trailer), each tappable to keep drilling, and the photos themselves below.
// The graph, navigable — the "right click" made a screen.

import SwiftUI

struct SubjectDetailView: View {
    let label: String
    @EnvironmentObject private var library: LibraryEngine

    var body: some View {
        let assets = library.assets(forSubject: label)
        let associates = library.associates(for: label)

        VStack(spacing: 0) {
            // Metrics + associates header.
            VStack(alignment: .leading, spacing: 10) {
                Text("\(assets.count) photo\(assets.count == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)

                if !associates.isEmpty {
                    Text("Also appears with")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(associates, id: \.label) { assoc in
                                NavigationLink(value: SubjectRef(label: assoc.label)) {
                                    HStack(spacing: 4) {
                                        Text(assoc.label)
                                        Text("\(assoc.count)").foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(.secondarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // The photos — the same grid surface (pinch, select, blur, drill).
            PhotoGrid(title: label, assetIDs: assets)
        }
    }
}
