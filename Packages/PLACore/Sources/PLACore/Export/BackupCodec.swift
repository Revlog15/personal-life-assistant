import Foundation

public struct BackupPayload: Equatable, Codable, Sendable {
    public var tasks: [PLATask]
    public var reminders: [Reminder]
    public var recurrenceRules: [RecurrenceRule]
    public var accounts: [Account]
    public var categories: [Category]
    public var transactions: [PLATransaction]
    public var budgets: [Budget]
    public var bills: [Bill]
    public var insights: [InsightRecord]
    public var settings: UserSettings

    public init(
        tasks: [PLATask] = [],
        reminders: [Reminder] = [],
        recurrenceRules: [RecurrenceRule] = [],
        accounts: [Account] = [],
        categories: [Category] = [],
        transactions: [PLATransaction] = [],
        budgets: [Budget] = [],
        bills: [Bill] = [],
        insights: [InsightRecord] = [],
        settings: UserSettings = .default
    ) {
        self.tasks = tasks
        self.reminders = reminders
        self.recurrenceRules = recurrenceRules
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.budgets = budgets
        self.bills = bills
        self.insights = insights
        self.settings = settings
    }
}

public struct BackupEnvelope: Equatable, Codable, Sendable {
    public var exportSchemaVersion: Int
    public var exportedAt: Date
    public var sha256: String
    public var payload: BackupPayload

    public init(
        exportSchemaVersion: Int,
        exportedAt: Date,
        sha256: String,
        payload: BackupPayload
    ) {
        self.exportSchemaVersion = exportSchemaVersion
        self.exportedAt = exportedAt
        self.sha256 = sha256
        self.payload = payload
    }
}

public struct BackupPreview: Equatable, Sendable {
    public let exportSchemaVersion: Int
    public let exportedAt: Date
    public let taskCount: Int
    public let transactionCount: Int
    public let billCount: Int
    public let accountCount: Int
    public let budgetCount: Int
    public let totalLiquidWealth: Int64
    public let payload: BackupPayload
}

public enum BackupCodecError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedFutureVersion(found: Int, maxSupported: Int)
    case checksumMismatch
    case invalidSchemaVersion

    public var userMessage: String {
        switch self {
        case .invalidJSON:
            return "File backup rusak atau bukan format JSON PLA yang valid."
        case .unsupportedFutureVersion(let found, let maxSupported):
            return "Versi backup (\(found)) lebih baru dari aplikasi ini (maks. \(maxSupported)). Perbarui aplikasi terlebih dahulu."
        case .checksumMismatch:
            return "Checksum SHA-256 tidak cocok. File backup mungkin telah rusak atau diubah."
        case .invalidSchemaVersion:
            return "Versi skema backup tidak valid."
        }
    }
}

/// JSON backup encoder/decoder with SHA-256 integrity verification and schema versioning (PRD F-13 / AC-13.1..13.4).
public enum BackupCodec {
    public static let currentSchemaVersion = 1

    public static func encode(payload: BackupPayload, exportedAt: Date) throws -> Data {
        let canonicalPayload = try canonicalEncoder().encode(payload)
        let checksum = SHA256.hexDigest(canonicalPayload)
        let envelope = BackupEnvelope(
            exportSchemaVersion: currentSchemaVersion,
            exportedAt: exportedAt,
            sha256: checksum,
            payload: payload
        )
        let encoder = prettyEncoder()
        return try encoder.encode(envelope)
    }

    public static func decodeAndValidate(data: Data) -> Result<BackupPreview, BackupCodecError> {
        let decoder = makeDecoder()
        guard let envelope = try? decoder.decode(BackupEnvelope.self, from: data) else {
            return .failure(.invalidJSON)
        }
        guard envelope.exportSchemaVersion >= 1 else {
            return .failure(.invalidSchemaVersion)
        }
        if envelope.exportSchemaVersion > currentSchemaVersion {
            return .failure(.unsupportedFutureVersion(
                found: envelope.exportSchemaVersion,
                maxSupported: currentSchemaVersion
            ))
        }

        guard let canonicalPayload = try? canonicalEncoder().encode(envelope.payload) else {
            return .failure(.invalidJSON)
        }
        let expectedChecksum = SHA256.hexDigest(canonicalPayload)
        guard expectedChecksum.lowercased() == envelope.sha256.lowercased() else {
            return .failure(.checksumMismatch)
        }

        let wealth = AccountBalanceCalculator.totalLiquidWealth(
            accounts: envelope.payload.accounts,
            transactions: envelope.payload.transactions
        )

        let preview = BackupPreview(
            exportSchemaVersion: envelope.exportSchemaVersion,
            exportedAt: envelope.exportedAt,
            taskCount: envelope.payload.tasks.count,
            transactionCount: envelope.payload.transactions.count,
            billCount: envelope.payload.bills.count,
            accountCount: envelope.payload.accounts.count,
            budgetCount: envelope.payload.budgets.count,
            totalLiquidWealth: wealth,
            payload: envelope.payload
        )
        return .success(preview)
    }

    public static func suggestedFilename(at dateTime: LocalDateTime) -> String {
        let dateDigits = dateTime.date.isoString.replacingOccurrences(of: "-", with: "")
        let h = dateTime.hour < 10 ? "0\(dateTime.hour)" : "\(dateTime.hour)"
        let m = dateTime.minute < 10 ? "0\(dateTime.minute)" : "\(dateTime.minute)"
        return "pla-backup-\(dateDigits)-\(h)\(m).json"
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
