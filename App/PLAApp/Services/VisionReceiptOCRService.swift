import Foundation
import Vision
import UIKit
import ImageIO
import PLACore

extension Notification.Name {
    static let plaExternalDataDidChange = Notification.Name("id.revand.pla.externalDataDidChange")
    static let plaPendingOCRReceiptArrived = Notification.Name("id.revand.pla.pendingOCRReceiptArrived")
}

/// Offline Apple Vision OCR service with strict privacy hygiene (PRD P-05 & §13.4):
/// Images are processed strictly in memory / private temp directory and deleted immediately after text extraction.
enum VisionReceiptOCRService {
    private static var privateTempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pla_ocr_private", isDirectory: true)
    }

    /// Sweeps any residual temporary OCR files on every app launch (PRD §13.4).
    static func cleanupResidualTempFiles() {
        let dir = privateTempDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Runs `VNRecognizeTextRequest` (.accurate, id-ID + en-US) entirely on-device without persisting the photo.
    static func recognizeAndParse(
        imageData: Data,
        fallbackDate: LocalDate
    ) async -> ParsedReceiptOCR {
        defer { cleanupResidualTempFiles() }

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

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(from: uiImage.imageOrientation), options: [:])
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

/// Lightweight text-only handoff between `ScanReceiptIntent` and the foreground Review Transaction UI (never stores image bytes).
struct PendingOCRReceiptDraft: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var amount: Int64?
    var date: LocalDate?
    var merchant: String?
    var detectedSourceApp: String?
    var rawLineCount: Int
    var createdAt: Date = Date()

    init(parsed: ParsedReceiptOCR) {
        self.amount = parsed.amount
        self.date = parsed.date
        self.merchant = parsed.merchant
        self.detectedSourceApp = parsed.detectedSourceApp
        self.rawLineCount = parsed.rawLineCount
    }
}

enum PendingOCRReceiptStore {
    private static let key = "id.revand.pla.pending_ocr_receipt_draft"

    static func save(_ draft: PendingOCRReceiptDraft) {
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func consume() -> PendingOCRReceiptDraft? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let draft = try? JSONDecoder().decode(PendingOCRReceiptDraft.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return draft
    }
}
