// AssetThumbnail.swift — local PhotoKit image views + a shared loader.
//
// PORTED from the Nuke capture app's TodayView thumbnail loader, generalized.
// Pure PhotoKit — zero network for thumbnails. Two views share one loader:
//   • AssetThumbnail — a square, croppable tile for the grid.
//   • AssetHeroImage — a full-aspect image for the inspector's hero (like the
//     photo at the top of Apple's info card).
// Identifiers that no longer resolve (deleted photo) render a placeholder.

import SwiftUI
import Photos

struct AssetThumbnail: View {
    let assetIdentifier: String
    var side: CGFloat = 120
    var cornerRadius: CGFloat = 10
    /// When true, the image is rendered with a heavy blur (the "hidden" state).
    var blurred: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blurred ? 28 : 0)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemFill))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // The one flourish the doctrine allows: the blur resolving in and out,
        // on the system default curve — never a bespoke timing.
        .animation(.default, value: blurred)
        // Decorative — the enclosing card/button carries the accessible label.
        .accessibilityHidden(true)
        // Reload when the identifier OR the tile size changes: pinch-zooming the
        // grid resizes tiles, and we want crisp pixels at the new size, like Photos.
        .task(id: "\(assetIdentifier)#\(Int(side.rounded()))") {
            image = await AssetImageLoader.load(
                identifier: assetIdentifier,
                target: CGSize(width: side * displayScale, height: side * displayScale),
                mode: .aspectFill,
                crisp: false,           // grid: cheap resize, small target
                allowsNetwork: true     // load iCloud-optimized photos
            )
        }
    }
}

/// The photo at the top of the inspector, shown at its real aspect ratio and
/// filling the available width (Apple's info sheet leads with the image).
struct AssetHeroImage: View {
    let assetIdentifier: String
    var blurred: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .blur(radius: blurred ? 40 : 0)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.default, value: blurred)
        .accessibilityHidden(true)
        .task(id: assetIdentifier) {
            image = await AssetImageLoader.load(
                identifier: assetIdentifier,
                target: CGSize(width: 1400 * displayScale, height: 1400 * displayScale),
                mode: .aspectFit
            )
        }
    }
}

/// One PhotoKit image request, shared by both views above.
enum AssetImageLoader {
    /// Always .highQualityFormat: it fires the handler EXACTLY ONCE (so the
    /// checked continuation can't double-resume) and always returns an image
    /// (unlike .fastFormat, which yields nil when no fast thumbnail is cached —
    /// that left tiles blank). Memory safety for the grid comes from a SMALL
    /// target + `.fast` resize, not from starving the request.
    ///
    /// Grid tiles pass crisp:false (cheap resize); the inspector hero passes the
    /// default crisp:true (exact). Both keep network on so iCloud-optimized
    /// photos load, like Photos.
    static func load(identifier: String, target: CGSize, mode: PHImageContentMode,
                     crisp: Bool = true, allowsNetwork: Bool = true) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // single-fire, always returns
        options.resizeMode = crisp ? .exact : .fast
        options.isNetworkAccessAllowed = allowsNetwork

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: mode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
