import Foundation
import Vision
import UIKit
import ImageIO
import PLACore

/// Shared on-device Apple Vision OCR helper used by both `PLAApp` (P-05) and `PLAShareExtension` (P-06).
/// Strictly processes image bytes in memory and deletes any temporary staging immediately (PRD §13.4).
enum PLASharedOCR {
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
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["id-ID", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgOrientation(from: uiImage.imageOrientation),
            options: [:]
        )
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        } catch {
            return []
        }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
