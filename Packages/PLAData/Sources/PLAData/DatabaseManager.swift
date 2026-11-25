import Foundation
import GRDB
import PLACore

public enum PLADatabaseError: Error, LocalizedError {
    case migrationFailedRestoredBackup(underlying: Error, backupURL: URL?)
    case invalidStoredIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .migrationFailedRestoredBackup(let err, _):
            return "Migrasi database gagal (\(err.localizedDescription)). Salinan database sebelum migrasi telah dipulihkan."
        case .invalidStoredIdentifier(let raw):
            return "Data ID tidak valid di database: \(raw)"
        }
    }
}

/// Manages GRDB SQLite database lifecycle, Data Protection, forward-only migrations, and pre-migration safety backups (PRD §11.5 & §13.4).
public final class DatabaseManager: @unchecked Sendable {
    public static let currentSchemaVersion = 1

    public let dbWriter: any DatabaseWriter
    public let databaseURL: URL?

    public init(inMemory: Bool = false, pathURL: URL? = nil, appVersion: String = "1.0.0") throws {
        if inMemory {
            let queue = try DatabaseQueue(configuration: Self.makeConfiguration())
            self.dbWriter = queue
            self.databaseURL = nil
            try Self.migrator(appVersion: appVersion).migrate(queue)
        } else {
            let fileURL = try pathURL ?? Self.defaultDatabaseURL()
            let folderURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            Self.applyDataProtection(to: folderURL)

            let migrator = Self.migrator(appVersion: appVersion)
            let preMigrationBackup = try Self.createPreMigrationBackupIfNeeded(
                at: fileURL,
                migrator: migrator
            )

            do {
                let pool = try DatabasePool(path: fileURL.path, configuration: Self.makeConfiguration())
                try migrator.migrate(pool)
                Self.applyDataProtection(to: fileURL)
                self.dbWriter = pool
                self.databaseURL = fileURL
            } catch {
                // PRD §11.5: Restore backup copy automatically if migration fails
                if let backup = preMigrationBackup, FileManager.default.fileExists(atPath: backup.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                    try? FileManager.default.copyItem(at: backup, to: fileURL)
                }
                throw PLADatabaseError.migrationFailedRestoredBackup(
                    underlying: error,
                    backupURL: preMigrationBackup
                )
            }
        }
    }

    public static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("PLA", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pla.sqlite")
    }

