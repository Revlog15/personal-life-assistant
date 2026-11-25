import Foundation
import GRDB
import PLACore

/// Unified GRDB repository implementing all `PLACore` storage contracts.
public final class GRDBStore: TaskRepository, ReminderRepository, FinanceRepository, InsightRepository, BackupRepository, @unchecked Sendable {
    public let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    private var dbWriter: any DatabaseWriter { dbManager.dbWriter }

    // MARK: - Initial Seeding

    public func ensureDefaultCategoriesExist() throws {
        try dbWriter.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0
            guard count == 0 else { return }
            for cat in PLADefaultSeed.defaultCategories() {
                try CategoryRecord(domain: cat).insert(db)
            }
        }
    }

    public func ensureDefaultAccountsExist(cashBalance: Int64 = 0, bankBalance: Int64 = 0, now: Date = Date()) throws {
        try dbWriter.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts") ?? 0
            guard count == 0 else { return }
            for acc in PLADefaultSeed.defaultAccounts(cashBalance: cashBalance, bankBalance: bankBalance, now: now) {
                try AccountRecord(domain: acc).insert(db)
            }
        }
    }

    /// Generates synthetic performance benchmark data (e.g., 2,000 transactions + 500 tasks) for SC-07 testing.
    public func seedBenchmarkDataset(transactionCount: Int = 2000, taskCount: Int = 500, today: LocalDate, now: Date = Date()) throws {
        try ensureDefaultCategoriesExist()
        try ensureDefaultAccountsExist(cashBalance: 1_000_000, bankBalance: 15_000_000, now: now)

        let accounts = try fetchAllAccounts()
        let expenseCats = try fetchAllCategories().filter { $0.scope == .expense }
        let incomeCats = try fetchAllCategories().filter { $0.scope == .income }
        let taskCats = try fetchAllCategories().filter { $0.scope == .task }
        guard let cash = accounts.first, let food = expenseCats.first, let salary = incomeCats.first else { return }

        try dbWriter.write { db in
            for i in 0..<transactionCount {
                let dayOffset = -(i % 120)
                let date = today.addingDays(dayOffset)
                let isIncome = (i % 25 == 0)
                let cat = isIncome ? salary : expenseCats[i % expenseCats.count]
                let acc = accounts[i % accounts.count]
                let amount: Int64 = isIncome ? 4_500_000 : Int64(((i % 15) + 1) * 15_000)
                let tx = PLATransaction(
                    type: isIncome ? .income : .expense,
                    amount: amount,
                    accountId: acc.id,
                    categoryId: cat.id,
                    dateLocal: date,
                    note: isIncome ? "Pemasukan #\(i)" : "Belanja #\(i)",
                    createdAt: now,
                    updatedAt: now
                )
                try TransactionRecord(domain: tx).insert(db)
            }

            for i in 0..<taskCount {
                let dayOffset = (i % 45) - 10
                let prio = TaskPriority(rawValue: i % 3) ?? .medium
                let done = (i % 3 == 0)
                let task = PLATask(
                    title: "Tugas Uji #\(i + 1)",
                    dueDateLocal: today.addingDays(dayOffset),
                    priority: prio,
                    status: done ? .completed : .active,
                    categoryId: taskCats.isEmpty ? nil : taskCats[i % taskCats.count].id,
                    completedAt: done ? now : nil,
                    createdAt: now,
                    updatedAt: now
                )
                try TaskRecord(domain: task).insert(db)
            }

            // Ensure an active budget exists
            let existingBudget = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets") ?? 0
            if existingBudget == 0 {
                let b = Budget(categoryId: nil, amount: 4_000_000, effectiveFromMonth: today.yearMonthString, createdAt: now, updatedAt: now)
                try BudgetRecord(domain: b).insert(db)
            }
            _ = (cash, food)
        }
    }

    // MARK: - TaskRepository

    public func fetchAllTasks() throws -> [PLATask] {
        try dbWriter.read { db in
            let rows = try TaskRecord.fetchAll(db, sql: "SELECT * FROM tasks ORDER BY status ASC, dueDateLocal ASC, priority DESC, createdAt DESC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveTask(_ task: PLATask) throws {
        try dbWriter.write { db in
            try TaskRecord(domain: task).save(db)
        }
    }

    public func deleteTask(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM reminders WHERE ownerType = ? AND ownerId = ?", arguments: [ReminderOwnerType.task.rawValue, id.uuidString])
            try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func fetchAllRecurrenceRules() throws -> [RecurrenceRule] {
        try dbWriter.read { db in
            try RecurrenceRuleRecord.fetchAll(db).map { try $0.toDomain() }
        }
    }

    public func saveRecurrenceRule(_ rule: RecurrenceRule) throws {
        try dbWriter.write { db in
            try RecurrenceRuleRecord(domain: rule).save(db)
        }
    }

    public func deleteRecurrenceRule(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM recurrence_rules WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - ReminderRepository

    public func fetchAllReminders() throws -> [Reminder] {
        try dbWriter.read { db in
            let rows = try ReminderRecord.fetchAll(db, sql: "SELECT * FROM reminders ORDER BY fireDateLocal ASC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func replaceReminders(forOwnerId ownerId: UUID, ownerType: ReminderOwnerType, reminders: [Reminder]) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM reminders WHERE ownerId = ? AND ownerType = ? AND triggerType = ?",
                arguments: [ownerId.uuidString, ownerType.rawValue, ReminderTriggerType.automatic.rawValue]
            )
            for r in reminders {
                try ReminderRecord(domain: r).save(db)
            }
        }
    }

    public func deleteReminders(forOwnerId ownerId: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM reminders WHERE ownerId = ?", arguments: [ownerId.uuidString])
        }
    }

    public func saveReminder(_ reminder: Reminder) throws {
        try dbWriter.write { db in
            try ReminderRecord(domain: reminder).save(db)
        }
    }

    // MARK: - FinanceRepository

    public func fetchAllAccounts() throws -> [Account] {
        try dbWriter.read { db in
            let rows = try AccountRecord.fetchAll(db, sql: "SELECT * FROM accounts ORDER BY isArchived ASC, sortOrder ASC, name ASC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveAccount(_ account: Account) throws {
        try dbWriter.write { db in
            if account.isDefault {
                try db.execute(sql: "UPDATE accounts SET isDefault = 0 WHERE id != ?", arguments: [account.id.uuidString])
            }
            try AccountRecord(domain: account).save(db)
        }
    }

    public func archiveAccount(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE accounts SET isArchived = 1, isDefault = 0 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAccount(id: UUID) throws {
        try dbWriter.write { db in
            let txCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE accountId = ? OR destinationAccountId = ?",
                arguments: [id.uuidString, id.uuidString]
            ) ?? 0
            let billCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bills WHERE defaultAccountId = ?",
                arguments: [id.uuidString]
            ) ?? 0
            if txCount > 0 || billCount > 0 {
                // AC-07.5: Soft-archive accounts with existing history so balances never break
                try db.execute(sql: "UPDATE accounts SET isArchived = 1, isDefault = 0 WHERE id = ?", arguments: [id.uuidString])
            } else {
                try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id.uuidString])
            }
        }
    }

    public func fetchAllCategories() throws -> [PLACategory] {
        try dbWriter.read { db in
            let rows = try CategoryRecord.fetchAll(db, sql: "SELECT * FROM categories ORDER BY scope ASC, sortOrder ASC, name ASC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveCategory(_ category: PLACategory) throws {
        try dbWriter.write { db in
            try CategoryRecord(domain: category).save(db)
        }
    }

    public func archiveCategory(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE categories SET isArchived = 1 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func fetchAllTransactions() throws -> [PLATransaction] {
        try dbWriter.read { db in
            let rows = try TransactionRecord.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY dateLocal DESC, createdAt DESC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func fetchTransactions(from: LocalDate, to: LocalDate) throws -> [PLATransaction] {
        try dbWriter.read { db in
            let rows = try TransactionRecord.fetchAll(
                db,
                sql: "SELECT * FROM transactions WHERE dateLocal >= ? AND dateLocal <= ? ORDER BY dateLocal DESC, createdAt DESC",
                arguments: [from.isoString, to.isoString]
            )
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveTransaction(_ transaction: PLATransaction) throws {
        try transaction.validate()
        try dbWriter.write { db in
            try TransactionRecord(domain: transaction).save(db)
        }
    }

    public func deleteTransaction(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM transactions WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func transactionCount(forAccountId id: UUID) throws -> Int {
        try dbWriter.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE accountId = ? OR destinationAccountId = ?",
                arguments: [id.uuidString, id.uuidString]
            ) ?? 0
        }
    }

    public func fetchAllBudgets() throws -> [Budget] {
        try dbWriter.read { db in
            let rows = try BudgetRecord.fetchAll(db, sql: "SELECT * FROM budgets ORDER BY effectiveFromMonth DESC, updatedAt DESC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveBudget(_ budget: Budget) throws {
        try dbWriter.write { db in
            try BudgetRecord(domain: budget).save(db)
        }
    }

    public func deleteBudget(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM budgets WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func fetchAllBills() throws -> [Bill] {
        try dbWriter.read { db in
            let rows = try BillRecord.fetchAll(db, sql: "SELECT * FROM bills ORDER BY isActive DESC, nextDueDateLocal ASC")
            return try rows.map { try $0.toDomain() }
        }
    }

    public func saveBill(_ bill: Bill) throws {
        try dbWriter.write { db in
            try BillRecord(domain: bill).save(db)
        }
    }

    public func deleteBill(id: UUID) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM reminders WHERE ownerType = ? AND ownerId = ?", arguments: [ReminderOwnerType.bill.rawValue, id.uuidString])
            try db.execute(sql: "DELETE FROM bills WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Atomically marks a bill as paid: inserts linked expense transaction + advances nextDueDateLocal (AC-10.2).
    public func markBillPaid(
        bill: Bill,
        actualAmount: Int64,
        updateEstimatedAmount: Bool,
        paidDate: LocalDate,
        nextDueDate: LocalDate?,
        now: Date
    ) throws -> PLATransaction {
        let tx = PLATransaction(
            type: .expense,
            amount: actualAmount,
            accountId: bill.defaultAccountId,
            categoryId: bill.categoryId,
            billId: bill.id,
            dateLocal: paidDate,
            note: "Tagihan: \(bill.name)",
            createdAt: now,
            updatedAt: now
        )
        try tx.validate()

        var updatedBill = bill
        updatedBill.lastPaidDateLocal = paidDate
        if updateEstimatedAmount {
            updatedBill.amount = actualAmount
        }
        if let next = nextDueDate {
            updatedBill.nextDueDateLocal = next
        } else {
            updatedBill.isActive = false
        }
        updatedBill.updatedAt = now

        try dbWriter.write { db in
            try TransactionRecord(domain: tx).insert(db)
            try BillRecord(domain: updatedBill).save(db)
        }
        return tx
    }

    // MARK: - InsightRepository

    public func fetchAllInsights() throws -> [InsightRecord] {
        try dbWriter.read { db in
            try InsightDBRecord.fetchAll(db).map { try $0.toDomain() }
        }
    }

    public func saveInsight(_ record: InsightRecord) throws {
        try dbWriter.write { db in
            if let subjectId = record.subjectId {
                try db.execute(
                    sql: "DELETE FROM insights WHERE ruleCode = ? AND periodKey = ? AND subjectId = ?",
                    arguments: [record.ruleCode, record.periodKey, subjectId.uuidString]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM insights WHERE ruleCode = ? AND periodKey = ? AND subjectId IS NULL",
                    arguments: [record.ruleCode, record.periodKey]
                )
            }
            try InsightDBRecord(domain: record).insert(db)
        }
    }

    // MARK: - BackupRepository

    public func exportFullPayload(settings: UserSettings) throws -> BackupPayload {
        try dbWriter.read { db in
            let tasks = try TaskRecord.fetchAll(db).map { try $0.toDomain() }
            let reminders = try ReminderRecord.fetchAll(db).map { try $0.toDomain() }
            let rules = try RecurrenceRuleRecord.fetchAll(db).map { try $0.toDomain() }
            let accounts = try AccountRecord.fetchAll(db).map { try $0.toDomain() }
            let categories = try CategoryRecord.fetchAll(db).map { try $0.toDomain() }
            let transactions = try TransactionRecord.fetchAll(db).map { try $0.toDomain() }
            let budgets = try BudgetRecord.fetchAll(db).map { try $0.toDomain() }
            let bills = try BillRecord.fetchAll(db).map { try $0.toDomain() }
            let insights = try InsightDBRecord.fetchAll(db).map { try $0.toDomain() }

            return BackupPayload(
                tasks: tasks,
                reminders: reminders,
                recurrenceRules: rules,
                accounts: accounts,
                categories: categories,
                transactions: transactions,
                budgets: budgets,
                bills: bills,
                insights: insights,
                settings: settings
            )
        }
    }

    /// Replaces all data inside a single atomic SQLite transaction (AC-13.3).
    public func restoreAtomically(payload: BackupPayload) throws {
        try dbWriter.write { db in
            // Delete child tables first to honor foreign keys
            try db.execute(sql: "DELETE FROM reminders")
            try db.execute(sql: "DELETE FROM transactions")
            try db.execute(sql: "DELETE FROM budgets")
            try db.execute(sql: "DELETE FROM bills")
            try db.execute(sql: "DELETE FROM tasks")
            try db.execute(sql: "DELETE FROM insights")
            try db.execute(sql: "DELETE FROM accounts")
            try db.execute(sql: "DELETE FROM recurrence_rules")
            try db.execute(sql: "DELETE FROM categories")

            // Insert parent tables first
            for item in payload.categories { try CategoryRecord(domain: item).insert(db) }
            for item in payload.recurrenceRules { try RecurrenceRuleRecord(domain: item).insert(db) }
            for item in payload.accounts { try AccountRecord(domain: item).insert(db) }
            for item in payload.tasks { try TaskRecord(domain: item).insert(db) }
            for item in payload.bills { try BillRecord(domain: item).insert(db) }
            for item in payload.reminders { try ReminderRecord(domain: item).insert(db) }
            for item in payload.transactions { try TransactionRecord(domain: item).insert(db) }
            for item in payload.budgets { try BudgetRecord(domain: item).insert(db) }
            for item in payload.insights { try InsightDBRecord(domain: item).insert(db) }
        }
    }
}
