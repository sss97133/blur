// PhotoTags.swift — the factual tag record for one photo.
//
// This is the heart of Blur's thesis: a programmatic view of the metadata the
// Photos app HAS but never shows you as data. Everything here is read freely
// from PhotoKit + ImageIO — no ML, no network, no Apple-private graph. The
// semantic layer (scene labels, people, captions) is walled off by Apple and
// is rebuilt later with Vision; this file is the free, instant foundation.
//
// SwiftUI-free on purpose: the engine is a shared core. The app, a future
// Table view, App Intents, and extensions are all thin clients of it, so it
// must not depend on the UI layer.

import Foundation
import CoreLocation

/// One labeled cell of the tag table — the unit both the per-photo inspector
/// and the future spreadsheet view render. `group` lets a UI section them.
struct TagField: Identifiable {
    let id = UUID()
    let group: String
    let label: String
    let value: String
}

/// Every factual tag we can read for a photo, for free, on-device.
struct PhotoTags {
    let assetID: String

    // ── Capture ──
    var creationDate: Date?
    var location: CLLocation?
    var placeName: String?      // reverse-geocoded, loaded on demand
    var fileName: String?       // original resource filename

    // ── Image ──
    var pixelWidth = 0
    var pixelHeight = 0
    var isScreenshot = false
    var isLive = false
    var isPanorama = false
    var isHDR = false
    var isDepth = false
    var fileType: String?       // "JPEG", "HEIC", … (from the resource UTI)
    var fileSizeBytes: Int?     // original byte size

    // ── Library state ──
    var isFavorite = false
    var isHidden = false        // Apple's own Hidden flag (distinct from Blur's blur)
    var burstID: String?
    var albumNames: [String] = []

    // ── Camera (EXIF, loaded on demand) ──
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var iso: Int?
    var aperture: Double?       // f-number
    var focalLength: Double?    // mm
    var shutter: Double?        // seconds
    var exposureBias: Double?   // ev

    init(assetID: String) { self.assetID = assetID }

    var megapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }

    // ── Apple-style EXIF card accessors (Image #7 layout) ──

    /// The camera's display name, e.g. "NIKON D800E" — model preferred, make
    /// as fallback.
    var cameraName: String? {
        if let cameraModel, !cameraModel.isEmpty { return cameraModel }
        return cameraMake
    }

    /// "16.0-35.0 mm ƒ4.0" when the lens reports it; otherwise built from the
    /// shot's own focal length + aperture.
    var lensLine: String? {
        if let lensModel, !lensModel.isEmpty { return lensModel }
        var parts: [String] = []
        if let focalLength { parts.append("\(Int(focalLength.rounded())) mm") }
        if let aperture { parts.append(String(format: "ƒ%.1f", aperture)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "4 MP • 1668 × 2500 • 1.3 MB"
    var sizeLine: String? {
        var parts: [String] = []
        if megapixels > 0 { parts.append("\(Int(megapixels.rounded())) MP") }
        if pixelWidth > 0 { parts.append("\(pixelWidth) × \(pixelHeight)") }
        if let fileSizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// The bottom stat strip: ISO 50 | 32 mm | 0 ev | ƒ22 | 0.8 s.
    var exposureStats: [String] {
        var out: [String] = []
        if let iso { out.append("ISO \(iso)") }
        if let focalLength { out.append("\(Int(focalLength.rounded())) mm") }
        if let exposureBias { out.append(String(format: "%g ev", exposureBias)) }
        if let aperture { out.append(String(format: "ƒ%g", aperture)) }
        if let shutter { out.append(Self.shutterString(shutter)) }
        return out
    }

    static func shutterString(_ shutter: Double) -> String {
        shutter < 1 ? "1/\(Int((1 / shutter).rounded())) s" : String(format: "%.1f s", shutter)
    }

    /// "Wednesday • Aug 8, 2012 • 5:29 PM" — the inspector header line.
    var headerDate: String? {
        guard let creationDate else { return nil }
        return Self.headerFormatter.string(from: creationDate)
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMM d yyyy h mm a")
        return f
    }()

    /// Cached — `fields` is recomputed on every SwiftUI pass; a fresh
    /// DateFormatter each time is needless churn.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// The tag table for this photo — non-empty fields only, grouped and
    /// formatted for display. Same shape the spreadsheet view will use as columns.
    var fields: [TagField] {
        var out: [TagField] = []
        func add(_ group: String, _ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            out.append(TagField(group: group, label: label, value: value))
        }

        // Capture
        if let creationDate {
            add("Capture", "Taken", Self.dateFormatter.string(from: creationDate))
        }
        add("Capture", "Place", placeName)
        if let c = location?.coordinate {
            add("Capture", "Coordinates", String(format: "%.5f, %.5f", c.latitude, c.longitude))
            if let alt = location?.altitude, alt != 0 {
                add("Capture", "Altitude", "\(Int(alt.rounded())) m")
            }
        }
        add("Capture", "File", fileName)

        // Image
        if pixelWidth > 0 {
            add("Image", "Dimensions", "\(pixelWidth) × \(pixelHeight)")
            add("Image", "Megapixels", String(format: "%.1f MP", megapixels))
        }
        add("Image", "Format", fileType)
        if let fileSizeBytes {
            add("Image", "File size", ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file))
        }
        let kinds = [isScreenshot ? "Screenshot" : nil, isLive ? "Live" : nil,
                     isPanorama ? "Panorama" : nil, isHDR ? "HDR" : nil,
                     isDepth ? "Depth" : nil].compactMap { $0 }
        if !kinds.isEmpty { add("Image", "Type", kinds.joined(separator: ", ")) }

        // Camera
        let body = [cameraMake, cameraModel].compactMap { $0 }.joined(separator: " ")
        add("Camera", "Camera", body)
        add("Camera", "Lens", lensModel)
        if let iso { add("Camera", "ISO", "\(iso)") }
        if let aperture { add("Camera", "Aperture", String(format: "ƒ/%.1f", aperture)) }
        if let focalLength { add("Camera", "Focal length", "\(Int(focalLength.rounded())) mm") }
        if let shutter {
            let s = shutter < 1 ? "1/\(Int((1 / shutter).rounded())) s" : String(format: "%.1f s", shutter)
            add("Camera", "Shutter", s)
        }

        // Library
        add("Library", "Favorite", isFavorite ? "Yes" : nil)
        add("Library", "Hidden (Apple)", isHidden ? "Yes" : nil)
        add("Library", "Burst", burstID != nil ? "Yes" : nil)
        if !albumNames.isEmpty { add("Library", "Albums", albumNames.joined(separator: ", ")) }

        return out
    }
}
