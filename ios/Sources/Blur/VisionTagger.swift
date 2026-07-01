// VisionTagger.swift — the semantic layer, computed by us on-device.
//
// Apple's Photos app computes scene/subject labels and a people graph, but locks
// those RESULTS away (no PhotoKit access). Apple does, however, hand us the same
// on-device engines via the Vision framework — so we recompute them ourselves,
// free, offline, private. This is Layer 2 of Blur's tags: instant PhotoKit facts
// are Layer 1 (TagExtractor); this is the "what's IN the photo" layer.
//
// v1: scene/object classification (VNClassifyImageRequest — this is how "blur
// anything automotive" works) + face COUNT (VNDetectFaceRectangles; identity is
// Apple's one real lock, so we detect presence, not who). OCR and feature-print
// clustering layer in later. All on-device; nothing leaves the phone.

import Foundation
import Vision

/// One Vision-detected subject label with its confidence.
struct VisionTag: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let confidence: Float
    var percent: Int { Int((confidence * 100).rounded()) }
}

/// Everything Vision read from one photo (runtime — for the inspector).
struct VisionTags {
    var subjects: [VisionTag] = []
    var faceCount: Int = 0
    var text: [String] = []          // OCR'd lines — the actionable evidence
    var isEmpty: Bool { subjects.isEmpty && faceCount == 0 && text.isEmpty }
}

/// The cached per-photo record (what the library-wide index stores).
struct PhotoVision: Codable {
    var subjects: [String]
    var text: [String]
}

enum VisionTagger {

    /// Run Vision on one photo. Loads a modest image (Vision doesn't need full
    /// res), then classifies + counts faces off the main thread.
    static func tags(for assetID: String) async -> VisionTags {
        guard let image = await AssetImageLoader.load(
            identifier: assetID,
            target: CGSize(width: 512, height: 512),
            mode: .aspectFit, crisp: true, allowsNetwork: true),
              let cg = image.cgImage else { return VisionTags() }

        return await Task.detached(priority: .userInitiated) {
            var result = VisionTags()
            let classify = VNClassifyImageRequest()
            let faces = VNDetectFaceRectanglesRequest()
            let ocr = VNRecognizeTextRequest()
            ocr.recognitionLevel = .fast          // library-wide pass: speed over perfection
            ocr.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            try? handler.perform([classify, faces, ocr])

            if let observations = classify.results {
                result.subjects = observations
                    .filter { $0.confidence > 0.10 }             // drop the long tail of noise
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(8)
                    .map { VisionTag(label: Self.pretty($0.identifier), confidence: $0.confidence) }
            }
            result.faceCount = faces.results?.count ?? 0
            result.text = (ocr.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.count >= 2 }        // drop single-char noise
            return result
        }.value
    }

    /// Vision labels arrive like "sports_car" / "coffee_cup" — humanize them.
    private static func pretty(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
