import Foundation
import Vision
import UIKit
import ImageIO
import PLACore

/// Shared on-device Apple Vision OCR helper used by both `PLAApp` (P-05) and `PLAShareExtension` (P-06).
/// Downscales large photos in memory before Vision OCR to stay far below the 120 MB iOS App Extension RAM limit,
/// and never writes image bytes to disk or database (PRD §13.4).
enum PLASharedOCR {
    private static let maxDimensionPixels: CGFloat = 1800

    static func recognizeAndParse(
        imageData: Data,
        fallbackDate: LocalDate
    ) async -> ParsedReceiptOCR {
        let lines: [String] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let recognized = performVisionOCR(imageData: imageData)
                continuation.resume(returning: recognized)
            }
        }
        return ReceiptOCRParser.parse(lines: lines, fallbackDate: fallbackDate)
    }

    private static func performVisionOCR(imageData: Data) -> [String] {
        guard let cgImage = makeOrientedDownscaledCGImage(from: imageData) else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["id-ID", "en-US"]
        request.usesLanguageCorrection = true

        // Image is already oriented upright by CGImageSourceCreateThumbnailAtIndex
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        } catch {
            return []
        }
    }

    /// Creates a memory-efficient upright CGImage (<= 1800px) so 12MP–48MP iPhone screenshots never OOM a Share Extension.
    private static func makeOrientedDownscaledCGImage(from imageData: Data) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        if let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions as CFDictionary) {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimensionPixels
            ]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
                return thumb
            }
            if let full = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return full
            }
        }
        return UIImage(data: imageData)?.cgImage
    }
}
