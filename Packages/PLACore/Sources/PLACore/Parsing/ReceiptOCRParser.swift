import Foundation

/// Structured extraction result from Apple Vision OCR text lines (PRD P-05 & SC-P1).
public struct ParsedReceiptOCR: Equatable, Sendable {
    public let amount: Int64?
    public let date: LocalDate?
    public let merchant: String?
    public let detectedSourceApp: String?
    public let suggestedType: TransactionType
    public let rawLineCount: Int

    public init(
        amount: Int64?,
        date: LocalDate?,
        merchant: String?,
        detectedSourceApp: String?,
        suggestedType: TransactionType = .expense,
        rawLineCount: Int = 0
    ) {
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.detectedSourceApp = detectedSourceApp
        self.suggestedType = suggestedType
        self.rawLineCount = rawLineCount
    }
}

/// Offline regex & heuristic parser for Indonesian bank, e-wallet, QRIS, and retail receipts (BCA, Mandiri, GoPay, OVO, DANA, QRIS).
public enum ReceiptOCRParser {
    private static let monthMap: [String: Int] = [
        "jan": 1, "januari": 1, "january": 1,
        "feb": 2, "februari": 2, "february": 2, "peb": 2,
        "mar": 3, "maret": 3, "march": 3,
        "apr": 4, "april": 4,
        "mei": 5, "may": 5,
        "jun": 6, "juni": 6, "june": 6,
        "jul": 7, "juli": 7, "july": 7,
        "agu": 8, "agt": 8, "agustus": 8, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "okt": 10, "oktober": 10, "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "des": 12, "desember": 12, "dec": 12, "december": 12
    ]

    private static let amountPriorityKeywords = [
        "total bayar", "grand total", "total pembayaran", "total transaksi", "total tagihan",
        "jumlah transfer", "nominal transfer", "total debit", "total belanja",
        "dibayar", "nominal", "jumlah", "total", "amount"
    ]

    private static let amountNoiseKeywords = [
        "saldo", "balance", "poin", "point", "cashback", "diskon", "hemat", "kembali", "kembalian",
        "biaya admin", "admin fee", "pajak", "ppn", "tax", "subtotal", "sub total", "no. ref", "ref",
        "rekening", "rek.", "va ", "virtual account", "id transaksi", "order id", "invoice", "telp", "hp"
    ]

    private static let merchantLabelPrefixes = [
        "nama merchant", "merchant", "nama penerima", "penerima", "kepada", "bayar ke",
        "tujuan", "outlet", "toko", "penjual", "pembayaran ke", "kirim ke", "ke:"
    ]

    private static let headerBoilerplate = [
        "transaksi berhasil", "pembayaran berhasil", "transfer berhasil", "berhasil",
        "struk", "bukti transfer", "bukti pembayaran", "receipt", "detail transaksi",
        "rincian transaksi", "m-bca", "mybca", "bca mobile", "livin", "bank mandiri",
        "mandiri", "gopay", "gojek", "ovo", "dana", "shopeepay", "qris", "bni", "bri",
        "terima kasih", "thank you", "lunas", "sukses", "status", "metode pembayaran",
        "sumber dana", "tanggal", "waktu", "nominal", "total", "jumlah", "biaya admin",
        "catatan", "referensi", "no referensi", "id transaksi", "rp"
    ]

    public static func parse(lines rawLines: [String], fallbackDate: LocalDate? = nil) -> ParsedReceiptOCR {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return ParsedReceiptOCR(amount: nil, date: fallbackDate, merchant: nil, detectedSourceApp: nil, rawLineCount: 0)
        }

        let joinedLower = lines.joined(separator: "\n").lowercased()
        let sourceApp = detectSourceApp(joinedLower)
        let amount = extractAmount(lines: lines)
        let date = extractDate(lines: lines) ?? fallbackDate
        let merchant = extractMerchant(lines: lines)

