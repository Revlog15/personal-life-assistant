import Foundation

/// Suggests transaction categories from historical notes (AC-08.2 & §10.1 cold start).
public enum CategorySuggester {
    public static func suggestCategories(
        forNote note: String,
        scope: CategoryScope,
        transactions: [PLATransaction],
        categories: [Category],
        limit: Int = 3
    ) -> [Category] {
        let activeCategories = categories.filter { $0.scope == scope && !$0.isArchived }
        let categoryById = Dictionary(uniqueKeysWithValues: activeCategories.map { ($0.id, $0) })

        let targetType: TransactionType = (scope == .income) ? .income : .expense
        let scopedTx = transactions.filter { $0.type == targetType && $0.categoryId != nil }

        let tokens = tokenize(note)
        if !tokens.isEmpty {
            // Count matching historical transactions per category where any token matches (min >= 2 matches per AC-08.2)
            var matchCounts: [UUID: Int] = [:]
            for tx in scopedTx {
                guard let catId = tx.categoryId, categoryById[catId] != nil,
                      let txNote = tx.note else { continue }
                let txTokens = tokenize(txNote)
                let overlap = tokens.contains { t in
                    txTokens.contains { hist in hist == t || hist.hasPrefix(t) || t.hasPrefix(hist) }
                }
                if overlap {
                    matchCounts[catId, default: 0] += 1
                }
            }

            let qualified = matchCounts
                .filter { $0.value >= 2 }
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return (categoryById[lhs.key]?.sortOrder ?? 0) < (categoryById[rhs.key]?.sortOrder ?? 0)
                }
                .compactMap { categoryById[$0.key] }

            if !qualified.isEmpty {
                return Array(qualified.prefix(limit))
            }
        }

        // Cold-start fallback (§10.1): top 3 most frequently used categories in this scope
        var freqCounts: [UUID: Int] = [:]
        for tx in scopedTx {
            if let catId = tx.categoryId, categoryById[catId] != nil {
                freqCounts[catId, default: 0] += 1
            }
        }
        let frequent = freqCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (categoryById[lhs.key]?.sortOrder ?? 0) < (categoryById[rhs.key]?.sortOrder ?? 0)
            }
            .compactMap { categoryById[$0.key] }

        return Array(frequent.prefix(limit))
    }

    internal static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var tokens: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                if current.count >= 2 { tokens.append(current) }
                current = ""
            }
        }
        if current.count >= 2 { tokens.append(current) }
        return tokens
    }
}
