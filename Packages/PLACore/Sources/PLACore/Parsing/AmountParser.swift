import Foundation

public enum AmountParseError: Error, Equatable, Sendable {
    case empty
    case negativeOrZero
    case decimalsNotAllowed
    case invalidFormat
    case exceedsMaximum

    public var userMessage: String {
        switch self {
        case .empty:
            return "Nominal wajib diisi."
        case .negativeOrZero:
            return "Nominal harus lebih besar dari Rp0."
        case .decimalsNotAllowed:
            return "Masukkan angka bulat tanpa sen."
        case .invalidFormat:
            return "Format nominal tidak valid."
        case .exceedsMaximum:
            return "Nominal maksimal adalah Rp999.999.999.999."
        }
    }
}

/// Deterministic Indonesian Rupiah integer parser (PRD §12).
public enum AmountParser {
    public static func parse(_ rawInput: String) -> Result<Money, AmountParseError> {
        var cleaned = rawInput
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return .failure(.empty)
        }

        // Strip leading currency prefix ("Rp", "Rp.", "IDR") case-insensitively
        let lower = cleaned.lowercased()
        if lower.hasPrefix("rp.") {
            cleaned = String(cleaned.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("rp") {
            cleaned = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("idr") {
            cleaned = String(cleaned.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.isEmpty {
            return .failure(.empty)
        }

        if cleaned.hasPrefix("-") {
            return .failure(.negativeOrZero)
        }
        if cleaned.hasPrefix("+") {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove spaces between currency and digits or internal spaces if purely numeric groups
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty {
            return .failure(.empty)
        }

        // Reject any character other than ASCII digits, '.', ','
        for scalar in cleaned.unicodeScalars {
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            let isSep = scalar == "." || scalar == ","
            if !isDigit && !isSep {
                return .failure(.invalidFormat)
            }
        }

        let hasDot = cleaned.contains(".")
        let hasComma = cleaned.contains(",")

        let digitsOnly: String
        if hasDot && hasComma {
            // Mixed separators like "1.500,50" or "1,500.50" denote a decimal fraction
            return .failure(.decimalsNotAllowed)
        } else if hasDot || hasComma {
            let sep: Character = hasDot ? "." : ","
            let parts = cleaned.split(separator: sep, omittingEmptySubsequences: false)
            guard parts.count >= 2, !parts.contains(where: { $0.isEmpty }) else {
                return .failure(.invalidFormat)
            }
            // Valid thousands grouping: first group 1..3 digits, every subsequent group strictly 3 digits.
            let isValidThousandsGrouping =
                (1...3).contains(parts[0].count) &&
                parts.dropFirst().allSatisfy { $0.count == 3 }

            if isValidThousandsGrouping {
                digitsOnly = parts.joined()
            } else if parts.count == 2 && (1...2).contains(parts[1].count) {
                // Classic decimal fraction such as 50000,75 or 50000.50 or 10,5
                return .failure(.decimalsNotAllowed)
            } else if parts.count == 2 && parts[0].count >= 4 {
                // e.g. 50000,123 or 50000.000
                return .failure(.decimalsNotAllowed)
            } else {
                return .failure(.invalidFormat)
            }
        } else {
            digitsOnly = cleaned
        }

        // Strip leading zeros safely
        let trimmedZeros = digitsOnly.drop(while: { $0 == "0" })
        if trimmedZeros.isEmpty {
            return .failure(.negativeOrZero)
        }

        // Prevent Int64 overflow before parsing
        if trimmedZeros.count > 12 {
            return .failure(.exceedsMaximum)
        }

        guard let value = Int64(trimmedZeros) else {
            return .failure(.exceedsMaximum)
        }

        if value <= 0 {
            return .failure(.negativeOrZero)
        }
        if value > Money.maxAllowedRupiah {
            return .failure(.exceedsMaximum)
        }

        return .success(Money(value))
    }
}
