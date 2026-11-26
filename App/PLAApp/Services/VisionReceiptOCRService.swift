import Foundation
import PLACore

extension Notification.Name {
    static let plaExternalDataDidChange = Notification.Name("id.revand.pla.externalDataDidChange")
    static let plaPendingOCRReceiptArrived = Notification.Name("id.revand.pla.pendingOCRReceiptArrived")
}

/// Offline Apple Vision OCR service with strict privacy hygiene (PRD P-05, P-06 & §13.4):
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
        return await PLASharedOCR.recognizeAndParse(imageData: imageData, fallbackDate: fallbackDate)
    }
}

/// Lightweight text-only handoff between `ScanReceiptIntent` (P-05), `PLAShareExtension` (P-06), and foreground Review UI.
/// Never stores image bytes (PRD §13.4).
typealias PendingOCRReceiptDraft = SharedOCRReceiptPayload

enum PendingOCRReceiptStore {
    static func save(_ draft: PendingOCRReceiptDraft) {
        PLASharedContainer.savePendingOCRDraft(draft)
    }

    static func consume() -> PendingOCRReceiptDraft? {
        PLASharedContainer.consumePendingOCRDraft()
    }
}
