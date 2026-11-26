import Foundation

public struct BackupPayload: Equatable, Codable, Sendable {
    public var tasks: [PLATask]
    public var reminders: [Reminder]
    public var recurrenceRules: [RecurrenceRule]
    public var accounts: [Account]
    public var categories: [PLACategory]
    public var transactions: [PLATransaction]
    public var budgets: [Budget]
    public var bills: [Bill]
    public var insights: [InsightRecord]
    public var savingsGoals: [SavingsGoal]
    public var settings: UserSettings

    public init(
        tasks: [PLATask] = [],
        reminders: [Reminder] = [],
        recurrenceRules: [RecurrenceRule] = [],
        accounts: [Account] = [],
        categories: [PLACategory] = [],
        transactions: [PLATransaction] = [],
        budgets: [Budget] = [],
        bills: [Bill] = [],
        insights: [InsightRecord] = [],
        savingsGoals: [SavingsGoal] = [],
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
        self.savingsGoals = savingsGoals
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case tasks, reminders, recurrenceRules, accounts, categories, transactions,
             budgets, bills, insights, savingsGoals, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tasks = try c.decodeIfPresent([PLATask].self, forKey: .tasks) ?? []
        self.reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        self.recurrenceRules = try c.decodeIfPresent([RecurrenceRule].self, forKey: .recurrenceRules) ?? []
        self.accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        self.categories = try c.decodeIfPresent([PLACategory].self, forKey: .categories) ?? []
        self.transactions = try c.decodeIfPresent([PLATransaction].self, forKey: .transactions) ?? []
        self.budgets = try c.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        self.bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        self.insights = try c.decodeIfPresent([InsightRecord].self, forKey: .insights) ?? []
        self.savingsGoals = try c.decodeIfPresent([SavingsGoal].self, forKey: .savingsGoals) ?? []
        self.settings = try c.decodeIfPresent(UserSettings.self, forKey: .settings) ?? .default
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
    public let savingsGoalCount: Int
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

/// JSON backup encoder/decoder with SHA-256 integrity verification and v1->v2 backwards-compatible migration (PRD F-13 & §11.5).
public enum BackupCodec {
    public static let currentSchemaVersion = 2

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

        let checksumValid: Bool
        if envelope.exportSchemaVersion == 1 {
            // Backwards-compatible v1 checksum verification over exact v1 payload JSON projection
            checksumValid = verifyLegacyV1Checksum(rawData: data, expectedHex: envelope.sha256)
        } else {
            guard let canonicalPayload = try? canonicalEncoder().encode(envelope.payload) else {
                return .failure(.invalidJSON)
            }
            checksumValid = SHA256.hexDigest(canonicalPayload).lowercased() == envelope.sha256.lowercased()
        }

        guard checksumValid else {
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
            savingsGoalCount: envelope.payload.savingsGoals.count,
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

    /// Re-serializes the raw `"payload"` JSON dictionary from a v1 export in sorted-key canonical form to verify its SHA-256.
    private static func verifyLegacyV1Checksum(rawData: Data, expectedHex: String) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let rawPayload = root["payload"],
              JSONSerialization.isValidJSONObject(rawPayload),
              let canonical = try? JSONSerialization.data(
                withJSONObject: rawPayload,
                options: [.sortedKeys]
              ) else {
            return false
        }
        return SHA256.hexDigest(canonical).lowercased() == expectedHex.lowercased()
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