    public static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // Enforce foreign key checks and sane busy timeout
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return config
    }

    private static func applyDataProtection(to url: URL) {
        #if os(iOS)
        // PRD §13.4 & V-17: completeUntilFirstUserAuthentication allows BGAppRefreshTask reads while locked
        // Setting on the containing directory ensures -wal and -shm files inherit the same protection class.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    /// Creates `pla_backup_before_vX.sqlite` if an existing DB has pending migrations, keeping at most 2 backups (PRD §11.5).
    private static func createPreMigrationBackupIfNeeded(
        at fileURL: URL,
        migrator: DatabaseMigrator
    ) throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let needsBackup: Bool = try {
            let probeQueue = try DatabaseQueue(path: fileURL.path, configuration: makeConfiguration())
            return try probeQueue.read { db in
                let hasMigrationTable = try db.tableExists("grdb_migrations")
                if !hasMigrationTable { return false }
                return try !migrator.hasCompletedMigrations(db)
            }
        }()

        guard needsBackup else { return nil }

        let dir = fileURL.deletingLastPathComponent()
        let backupName = "pla_backup_before_v\(currentSchemaVersion)_\(Int(Date().timeIntervalSince1970)).sqlite"
        let backupURL = dir.appendingPathComponent(backupName)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        applyDataProtection(to: backupURL)

        // Retain at most 2 latest pre-migration backups
        let existingBackups = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { $0.lastPathComponent.hasPrefix("pla_backup_before_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []

        if existingBackups.count > 2 {
            for old in existingBackups.dropFirst(2) {
                try? FileManager.default.removeItem(at: old)
            }
        }
        return backupURL
    }

    /// Forward-only schema migrations (PRD §11.3, §11.4, §11.5). Released migrations must never be modified.
    public static func migrator(appVersion: String = "1.0.0") -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_mvp") { db in
            // Metadata table
            try db.create(table: "app_metadata") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            // 1. categories
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("scope", .integer).notNull()
                t.column("iconName", .text).notNull()
                t.column("colorToken", .text).notNull()
                t.column("isSystem", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            // 2. recurrence_rules
            try db.create(table: "recurrence_rules") { t in
                t.column("id", .text).primaryKey()
                t.column("frequency", .integer).notNull()
                t.column("interval", .integer).notNull().defaults(to: 1)
                t.column("weekdaysMask", .integer)
                t.column("anchorDayOfMonth", .integer)
                t.column("anchorMonth", .integer)
                t.column("endDateLocal", .text)
                t.column("maxOccurrences", .integer)
            }

            // 3. accounts
            try db.create(table: "accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .integer).notNull()
                t.column("initialBalance", .integer).notNull().defaults(to: 0)
                t.column("iconName", .text).notNull()
                t.column("colorToken", .text).notNull()
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .double).notNull()
            }

            // 4. tasks
            try db.create(table: "tasks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("dueDateLocal", .text)
                t.column("dueTimeMinutes", .integer)
                t.column("priority", .integer).notNull().defaults(to: 1)
                t.column("status", .integer).notNull().defaults(to: 0)
                t.column("categoryId", .text).references("categories", onDelete: .setNull)
                t.column("recurrenceRuleId", .text).references("recurrence_rules", onDelete: .setNull)
                t.column("completedAt", .double)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // 5. bills
            try db.create(table: "bills") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("amount", .integer).notNull()
                t.column("isVariableAmount", .boolean).notNull().defaults(to: false)
                t.column("nextDueDateLocal", .text).notNull()
                t.column("recurrenceRuleId", .text).notNull().references("recurrence_rules", onDelete: .restrict)
                t.column("defaultAccountId", .text).notNull().references("accounts", onDelete: .restrict)
                t.column("categoryId", .text).notNull().references("categories", onDelete: .restrict)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("lastPaidDateLocal", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // 6. reminders
            try db.create(table: "reminders") { t in
                t.column("id", .text).primaryKey()
                t.column("ownerType", .integer).notNull()
                t.column("ownerId", .text).notNull()
                t.column("triggerType", .integer).notNull().defaults(to: 0)
                t.column("offsetMinutes", .integer)
                t.column("fireDateLocal", .text).notNull()
                t.column("soundName", .text).notNull()
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("lastScheduledAt", .double)
            }

            // 7. transactions
            try db.create(table: "transactions") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .integer).notNull()
                t.column("amount", .integer).notNull()
                t.column("accountId", .text).notNull().references("accounts", onDelete: .restrict)
                t.column("destinationAccountId", .text).references("accounts", onDelete: .restrict)
                t.column("categoryId", .text).references("categories", onDelete: .restrict)
                t.column("billId", .text).references("bills", onDelete: .setNull)
                t.column("dateLocal", .text).notNull()
                t.column("note", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // 8. budgets
            try db.create(table: "budgets") { t in
                t.column("id", .text).primaryKey()
                t.column("categoryId", .text).references("categories", onDelete: .setNull)
                t.column("amount", .integer).notNull()
                t.column("effectiveFromMonth", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // 9. insights
            try db.create(table: "insights") { t in
                t.column("id", .text).primaryKey()
                t.column("ruleCode", .text).notNull()
                t.column("periodKey", .text).notNull()
                t.column("subjectId", .text)
                t.column("severity", .integer).notNull()
                t.column("dismissedAt", .double)
                t.column("feedback", .integer)
                t.column("generatedAt", .double).notNull()
            }

            // Required indices (PRD §11.4)
            try db.create(index: "idx_tasks_status_due", on: "tasks", columns: ["status", "dueDateLocal"])
            try db.create(index: "idx_transactions_date_type", on: "transactions", columns: ["dateLocal", "type"])
            try db.create(index: "idx_transactions_account", on: "transactions", columns: ["accountId"])
            try db.create(index: "idx_transactions_dest_account", on: "transactions", columns: ["destinationAccountId"])
            try db.create(index: "idx_reminders_fire", on: "reminders", columns: ["isEnabled", "fireDateLocal"])
            try db.create(index: "idx_reminders_owner", on: "reminders", columns: ["ownerId"])
            try db.create(index: "idx_bills_active_due", on: "bills", columns: ["isActive", "nextDueDateLocal"])
            try db.create(index: "idx_insights_dedup", on: "insights", columns: ["ruleCode", "periodKey", "subjectId"], unique: true)

            try db.execute(
                sql: "INSERT OR REPLACE INTO app_metadata (key, value) VALUES (?, ?), (?, ?)",
                arguments: ["schemaVersion", "\(currentSchemaVersion)", "appVersion", appVersion]
            )
        }

        return migrator
    }
}
