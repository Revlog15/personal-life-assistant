import Foundation

public protocol TaskRepository: Sendable {
    func fetchAllTasks() throws -> [PLATask]
    func saveTask(_ task: PLATask) throws
    func deleteTask(id: UUID) throws
    func fetchAllRecurrenceRules() throws -> [RecurrenceRule]
    func saveRecurrenceRule(_ rule: RecurrenceRule) throws
    func deleteRecurrenceRule(id: UUID) throws
}

public protocol ReminderRepository: Sendable {
    func fetchAllReminders() throws -> [Reminder]
    func replaceReminders(forOwnerId ownerId: UUID, ownerType: ReminderOwnerType, reminders: [Reminder]) throws
    func deleteReminders(forOwnerId ownerId: UUID) throws
    func saveReminder(_ reminder: Reminder) throws
}

public protocol FinanceRepository: Sendable {
    func fetchAllAccounts() throws -> [Account]
    func saveAccount(_ account: Account) throws
    func archiveAccount(id: UUID) throws
    func deleteAccount(id: UUID) throws

    func fetchAllCategories() throws -> [PLACategory]
    func saveCategory(_ category: PLACategory) throws
    func archiveCategory(id: UUID) throws

    func fetchAllTransactions() throws -> [PLATransaction]
    func fetchTransactions(from: LocalDate, to: LocalDate) throws -> [PLATransaction]
    func saveTransaction(_ transaction: PLATransaction) throws
    func deleteTransaction(id: UUID) throws
    func transactionCount(forAccountId id: UUID) throws -> Int

    func fetchAllBudgets() throws -> [Budget]
    func saveBudget(_ budget: Budget) throws
    func deleteBudget(id: UUID) throws

    func fetchAllBills() throws -> [Bill]
    func saveBill(_ bill: Bill) throws
    func deleteBill(id: UUID) throws
    func markBillPaid(
        bill: Bill,
        actualAmount: Int64,
        updateEstimatedAmount: Bool,
        paidDate: LocalDate,
        nextDueDate: LocalDate?,
        now: Date
    ) throws -> PLATransaction
}

public protocol InsightRepository: Sendable {
    func fetchAllInsights() throws -> [InsightRecord]
    func saveInsight(_ record: InsightRecord) throws
}

public protocol SavingsGoalRepository: Sendable {
    func fetchAllSavingsGoals() throws -> [SavingsGoal]
    func saveSavingsGoal(_ goal: SavingsGoal) throws
    func deleteSavingsGoal(id: UUID) throws
}

public protocol BackupRepository: Sendable {
    func exportFullPayload(settings: UserSettings) throws -> BackupPayload
    func restoreAtomically(payload: BackupPayload) throws
}
