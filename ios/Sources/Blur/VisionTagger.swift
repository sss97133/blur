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
    var facePrints: [[Float]] = []   // one feature-vector per detected face (for people clustering)
    var isEmpty: Bool { subjects.isEmpty && faceCount == 0 && text.isEmpty }
}

/// The cached per-photo record (what the library-wide index stores).
struct PhotoVision: Codable {
    var subjects: [String]
    var text: [String]
    var people: [Int] = []        // person-cluster ids this photo's faces belong to
}

/// One clustered person — a representative face-vector + a cover photo.
struct Person: Codable, Identifiable {
    let id: Int
    var cover: String             // assetID for the person's cover face
    var vector: [Float]           // representative feature-vector
}

/// Euclidean distance between two feature-vectors (same length).
func faceDistance(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
    var sum: Float = 0
    for i in a.indices { let d = a[i] - b[i]; sum += d * d }
    return sum.squareRoot()
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

        return await Task.detached(priority: .utility) {
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

            // A feature-vector per face (crop → feature-print) — the raw material
            // for on-device people clustering.
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            for face in faces.results ?? [] {
                let bb = face.boundingBox
                let rect = CGRect(x: bb.minX * w, y: (1 - bb.maxY) * h,
                                  width: bb.width * w, height: bb.height * h).integral
                guard rect.width > 24, rect.height > 24, let crop = cg.cropping(to: rect) else { continue }
                let fp = VNGenerateImageFeaturePrintRequest()
                try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([fp])
                if let obs = fp.results?.first as? VNFeaturePrintObservation, obs.elementType == .float {
                    let vec = obs.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    if !vec.isEmpty { result.facePrints.append(vec) }
                }
            }
            return result
        }.value
    }

    /// Vision labels arrive like "sports_car" / "coffee_cup" — humanize them.
    private static func pretty(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
