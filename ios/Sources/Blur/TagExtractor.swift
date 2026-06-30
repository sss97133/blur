// TagExtractor.swift — reads a photo's factual tags from PhotoKit + ImageIO.
//
// Two tiers, both on-device, both free:
//   • fastTags(for:)  — instant, from PHAsset alone (no image load).
//   • fullTags(for:)  — fast tags PLUS EXIF (camera, lens, ISO…), which needs
//     the image's metadata. We read ONLY the metadata via CGImageSource — we
//     never decode the pixels — so it's cheap.
//
// SwiftUI-free: part of the shared engine core.

import Foundation
import Photos
import ImageIO
import CoreLocation

enum TagExtractor {

    // ── Tier 1: instant PHAsset metadata ──

    static func fastTags(for asset: PHAsset) -> PhotoTags {
        var t = PhotoTags(assetID: asset.localIdentifier)
        t.creationDate = asset.creationDate
        t.location = asset.location
        t.isFavorite = asset.isFavorite
        t.isHidden = asset.isHidden
        t.pixelWidth = asset.pixelWidth
        t.pixelHeight = asset.pixelHeight
        let s = asset.mediaSubtypes
        t.isScreenshot = s.contains(.photoScreenshot)
        t.isLive = s.contains(.photoLive)
        t.isPanorama = s.contains(.photoPanorama)
        t.isHDR = s.contains(.photoHDR)
        t.isDepth = s.contains(.photoDepthEffect)
        t.burstID = asset.burstIdentifier
        t.albumNames = albumNames(for: asset)
        return t
    }

    /// Reverse lookup: which user albums contain this asset.
    private static func albumNames(for asset: PHAsset) -> [String] {
        let cols = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var names: [String] = []
        cols.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle { names.append(title) }
        }
        return names
    }

    // ── Tier 2: + EXIF (metadata only, no pixel decode) ──

    static func fullTags(for asset: PHAsset) async -> PhotoTags {
        var t = fastTags(for: asset)
        guard let props = await imageProperties(for: asset) else { return t }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        t.cameraMake = tiff?[kCGImagePropertyTIFFMake] as? String
        t.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        t.lensModel = exif?[kCGImagePropertyExifLensModel] as? String
        t.iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        t.aperture = exif?[kCGImagePropertyExifFNumber] as? Double
        t.focalLength = exif?[kCGImagePropertyExifFocalLength] as? Double
        t.shutter = exif?[kCGImagePropertyExifExposureTime] as? Double
        return t
    }

    /// Pull just the image-properties dictionary (EXIF/TIFF) without decoding
    /// the bitmap. Allowed to hit the network for iCloud-optimized originals.
    private static func imageProperties(for asset: PHAsset) async -> [CFString: Any]? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: props)
            }
        }
    }
}
