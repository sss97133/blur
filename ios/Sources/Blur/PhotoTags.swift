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

    // ── Image ──
    var pixelWidth = 0
    var pixelHeight = 0
    var isScreenshot = false
    var isLive = false
    var isPanorama = false
    var isHDR = false
    var isDepth = false

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

    init(assetID: String) { self.assetID = assetID }

    var megapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }

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
            let f = DateFormatter()
            f.dateStyle = .medium; f.timeStyle = .short
            add("Capture", "Taken", f.string(from: creationDate))
        }
        if let c = location?.coordinate {
            add("Capture", "Place", String(format: "%.5f, %.5f", c.latitude, c.longitude))
        }

        // Image
        if pixelWidth > 0 {
            add("Image", "Dimensions", "\(pixelWidth) × \(pixelHeight)")
            add("Image", "Megapixels", String(format: "%.1f MP", megapixels))
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