        return ParsedReceiptOCR(
            amount: amount,
            date: date,
            merchant: merchant,
            detectedSourceApp: sourceApp,
            suggestedType: .expense,
            rawLineCount: lines.count
        )
    }

    public static func parse(text: String, fallbackDate: LocalDate? = nil) -> ParsedReceiptOCR {
        let lines = text.components(separatedBy: .newlines)
        return parse(lines: lines, fallbackDate: fallbackDate)
    }

    // MARK: - Source App Detection

    private static func detectSourceApp(_ textLower: String) -> String? {
        if textLower.contains("m-bca") || textLower.contains("mybca") || textLower.contains("bca mobile") || textLower.contains("bank bca") || textLower.contains("m-transfer") {
            return "BCA"
        }
        if textLower.contains("livin") || textLower.contains("bank mandiri") || textLower.contains("mandiri") {
            return "Mandiri"
        }
        if textLower.contains("gopay") || textLower.contains("gojek") {
            return "GoPay"
        }
        if textLower.contains("ovo cash") || textLower.contains("ovo ") || textLower.hasPrefix("ovo") || textLower.contains("\novo") {
            return "OVO"
        }
        if textLower.contains("dana") && (textLower.contains("transaksi") || textLower.contains("bayar") || textLower.contains("kirim") || textLower.contains("saldo")) {
            return "DANA"
        }
        if textLower.contains("shopeepay") {
            return "ShopeePay"
        }
        if textLower.contains("qris") {
            return "QRIS"
        }
        return nil
    }

    // MARK: - Amount Extraction

    private static func extractAmount(lines: [String]) -> Int64? {
        struct ScoredAmount {
            let value: Int64
            let score: Int
            let lineIndex: Int
        }

        var candidates: [ScoredAmount] = []

        for idx in lines.indices {
            let line = lines[idx]
            let lower = line.lowercased()

            // Skip lines that are clearly noise (account numbers, balance, tax, admin fee, ref IDs)
            let isExplicitTotal = amountPriorityKeywords.contains { lower.contains($0) }
            let isNoise = !isExplicitTotal && amountNoiseKeywords.contains { lower.contains($0) }
            if isNoise { continue }

            // Check amounts on this line
            let extracted = extractAmountsOnLine(line)
            for amt in extracted {
                var score = 10
                if lower.contains("rp") || lower.contains("idr") { score += 20 }
                if isExplicitTotal {
                    if lower.contains("total bayar") || lower.contains("grand total") || lower.contains("total pembayaran") || lower.contains("total transaksi") {
                        score += 60
                    } else if lower.contains("total") || lower.contains("nominal") || lower.contains("jumlah") {
                        score += 45
                    } else {
                        score += 30
                    }
                }
                // Check if PREVIOUS line was a label like "Total Bayar" or "Nominal" and this line is the standalone Rp value
                if idx > 0 {
                    let prevLower = lines[idx - 1].lowercased()
                    if amountPriorityKeywords.contains(where: { prevLower.contains($0) }) && extractAmountsOnLine(lines[idx - 1]).isEmpty {
                        score += 55
                    } else if prevLower.contains("transaksi berhasil") || prevLower.contains("pembayaran berhasil") || prevLower.contains("transfer berhasil") {
                        score += 35
                    }
                }
                candidates.append(ScoredAmount(value: amt, score: score, lineIndex: idx))
            }
        }

        guard !candidates.isEmpty else { return nil }
        let best = candidates.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.lineIndex < rhs.lineIndex
        }
        return best?.value
    }

    private static func extractAmountsOnLine(_ line: String) -> [Int64] {
        // Match Indonesian currency numbers: optional Rp/IDR + grouped digits (1.500.000 or 1,500,000 or 50000) + optional ,00 / .00
        let pattern = #"(?i)(?:(?:rp\.?|idr)\s*-?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?:[.,](00|0))?(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))

        var results: [Int64] = []
        for match in matches {
            guard let fullRange = Range(match.range, in: line),
                  let numRange = Range(match.range(at: 1), in: line) else { continue }
            let fullMatch = String(line[fullRange])
            let numStr = String(line[numRange])

            // Filter out obvious years (2020..2035) unless prefixed by Rp/IDR
            let hasCurrencyPrefix = fullMatch.lowercased().contains("rp") || fullMatch.lowercased().contains("idr")
            let digitsOnly = numStr.filter(\.isNumber)
            guard let val = Int64(digitsOnly), val >= 500, val <= Money.maxAllowedRupiah else { continue }

            if !hasCurrencyPrefix && (2015...2039).contains(val) && !numStr.contains(".") && !numStr.contains(",") {
                continue
            }
            // Reject raw ungrouped long numbers >= 8 digits (likely phone/VA/reference IDs) unless prefixed by Rp/IDR
            if !hasCurrencyPrefix && !numStr.contains(".") && !numStr.contains(",") && digitsOnly.count >= 8 {
                continue
            }
            results.append(val)
        }
        return results
    }

    // MARK: - Date Extraction

    private static func extractDate(lines: [String]) -> LocalDate? {
        for line in lines {
            // 1. YYYY-MM-DD
            if let m = firstMatch(#"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b"#, in: line),
               let y = Int(sub(line, m.range(at: 1))),
               let mo = Int(sub(line, m.range(at: 2))),
               let d = Int(sub(line, m.range(at: 3))),
               let parsed = LocalDate(year: y, month: mo, day: d) {
                return parsed
            }

            // 2. DD MMM YYYY or DD MMMM YYYY (e.g. 26 Nov 2026, 05 Agustus 2026)
            if let m = firstMatch(#"(?i)\b(\d{1,2})\s+(januari|january|jan|februari|february|feb|peb|maret|march|mar|april|apr|mei|may|juni|june|jun|juli|july|jul|agustus|august|agu|agt|aug|september|sept|sep|oktober|october|okt|oct|november|nov|desember|december|des|dec)\s+(20\d{2}|\d{2})\b"#, in: line),
               let d = Int(sub(line, m.range(at: 1))),
               let mo = monthMap[sub(line, m.range(at: 2)).lowercased()],
               let yRaw = Int(sub(line, m.range(at: 3))) {
                let y = yRaw < 100 ? (2000 + yRaw) : yRaw
                if let parsed = LocalDate(year: y, month: mo, day: d) {
                    return parsed
                }
            }

            // 3. DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY (and 2-digit year DD/MM/YY)
            if let m = firstMatch(#"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](20\d{2}|\d{2})\b"#, in: line),
               let d = Int(sub(line, m.range(at: 1))),
               let mo = Int(sub(line, m.range(at: 2))),
               let yRaw = Int(sub(line, m.range(at: 3))) {
                let y = yRaw < 100 ? (2000 + yRaw) : yRaw
                if let parsed = LocalDate(year: y, month: mo, day: d) {
                    return parsed
                }
            }
        }
        return nil
    }

    // MARK: - Merchant Extraction

    private static func extractMerchant(lines: [String]) -> String? {
        // Pass 1: Explicit labeled merchant/recipient field ("Merchant: Kopi Kenangan" or label on line i, value on line i+1)
        for idx in lines.indices {
            let line = lines[idx]
            let lower = line.lowercased()
            for label in merchantLabelPrefixes {
                if lower.hasPrefix(label) {
                    let remainder = String(line.dropFirst(label.count))
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")))
                    if isCleanMerchantName(remainder) {
                        return cleanMerchant(remainder)
                    }
                    // Otherwise take the next line
                    if idx + 1 < lines.count, isCleanMerchantName(lines[idx + 1]) {
                        return cleanMerchant(lines[idx + 1])
                    }
                }
            }
        }

        // Pass 2: Retail receipt top non-boilerplate line (e.g. "INDOMARET SUDIRMAN", "KOPI KENANGAN")
        for line in lines.prefix(6) {
            if isCleanMerchantName(line) {
                return cleanMerchant(line)
            }
        }

        return nil
    }

    private static func isCleanMerchantName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 && trimmed.count <= 60 else { return false }
        let lower = trimmed.lowercased()
        // Reject lines that are pure currency, dates, digits, or boilerplate headers
        if lower.hasPrefix("rp") || lower.hasPrefix("idr") { return false }
        if headerBoilerplate.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ":") }) {
            return false
        }
        let letterCount = trimmed.filter(\.isLetter).count
        let digitCount = trimmed.filter(\.isNumber).count
        guard letterCount >= 3 else { return false }
        // Reject mostly-numeric strings like reference numbers or masked account numbers
        if digitCount > letterCount { return false }
        return true
    }

    private static func cleanMerchant(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-•*")))
        return trimmed.count > 50 ? String(trimmed.prefix(50)) : trimmed
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func sub(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }
}
