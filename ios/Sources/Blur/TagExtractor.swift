// TagExtractor.swift — reads a photo's factual tags from PhotoKit + ImageIO.
//
// Two tiers, both on-device, both free:
//   • fastTags(for:)  — instant, from PHAsset properties alone (no image load).
//   • fullTags(for:)  — fast tags PLUS album membership and EXIF (camera, lens,
//     ISO…). Reading EXIF means fetching the original's bytes once (PhotoKit
//     may pull them from iCloud); we read only the metadata dictionary from
//     them via CGImageSource — the pixels are never decoded. On demand, per
//     photo; a whole-library pass would cache this (later, the Table).
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
        return t
    }

    /// Reverse-geocode a coordinate into a short, readable place — the vague
    /// "37.77493, -122.41942" becomes "Mission District, San Francisco". Fully
    /// on-device where possible; Apple may hit the network for the name only.
    private static func placeName(for location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = marks?.first else { return nil }
        let parts = [p.name, p.locality, p.administrativeArea]
            .compactMap { $0 }
        // Drop a leading street-number-only `name` that just repeats detail.
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.prefix(3).joined(separator: ", ")
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
        t.albumNames = albumNames(for: asset)   // reverse lookup — kept off the instant path
        if let resource = PHAssetResource.assetResources(for: asset).first {
            t.fileName = resource.originalFilename
            t.fileType = shortFileType(resource.uniformTypeIdentifier)
        }
        if let loc = asset.location {
            t.placeName = await placeName(for: loc)   // raw coords are vague; show a name
        }
        guard let (props, byteCount) = await imageProperties(for: asset) else { return t }
        t.fileSizeBytes = byteCount

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        // ImageIO hands these back as NSNumber; bridge explicitly so a stray
        // type doesn't silently null the field (ISO arrives as [NSNumber]).
        t.cameraMake = tiff?[kCGImagePropertyTIFFMake] as? String
        t.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        t.lensModel = exif?[kCGImagePropertyExifLensModel] as? String
        t.iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        t.aperture = (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
        t.focalLength = (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue
        t.shutter = (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
        t.exposureBias = (exif?[kCGImagePropertyExifExposureBiasValue] as? NSNumber)?.doubleValue
        return t
    }

    /// Turn a UTI ("public.jpeg", "public.heic") into Apple's short badge text.
    private static func shortFileType(_ uti: String) -> String? {
        switch uti.lowercased() {
        case let u where u.contains("jpeg"): return "JPEG"
        case let u where u.contains("heic"), let u where u.contains("heif"): return "HEIC"
        case let u where u.contains("png"): return "PNG"
        case let u where u.contains("dng"), let u where u.contains("raw"): return "RAW"
        case let u where u.contains("gif"): return "GIF"
        case let u where u.contains("tiff"): return "TIFF"
        default:
            return uti.split(separator: ".").last.map { $0.uppercased() }
        }
    }

    /// Pull the image-properties dictionary (EXIF/TIFF) and the original byte
    /// size without decoding the bitmap. Allowed to hit the network for
    /// iCloud-optimized originals.
    private static func imageProperties(for asset: PHAsset) async -> (props: [CFString: Any], bytes: Int)? {
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
                continuation.resume(returning: (props, data.count))
            }
        }
    }
}
