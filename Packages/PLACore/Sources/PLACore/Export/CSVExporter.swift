import Foundation

/// UTF-8 BOM CSV exporter compatible with Excel Windows & Numbers (PRD AC-13.2).
public enum CSVExporter {
    public static let headerRow = "Tanggal,Tipe,Nominal,Kategori,Akun,Akun Tujuan,Catatan,Status Tagihan"

    public static func exportTransactions(
        transactions: [PLATransaction],
        accounts: [Account],
        categories: [Category],
        from startDate: LocalDate? = nil,
        to endDate: LocalDate? = nil
    ) -> Data {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        let filtered = transactions
            .filter { tx in
                if let s = startDate, tx.dateLocal < s { return false }
                if let e = endDate, tx.dateLocal > e { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.dateLocal != rhs.dateLocal { return lhs.dateLocal > rhs.dateLocal }
                return lhs.createdAt > rhs.createdAt
            }

        var lines: [String] = [headerRow]
        lines.reserveCapacity(filtered.count + 1)

        for tx in filtered {
            let typeLabel: String
            switch tx.type {
            case .expense: typeLabel = "Pengeluaran"
            case .income: typeLabel = "Pemasukan"
            case .transfer: typeLabel = "Transfer"
            }
            let categoryName = tx.categoryId.flatMap { categoryMap[$0] } ?? ""
            let accountName = accountMap[tx.accountId] ?? ""
            let destAccountName = tx.destinationAccountId.flatMap { accountMap[$0] } ?? ""
            let note = tx.note ?? ""
            let billStatus = tx.billId != nil ? "Tagihan Lunas" : ""

            let fields = [
                tx.dateLocal.isoString,
                typeLabel,
                String(tx.amount),
                categoryName,
                accountName,
                destAccountName,
                note,
                billStatus
            ].map(escapeCSVField)

            lines.append(fields.joined(separator: ","))
        }

        // Prefix UTF-8 BOM (EF BB BF) so Excel on Windows detects UTF-8 automatically
        let content = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        return Data(content.utf8)
    }

    private static func escapeCSVField(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        if !needsQuoting {
            return field
        }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
