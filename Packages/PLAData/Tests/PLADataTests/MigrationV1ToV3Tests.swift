import Foundation
import XCTest
import GRDB
import PLACore
@testable import PLAData

/// Verifies PRD §11.5 & Fase 5 DoD: authentic v1_initial_mvp disk DB upgrades cleanly through v2 & v3 with 0 data loss and automatic pre-migration backup.
final class MigrationV1ToV3Tests: XCTestCase {
    func testUpgradeFromV1FixtureToV3CreatesBackupAndPreservesAllRecordsAndBalances() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla-v1-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("pla.sqlite")
        let accId = UUID().uuidString
        let catId = UUID().uuidString
        let ruleId = UUID().uuidString
        let billId = UUID().uuidString
        let taskId = UUID().uuidString
        let txId = UUID().uuidString
        let nowTs = Date().timeIntervalSince1970

        // 1. Build authentic v1.0.0 SQLite database on disk (only v1_initial_mvp migration)
        do {
            let v1Queue = try DatabaseQueue(path: dbURL.path, configuration: DatabaseManager.makeConfiguration())
            try DatabaseManager.migratorV1OnlyForTesting().migrate(v1Queue)
            try v1Queue.write { db in
                try db.execute(
                    sql: "INSERT INTO categories (id, name, scope, iconName, colorToken, isSystem, isArchived, sortOrder) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [catId, "Makan & Minum", 0, "fork.knife", "orange", true, false, 1]
                )
                try db.execute(
                    sql: "INSERT INTO accounts (id, name, type, initialBalance, iconName, colorToken, isDefault, isArchived, sortOrder, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [accId, "BCA", 1, 5_000_000, "building.columns.fill", "blue", true, false, 1, nowTs]
                )
                try db.execute(
                    sql: "INSERT INTO recurrence_rules (id, frequency, interval, anchorDayOfMonth) VALUES (?, ?, ?, ?)",
                    arguments: [ruleId, 2, 1, 15]
                )
                try db.execute(
                    sql: "INSERT INTO bills (id, name, amount, isVariableAmount, nextDueDateLocal, recurrenceRuleId, defaultAccountId, categoryId, isActive, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [billId, "Internet", 350_000, false, "2026-12-15", ruleId, accId, catId, true, nowTs, nowTs]
                )
                try db.execute(
                    sql: "INSERT INTO tasks (id, title, dueDateLocal, priority, status, recurrenceRuleId, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [taskId, "Tugas v1", "2026-12-01", 2, 0, ruleId, nowTs, nowTs]
                )
                try db.execute(
                    sql: "INSERT INTO transactions (id, type, amount, accountId, categoryId, dateLocal, note, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [txId, 0, 250_000, accId, catId, "2026-11-20", "Kopi v1", nowTs, nowTs]
                )
            }
        }

        // 2. Open with v2.0.0 DatabaseManager (triggers pre-migration backup + v2_savings_goal + v3_post_mvp_recurrence_and_trials)
        let upgradedMgr = try DatabaseManager(inMemory: false, pathURL: dbURL, appVersion: "2.0.0")
        let store = GRDBStore(dbManager: upgradedMgr)

        // Verify pre-migration safety backup file was created automatically (PRD §11.5)
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(
            files.contains { $0.hasPrefix("pla_backup_before_v") && $0.hasSuffix(".sqlite") },
            "Expected automatic pre-migration SQLite backup in \(files)"
        )

        // Verify 0 data loss & exact balance preserved (SC-09)
        let accounts = try store.fetchAllAccounts()
        let txs = try store.fetchAllTransactions()
        let tasks = try store.fetchAllTasks()
        let bills = try store.fetchAllBills()
        let rules = try store.fetchAllRecurrenceRules()

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(AccountBalanceCalculator.totalLiquidWealth(accounts: accounts, transactions: txs), 4_750_000)
        XCTAssertEqual(tasks.first?.title, "Tugas v1")
        XCTAssertEqual(bills.first?.isTrial, false)
        XCTAssertNil(bills.first?.trialEndDateLocal)
        XCTAssertEqual(rules.first?.anchorMode, .fixedSchedule)

