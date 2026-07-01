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

    /// Fixed load resolution — large enough to stay crisp across the whole pinch
    /// zoom range (dense tiles → a couple per row), independent of the current
    /// tile size so resizing never triggers a reload.
    private static let loadTarget = CGSize(width: 500, height: 500)

    @State private var image: UIImage?

    /// Prefer live @State, else the synchronous cache — so a recreated cell
    /// (e.g. on a pinch column change) shows its image instantly, never white.
    private var displayImage: UIImage? {
        image ?? AssetImageLoader.cached(assetIdentifier, target: Self.loadTarget)
    }

    var body: some View {
        Group {
            if let img = displayImage {
                Image(uiImage: img)
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
        // Load ONCE per asset at a fixed resolution — keyed on the identifier
        // only, NOT the tile size. Pinch-zoom changes `side` every frame; if the
        // load were keyed on size, each pinch would blank + reload every tile
        // (the white flash). Keeping one cached image and letting .scaledToFill
        // rescale it is how Photos stays graceful — the tiles shrink/grow with a
        // real image on every frame.
        .task(id: assetIdentifier) {
            image = await AssetImageLoader.load(
                identifier: assetIdentifier,
                target: Self.loadTarget,
                mode: .aspectFill,
                crisp: false,           // cheap resize
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

/// One PhotoKit image request, shared by both views above — with an in-memory
/// cache so a tile is NEVER blank if its image was ever loaded (kills the white
/// flash on resize/scroll, the way Photos' caching image manager does).
enum AssetImageLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 800          // NSCache also auto-evicts under memory pressure
        return c
    }()

    private static func key(_ id: String, _ target: CGSize) -> NSString {
        "\(id)@\(Int(target.width))" as NSString
    }

    /// Synchronous cache hit — used as an instant fallback before .task runs, so
    /// a recreated cell shows its image immediately instead of flashing white.
    static func cached(_ identifier: String, target: CGSize) -> UIImage? {
        cache.object(forKey: key(identifier, target))
    }

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

        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: mode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image { cache.setObject(image, forKey: key(identifier, target)) }
        return image
    }
}
