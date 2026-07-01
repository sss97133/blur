// PhotoInspectorView.swift — tap a photo, see everything.
//
// Modeled on Apple's own photo info card: the image up top, a weekday/date
// header, then the camera/EXIF card (make · type badge · lens · MP•dims•size ·
// the ISO|mm|ev|ƒ|s strip) and a map. That's the part Photos does well, matched.
//
// Then Blur takes it farther: a "Full metadata" section exposing EVERY factual
// tag we can read — the flat table Apple keeps to itself. Same engine
// (TagExtractor) feeds both the pretty card and the complete table.

import SwiftUI
import Photos
import MapKit

struct PhotoInspectorView: View {
    let assetID: String
    @EnvironmentObject private var library: LibraryEngine
    @State private var tags: PhotoTags?
    @State private var vision: VisionTags?
    @State private var showAllMetadata = false

    private let groupOrder = ["Capture", "Image", "Camera", "Library"]

    private var grouped: [(String, [TagField])] {
        let dict = Dictionary(grouping: tags?.fields ?? []) { $0.group }
        return groupOrder.compactMap { key in dict[key].map { (key, $0) } }
    }

    private var isHidden: Bool { library.isHidden(assetID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AssetHeroImage(assetIdentifier: assetID, blurred: isHidden)

                VStack(alignment: .leading, spacing: 18) {
                    if let tags {
                        header(tags)
                        visionCard
                        exifCard(tags)
                        map(tags)
                    }
                    blurAction
                    if let tags { fullMetadata(tags) }
                }
                .padding()
            }
        }
        .presentationDragIndicator(.visible)
        .task(id: assetID) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
            else { return }
            tags = TagExtractor.fastTags(for: asset)        // instant
            tags = await TagExtractor.fullTags(for: asset)  // + EXIF, place, size
        }
        .task(id: assetID) {
            vision = nil                                     // show "Analyzing…" on switch
            vision = await VisionTagger.tags(for: assetID)   // on-device semantics
        }
    }

    // ── Vision: what's IN the photo, computed on-device (Layer 2) ──
    private var visionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Vision", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let vision, vision.faceCount > 0 {
                    Label("\(vision.faceCount)", systemImage: "person.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let vision {
                if vision.subjects.isEmpty {
                    Text(vision.faceCount > 0 ? "Faces detected." : "No subjects detected.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(vision.subjects) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.label)
                                    Text("\(tag.percent)%").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Analyzing on device…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Date + filename header ──
    private func header(_ t: PhotoTags) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let headerDate = t.headerDate {
                Text(headerDate).font(.headline)
            }
            if let fileName = t.fileName {
                Text(fileName).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── The Apple-style EXIF card ──
    @ViewBuilder
    private func exifCard(_ t: PhotoTags) -> some View {
        if t.cameraName != nil || t.sizeLine != nil || !t.exposureStats.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.cameraName ?? (t.isScreenshot ? "Screenshot" : "Photo"))
                        .font(.headline)
                    Spacer()
                    if let fileType = t.fileType {
                        Text(fileType)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                if let lens = t.lensLine {
                    Text(lens).font(.subheadline).foregroundStyle(.secondary)
                }
                if let size = t.sizeLine {
                    Text(size).font(.subheadline).foregroundStyle(.secondary)
                }
                if !t.exposureStats.isEmpty {
                    Divider().padding(.vertical, 4)
                    HStack(spacing: 0) {
                        ForEach(Array(t.exposureStats.enumerated()), id: \.offset) { i, stat in
                            if i > 0 { Divider().frame(height: 16) }
                            Text(stat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // ── Map ──
    @ViewBuilder
    private func map(_ t: PhotoTags) -> some View {
        if let coord = t.location?.coordinate {
            VStack(alignment: .leading, spacing: 6) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord, latitudinalMeters: 800, longitudinalMeters: 800))) {
                    Marker(t.placeName ?? "", coordinate: coord)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                if let place = t.placeName {
                    Text(place).font(.subheadline)
                }
            }
        }
    }

    // ── Blur action (reversible, private — never destructive) ──
    private var blurAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                library.toggleHidden(assetID)
            } label: {
                Label(isHidden ? "Blurred — tap to reveal" : "Blur this photo",
                      systemImage: isHidden ? "eye" : "eye.slash")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Text("Blurring is private to Blur and reversible — the photo blurs in the grid and drops out of Show mode. Nothing is deleted; your Photos library is untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // ── Take it farther: the complete factual table Apple hides ──
    @ViewBuilder
    private func fullMetadata(_ t: PhotoTags) -> some View {
        let fieldCount = t.fields.count
        DisclosureGroup(isExpanded: $showAllMetadata) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(grouped, id: \.0) { group, items in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(items) { field in
                            HStack(alignment: .top) {
                                Text(field.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(field.value)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Full metadata · \(fieldCount) fields", systemImage: "tablecells")
                .font(.body.weight(.medium))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