        // Verify v2 & v3 features write & read cleanly on the upgraded DB
        let goal = SavingsGoal(
            name: "Dana Darurat",
            targetAmount: 10_000_000,
            currentAmount: 2_500_000,
            targetDateLocal: LocalDate(year: 2027, month: 6, day: 1)!,
            linkedAccountId: accounts.first?.id
        )
        try store.saveSavingsGoal(goal)
        XCTAssertEqual(try store.fetchAllSavingsGoals().first?.name, "Dana Darurat")

        let trialRule = RecurrenceRule(frequency: .daily, interval: 60, anchorMode: .fromCompletionDate)
        try store.saveRecurrenceRule(trialRule)
        XCTAssertEqual(try store.fetchAllRecurrenceRules().first { $0.id == trialRule.id }?.anchorMode, .fromCompletionDate)

        let trialBill = Bill(
            name: "Trial Cloud",
            amount: 99_000,
            nextDueDateLocal: LocalDate(year: 2026, month: 12, day: 10)!,
            recurrenceRuleId: trialRule.id,
            defaultAccountId: accounts.first!.id,
            categoryId: try store.fetchAllCategories().first!.id,
            isTrial: true,
            trialEndDateLocal: LocalDate(year: 2026, month: 12, day: 10)!
        )
        try store.saveBill(trialBill)
        let fetchedTrial = try store.fetchAllBills().first { $0.id == trialBill.id }
        XCTAssertEqual(fetchedTrial?.isTrial, true)
        XCTAssertEqual(fetchedTrial?.trialEndDateLocal, LocalDate(year: 2026, month: 12, day: 10))
    }

    /// Verifies PRD §11.5: committed anonymous static v1_initial_mvp `.sqlite` binary fixture in `Tests/PLADataTests/Fixtures/`
    /// upgrades cleanly to v3 with automatic pre-migration backup, exact row counts, and exact multi-account balances.
    func testCommittedStaticV1SQLiteFixtureMigratesCleanlyToV3() throws {
        guard let fixtureURL = Bundle.module.url(
            forResource: "pla_v1_initial_mvp",
            withExtension: "sqlite",
            subdirectory: "Fixtures"
        ) else {
            return XCTFail("Missing committed fixture Fixtures/pla_v1_initial_mvp.sqlite in test bundle")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla-static-v1-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workingDB = tempDir.appendingPathComponent("pla.sqlite")
        try FileManager.default.copyItem(at: fixtureURL, to: workingDB)

        let upgraded = try DatabaseManager(inMemory: false, pathURL: workingDB, appVersion: "2.1.0")
        let store = GRDBStore(dbManager: upgraded)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(
            files.contains { $0.hasPrefix("pla_backup_before_v") && $0.hasSuffix(".sqlite") },
            "Expected pre-migration backup from static v1 fixture in \(files)"
        )

        let accounts = try store.fetchAllAccounts()
        let transactions = try store.fetchAllTransactions()
        let tasks = try store.fetchAllTasks()
        let bills = try store.fetchAllBills()
        let budgets = try store.fetchAllBudgets()
        let insights = try store.fetchAllInsights()

        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(transactions.count, 3)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(insights.count, 1)

        // Bank Utama: 2,000,000 + 5,000,000 - 500,000 = 6,500,000
        // E-Wallet:     500,000 +   500,000 - 150,000 =   850,000
        // Total = 7,350,000 (transfer must not inflate or deflate total liquid wealth)
        let balances = AccountBalanceCalculator.balancesByAccount(accounts: accounts, transactions: transactions)
        let bankId = UUID(uuidString: "22222222-2222-4222-8222-222222222201")!
        let ewalletId = UUID(uuidString: "22222222-2222-4222-8222-222222222202")!
        XCTAssertEqual(balances[bankId], 6_500_000)
        XCTAssertEqual(balances[ewalletId], 850_000)
        XCTAssertEqual(AccountBalanceCalculator.totalLiquidWealth(accounts: accounts, transactions: transactions), 7_350_000)

        // Verify schemaVersion updated to 3 and v2/v3 tables operational
        let schemaVersion: String? = try upgraded.dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_metadata WHERE key = 'schemaVersion'")
        }
        XCTAssertEqual(schemaVersion, "3")
        XCTAssertEqual(try store.fetchAllSavingsGoals().count, 0)
    }
}
