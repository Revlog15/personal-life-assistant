import Foundation
import SwiftUI
import UserNotifications
import WidgetKit
import PLACore
import PLAData

/// Root @Observable application state wiring GRDBStore, PLACore engines, notifications, Face ID, and diagnostics.
@MainActor
@Observable
final class AppStore {
    let store: GRDBStore?
    let settingsStore: SettingsStore
    let diagnostics: DiagnosticsService
    let authService: AuthService
    let calendarService: CalendarService
    let notificationAdapter: NotificationAdapter
    let backgroundRefresh: BackgroundRefreshService
    let clock: any PLAClock

    // Domain snapshots
    var tasks: [PLATask] = []
    var reminders: [Reminder] = []
    var recurrenceRules: [RecurrenceRule] = []
    var accounts: [Account] = []
    var categories: [PLACategory] = []
    var transactions: [PLATransaction] = []
    var budgets: [Budget] = []
    var bills: [Bill] = []
    var insightRecords: [InsightRecord] = []
    var savingsGoals: [SavingsGoal] = []
    var settings: UserSettings

    // System & UI state
    var appearanceMode: AppAppearanceMode = .system
    var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    var pendingNotificationCount: Int = 0
    var sideloadInfo: SideloadExpiryInfo
    var databaseErrorMessage: String?
    var pendingOCRReceipt: PendingOCRReceiptDraft?
    var pendingTabNavigation: AppTab?
    var pendingQuickAddRoute: QuickAddSheetKind?
    var dismissedPersonalSuggestionIds: Set<String> = []
    private var lastHandledOCRDraftId: UUID?

    // Toast & 5-second Undo state (AC-02.3)
    var toastMessage: String?
    var toastUndoTitle: String?
    private var toastUndoAction: (() -> Void)?
    private var toastDismissTask: _Concurrency.Task<Void, Never>?

    private var systemObservers: [NSObjectProtocol] = []

    init(clock: any PLAClock = SystemClock()) {
        self.clock = clock
        self.settingsStore = SettingsStore()
        self.diagnostics = DiagnosticsService()
        self.authService = AuthService()
        self.calendarService = CalendarService()
        self.notificationAdapter = NotificationAdapter(diagnostics: diagnostics)
        // PRD §13.4: Sweep any residual temporary OCR files on every launch
        VisionReceiptOCRService.cleanupResidualTempFiles()
        self.backgroundRefresh = BackgroundRefreshService(
            diagnostics: diagnostics,
            notificationAdapter: notificationAdapter,
            settingsStore: settingsStore
        )
        let loadedSettings = settingsStore.loadSettings()
        self.settings = loadedSettings
        self.appearanceMode = settingsStore.loadAppearanceMode()
        self.sideloadInfo = SideloadExpiryReader.read(
            manualRefreshDate: settingsStore.loadManualSideloadRefreshDate(),
            timeZone: clock.timeZone
        )

        if !loadedSettings.financeLockEnabled {
            self.authService.isFinanceUnlocked = true
        }

        do {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let dbManager = try DatabaseManager(appVersion: appVersion)
            let grdbStore = GRDBStore(dbManager: dbManager)
            try grdbStore.ensureDefaultCategoriesExist()
            self.store = grdbStore
        } catch {
            self.store = nil
            self.databaseErrorMessage = error.localizedDescription
            self.diagnostics.log(level: "ERROR", category: "Database", message: "Init DB gagal: \(error.localizedDescription)")
        }

        notificationAdapter.onActionReceived = { [weak self] event in
            self?.handleNotificationAction(event)
        }

        reloadAllData()
        consumePendingOCRReceiptIfAny()
        setupSystemTimeObservers()
    }

    // MARK: - Derived Computations

    var today: LocalDate { clock.today }
    var currentDateTime: LocalDateTime { clock.currentLocalDateTime }

    var activePeriod: BudgetPeriod {
        BudgetPeriod.current(for: today, cycleStartDay: settings.budgetCycleStartDay)
    }

    var financialSummary: FinancialPeriodSummary {
        let period = activePeriod
        return BudgetCalculator.summarize(
            today: today,
            cycleStartDay: settings.budgetCycleStartDay,
            transactions: transactions,
            budgets: budgets,
            bills: bills,
            categories: categories,
            openingSpent: settings.openingSpent(for: period.periodKey)
        )
    }

    var activeInsights: [FinancialInsight] {
        InsightEngine.evaluate(
            summary: financialSummary,
            today: today,
            cycleStartDay: settings.budgetCycleStartDay,
            allTransactions: transactions,
            categories: categories,
            existingRecords: insightRecords
        )
    }

    /// P-09: Opt-in Personal Intelligence suggestions (R-PER-01 & R-PER-02), cold-start guarded.
    var personalSuggestions: [PersonalSuggestion] {
        PersonalIntelligenceEngine.evaluate(
            tasks: tasks,
            categories: categories,
            now: clock.now,
            timeZone: clock.timeZone,
            settings: settings
        ).filter { !dismissedPersonalSuggestionIds.contains($0.id) }
    }

    var activeSavingsGoals: [SavingsGoal] {
        savingsGoals.filter { $0.status != .archived }
    }

    var accountBalances: [UUID: Int64] {
        AccountBalanceCalculator.balancesByAccount(accounts: accounts, transactions: transactions)
    }

    var totalLiquidWealth: Int64 {
        AccountBalanceCalculator.totalLiquidWealth(accounts: accounts, transactions: transactions)
    }

    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    var archivedAccounts: [Account] { accounts.filter { $0.isArchived } }

    var defaultAccount: Account? {
        activeAccounts.first(where: \.isDefault) ?? activeAccounts.first
    }

    var expenseCategories: [PLACategory] {
        categories.filter { $0.scope == .expense && !$0.isArchived }
    }

    var incomeCategories: [PLACategory] {
        categories.filter { $0.scope == .income && !$0.isArchived }
    }

    var taskCategories: [PLACategory] {
        categories.filter { $0.scope == .task && !$0.isArchived }
    }

    var defaultTaskCategory: PLACategory? {
        taskCategories.first { $0.name == "Umum" } ?? taskCategories.first
    }

    var overdueTasks: [PLATask] {
        let now = currentDateTime
        return tasks.filter { $0.isOverdue(at: now) }
    }

    var todayTasks: [PLATask] {
        let now = currentDateTime
        return tasks.filter { task in
            task.status == .active && task.dueDateLocal == today && !task.isOverdue(at: now)
        }
    }

    var upcomingTasks: [PLATask] {
        tasks.filter { task in
            guard task.status == .active, let due = task.dueDateLocal else { return false }
            return due > today
        }
    }

    var anytimeTasks: [PLATask] {
        tasks.filter { $0.status == .active && $0.dueDateLocal == nil }
    }

    var completedTasks: [PLATask] {
        tasks
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    var activeBills: [Bill] {
        bills.filter(\.isActive)
    }

    var upcomingBills7Days: [Bill] {
        activeBills.filter { $0.isDueWithin(days: 7, from: today) }
    }

    var isCompletelyEmpty: Bool {
        tasks.isEmpty && bills.isEmpty && transactions.isEmpty
    }

    func recurrenceRule(for id: UUID?) -> RecurrenceRule? {
        guard let id else { return nil }
        return recurrenceRules.first { $0.id == id }
    }

    func categoryName(for id: UUID?) -> String {
        guard let id else { return "Tanpa Kategori" }
        return categories.first { $0.id == id }?.name ?? "Kategori"
    }

    func accountName(for id: UUID?) -> String {
        guard let id else { return "Akun" }
        return accounts.first { $0.id == id }?.name ?? "Akun"
    }

    func feedbackForInsight(_ insight: FinancialInsight) -> Int? {
        insightRecords.first {
            $0.ruleCode == insight.ruleCode.rawValue &&
            $0.periodKey == insight.periodKey &&
            $0.subjectId == insight.subjectId
        }?.feedback
    }

    // MARK: - Data Loading & Sync

    func reloadAllData() {
        guard let store else { return }
        do {
            tasks = try store.fetchAllTasks()
            reminders = try store.fetchAllReminders()
            recurrenceRules = try store.fetchAllRecurrenceRules()
            accounts = try store.fetchAllAccounts()
            categories = try store.fetchAllCategories()
            transactions = try store.fetchAllTransactions()
            budgets = try store.fetchAllBudgets()
            bills = try store.fetchAllBills()
            insightRecords = try store.fetchAllInsights()
            savingsGoals = try store.fetchAllSavingsGoals()
            syncWidgetSnapshot()
        } catch {
            diagnostics.log(level: "ERROR", category: "Reload", message: "Gagal memuat data: \(error.localizedDescription)")
        }
    }

    func syncWidgetSnapshot() {
        let snapshot = WidgetSnapshotBuilder.build(
            today: today,
            now: currentDateTime,
            summary: financialSummary,
            tasks: tasks,
            bills: bills,
            settings: settings,
            generatedAt: clock.now
        )
        let saved = PLASharedContainer.saveWidgetSnapshot(snapshot)
        if saved {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var appGroupStatus: PLAAppGroupStatus {
        PLASharedContainer.status()
    }

    func runAppGroupSelfTest() -> (ok: Bool, detail: String) {
        let result = PLASharedContainer.runAppGroupSelfTest()
        diagnostics.log(
            level: result.ok ? "INFO" : "WARN",
            category: "AppGroupV07",
            message: result.detail
        )
        return result
    }

    func consumePendingOCRReceiptIfAny() {
        if let draft = PendingOCRReceiptStore.consume(), draft.id != lastHandledOCRDraftId {
            lastHandledOCRDraftId = draft.id
            pendingOCRReceipt = draft
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let route = PLAURLRoute.parse(url: url) else { return }
        switch route {
        case .dashboard:
            pendingTabNavigation = .dashboard
        case .tasks:
            pendingTabNavigation = .tasks
        case .finance:
            pendingTabNavigation = .finance
        case .settings:
            pendingTabNavigation = .settings
        case .quickAddTask:
            pendingTabNavigation = .tasks
            pendingQuickAddRoute = .task
        case .quickAddExpense:
            pendingTabNavigation = .finance
            pendingQuickAddRoute = .expense
        case .ocrDraft(let draft):
            guard draft.id != lastHandledOCRDraftId else { return }
            lastHandledOCRDraftId = draft.id
            // Clear any duplicate App Group file saved simultaneously by Share Extension
            _ = PendingOCRReceiptStore.consume()
            pendingOCRReceipt = draft
        }
    }

    func refreshSystemStatusAndSyncNotifications() {
        consumePendingOCRReceiptIfAny()
        reloadAllData()
        sideloadInfo = SideloadExpiryReader.read(
            manualRefreshDate: settingsStore.loadManualSideloadRefreshDate(),
            timeZone: clock.timeZone
        )
        _Concurrency.Task {
            notificationAuthStatus = await notificationAdapter.authorizationStatus()
            await syncNotificationQueueNow()
        }
    }

    func syncNotificationQueueNow() async {
        let plan = NotificationQueuePlanner.buildQueue(
            now: currentDateTime,
            tasks: tasks,
            bills: bills,
            reminders: reminders,
            settings: settings,
            sideloadExpiryDate: sideloadInfo.expirationDate
        )
        pendingNotificationCount = await notificationAdapter.syncQueue(plan: plan, timeZone: clock.timeZone)
    }

    func requestNotificationPermission() async {
        _ = await notificationAdapter.requestAuthorization()
        notificationAuthStatus = await notificationAdapter.authorizationStatus()
        await syncNotificationQueueNow()
    }

    // MARK: - Onboarding (F-15)

    func completeOnboarding(
        cashBalance: Int64,
        bankBalance: Int64,
        monthlyBudget: Int64?,
        budgetCycleStartDay: Int = 1,
        remainingBudgetForCurrentCycle: Int64? = nil
    ) {
        guard let store else { return }
        do {
            try store.ensureDefaultCategoriesExist()
            try store.ensureDefaultAccountsExist(cashBalance: cashBalance, bankBalance: bankBalance, now: clock.now)

            settings.budgetCycleStartDay = min(max(budgetCycleStartDay, 1), 28)
            let period = BudgetPeriod.current(for: today, cycleStartDay: settings.budgetCycleStartDay)

            if let monthlyBudget, monthlyBudget > 0 {
                let budget = Budget(
                    categoryId: nil,
                    amount: monthlyBudget,
                    effectiveFromMonth: period.periodKey,
                    isActive: true,
                    createdAt: clock.now,
                    updatedAt: clock.now
                )
                try store.saveBudget(budget)

                if let remaining = remainingBudgetForCurrentCycle {
                    let opening = BudgetCalculator.openingSpent(
                        monthlyBudget: monthlyBudget,
                        remainingForCurrentCycle: remaining,
                        recordedExpense: 0
                    )
                    if opening > 0 {
                        settings.budgetOpeningSpentByPeriod[period.periodKey] = opening
                    } else {
                        settings.budgetOpeningSpentByPeriod.removeValue(forKey: period.periodKey)
                    }
                }
            }

            settings.hasCompletedOnboarding = true
            settingsStore.saveSettings(settings)
            reloadAllData()
            refreshSystemStatusAndSyncNotifications()
        } catch {
            diagnostics.log(level: "ERROR", category: "Onboarding", message: "Gagal menyelesaikan onboarding: \(error.localizedDescription)")
        }
    }

    func skipOnboarding() {
        guard let store else { return }
        do {
            try store.ensureDefaultCategoriesExist()
            try store.ensureDefaultAccountsExist(cashBalance: 0, bankBalance: 0, now: clock.now)
            settings.hasCompletedOnboarding = true
            settingsStore.saveSettings(settings)
            reloadAllData()
            refreshSystemStatusAndSyncNotifications()
        } catch {
            diagnostics.log(level: "ERROR", category: "Onboarding", message: "Gagal melewati onboarding: \(error.localizedDescription)")
        }
    }

    // MARK: - Tasks & Smart Reminders (F-02..F-06)

    func createOrUpdateTask(
        existing: PLATask? = nil,
        title: String,
        notes: String?,
        dueDate: LocalDate?,
        dueTimeMinutes: Int?,
        priority: TaskPriority,
        categoryId: UUID?,
        recurrenceRule: RecurrenceRule?
    ) {
        guard let store, PLATask.isValidTitle(title) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = clock.now

        do {
            var resolvedRuleId: UUID? = nil
            if let rule = recurrenceRule {
                try store.saveRecurrenceRule(rule)
                resolvedRuleId = rule.id
            }

            let task = PLATask(
                id: existing?.id ?? UUID(),
                title: trimmedTitle,
                notes: (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes,
                dueDateLocal: dueDate,
                dueTimeMinutes: dueDate == nil ? nil : dueTimeMinutes,
                priority: priority,
                status: existing?.status ?? .active,
                categoryId: categoryId ?? defaultTaskCategory?.id,
                recurrenceRuleId: resolvedRuleId,
                completedAt: existing?.completedAt,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )

            try store.saveTask(task)
            let autoReminders = ReminderPlanner.planTaskReminders(for: task, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: task.id, ownerType: .task, reminders: autoReminders)

            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal menyimpan tugas: \(error.localizedDescription)")
        }
    }

    func completeTask(_ task: PLATask, catchUpFromToday: Bool = false) {
        guard let store, task.status == .active else { return }
        let previousSnapshot = task
        var completed = task
        completed.status = .completed
        completed.completedAt = clock.now
        completed.updatedAt = clock.now

        var spawnedNextTaskId: UUID? = nil

        do {
            try store.saveTask(completed)
            try store.deleteReminders(forOwnerId: task.id)

            // AC-04.2 & P-10: Generate next recurring cycle (supports fixedSchedule AND fromCompletionDate!)
            if let ruleId = task.recurrenceRuleId,
               let rule = recurrenceRule(for: ruleId),
               let currentDue = task.dueDateLocal {
                let nextDue: LocalDate?
                if rule.anchorMode == .fromCompletionDate {
                    nextDue = RecurrenceEngine.nextOccurrence(after: currentDue, completedOn: today, rule: rule)
                } else if catchUpFromToday {
                    nextDue = RecurrenceEngine.nextOccurrenceFromToday(overdueDate: currentDue, today: today, rule: rule)
                } else {
                    nextDue = RecurrenceEngine.nextOccurrence(after: currentDue, completedOn: today, rule: rule)
                }

                if let nextDue {
                    let nextTask = PLATask(
                        title: task.title,
                        notes: task.notes,
                        dueDateLocal: nextDue,
                        dueTimeMinutes: task.dueTimeMinutes,
                        priority: task.priority,
                        status: .active,
                        categoryId: task.categoryId,
                        recurrenceRuleId: rule.id,
                        createdAt: clock.now,
                        updatedAt: clock.now
                    )
                    try store.saveTask(nextTask)
                    let nextRems = ReminderPlanner.planTaskReminders(for: nextTask, now: currentDateTime, settings: settings)
                    try store.replaceReminders(forOwnerId: nextTask.id, ownerType: .task, reminders: nextRems)
                    spawnedNextTaskId = nextTask.id
                }
            }

            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }

            // AC-02.3: 5-second Undo toast
            showToast("Selesai", undoTitle: "Urungkan") { [weak self] in
                self?.undoTaskCompletion(originalTask: previousSnapshot, spawnedNextTaskId: spawnedNextTaskId)
            }
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal menyelesaikan tugas: \(error.localizedDescription)")
        }
    }

    func reopenTask(_ task: PLATask) {
        guard let store else { return }
        var reopened = task
        reopened.status = .active
        reopened.completedAt = nil
        reopened.updatedAt = clock.now
        do {
            try store.saveTask(reopened)
            let rems = ReminderPlanner.planTaskReminders(for: reopened, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: reopened.id, ownerType: .task, reminders: rems)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal membuka ulang tugas: \(error.localizedDescription)")
        }
    }

    private func undoTaskCompletion(originalTask: PLATask, spawnedNextTaskId: UUID?) {
        guard let store else { return }
        do {
            if let spawnedId = spawnedNextTaskId {
                try store.deleteTask(id: spawnedId)
            }
            try store.saveTask(originalTask)
            let rems = ReminderPlanner.planTaskReminders(for: originalTask, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: originalTask.id, ownerType: .task, reminders: rems)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal mengurungkan tugas: \(error.localizedDescription)")
        }
    }

    func rescheduleTask(_ task: PLATask, to newDate: LocalDate, newTimeMinutes: Int? = nil) {
        guard let store else { return }
        var updated = task
        updated.dueDateLocal = newDate
        if let newTimeMinutes {
            updated.dueTimeMinutes = newTimeMinutes
        }
        updated.updatedAt = clock.now
        do {
            try store.saveTask(updated)
            let rems = ReminderPlanner.planTaskReminders(for: updated, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: updated.id, ownerType: .task, reminders: rems)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
            showToast("Dijadwalkan ke \(PLAFormatters.shortDate(newDate))")
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal menjadwalkan ulang: \(error.localizedDescription)")
        }
    }

    /// AC-04.4: Delete either just this cycle (advancing to next cycle) or the entire recurring series.
    func deleteTask(_ task: PLATask, deleteEntireSeries: Bool) {
        guard let store else { return }
        do {
            if !deleteEntireSeries,
               let ruleId = task.recurrenceRuleId,
               let rule = recurrenceRule(for: ruleId),
               let currentDue = task.dueDateLocal,
               let nextDue = RecurrenceEngine.nextOccurrence(after: currentDue, rule: rule) {
                let nextTask = PLATask(
                    title: task.title,
                    notes: task.notes,
                    dueDateLocal: nextDue,
                    dueTimeMinutes: task.dueTimeMinutes,
                    priority: task.priority,
                    status: .active,
                    categoryId: task.categoryId,
                    recurrenceRuleId: rule.id,
                    createdAt: clock.now,
                    updatedAt: clock.now
                )
                try store.saveTask(nextTask)
                let rems = ReminderPlanner.planTaskReminders(for: nextTask, now: currentDateTime, settings: settings)
                try store.replaceReminders(forOwnerId: nextTask.id, ownerType: .task, reminders: rems)
            }

            try store.deleteTask(id: task.id)
            if deleteEntireSeries, let ruleId = task.recurrenceRuleId {
                // Clean up rule only if no bills or other active tasks reference it
                let stillUsedByTasks = try store.fetchAllTasks().contains { $0.recurrenceRuleId == ruleId }
                let stillUsedByBills = try store.fetchAllBills().contains { $0.recurrenceRuleId == ruleId }
                if !stillUsedByTasks && !stillUsedByBills {
                    try store.deleteRecurrenceRule(id: ruleId)
                }
            }

            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Task", message: "Gagal menghapus tugas: \(error.localizedDescription)")
        }
    }

    func snoozeTaskOneHour(taskId: UUID) {
        guard let store, let task = tasks.first(where: { $0.id == taskId && $0.status == .active }) else { return }
        let snoozeFire = currentDateTime.addingMinutes(60)
        let rem = Reminder(
            ownerType: .task,
            ownerId: task.id,
            triggerType: .snooze,
            offsetMinutes: 60,
            fireDateLocal: snoozeFire,
            soundName: task.priority == .high ? settings.urgentTaskSound : settings.defaultTaskSound,
            isEnabled: true
        )
        do {
            try store.saveReminder(rem)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Snooze", message: "Gagal menunda pengingat: \(error.localizedDescription)")
        }
    }

    // MARK: - Accounts, Transactions & Budgets (F-07..F-09)

    func saveAccount(_ account: Account) {
        guard let store else { return }
        do {
            try store.saveAccount(account)
            reloadAllData()
        } catch {
            diagnostics.log(level: "ERROR", category: "Account", message: "Gagal menyimpan akun: \(error.localizedDescription)")
        }
    }

    func deleteOrArchiveAccount(_ account: Account) {
        guard let store else { return }
        do {
            let count = try store.transactionCount(forAccountId: account.id)
            try store.deleteAccount(id: account.id)
            reloadAllData()
            if count > 0 {
                showToast("Akun diarsipkan agar riwayat transaksi tetap utuh")
            }
        } catch {
            diagnostics.log(level: "ERROR", category: "Account", message: "Gagal menghapus akun: \(error.localizedDescription)")
        }
    }

    func saveTransaction(_ transaction: PLATransaction) {
        guard let store else { return }
        do {
            try store.saveTransaction(transaction)
            reloadAllData()
            showToast("Transaksi tersimpan")
        } catch {
            diagnostics.log(level: "ERROR", category: "Transaction", message: "Gagal menyimpan transaksi: \(error.localizedDescription)")
        }
    }

    func deleteTransaction(id: UUID) {
        guard let store else { return }
        do {
            try store.deleteTransaction(id: id)
            reloadAllData()
        } catch {
            diagnostics.log(level: "ERROR", category: "Transaction", message: "Gagal menghapus transaksi: \(error.localizedDescription)")
        }
    }

    /// AC-07.3: Transfer between accounts + optional admin fee recorded as "Biaya Admin" expense.
    func createTransfer(
        from sourceId: UUID,
        to destinationId: UUID,
        amount: Int64,
        adminFee: Int64?,
        date: LocalDate,
        note: String?
    ) {
        guard let store, sourceId != destinationId, amount > 0 else { return }
        let now = clock.now
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let transferTx = PLATransaction(
                type: .transfer,
                amount: amount,
                accountId: sourceId,
                destinationAccountId: destinationId,
                categoryId: nil,
                dateLocal: date,
                note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
                createdAt: now,
                updatedAt: now
            )
            try store.saveTransaction(transferTx)

            if let fee = adminFee, fee > 0 {
                let adminCat = expenseCategories.first { $0.name == "Biaya Admin" } ?? expenseCategories.last
                if let catId = adminCat?.id {
                    let feeTx = PLATransaction(
                        type: .expense,
                        amount: fee,
                        accountId: sourceId,
                        categoryId: catId,
                        dateLocal: date,
                        note: "Biaya admin transfer ke \(accountName(for: destinationId))",
                        createdAt: now,
                        updatedAt: now
                    )
                    try store.saveTransaction(feeTx)
                }
            }

            reloadAllData()
            showToast("Transfer tersimpan")
        } catch {
            diagnostics.log(level: "ERROR", category: "Transfer", message: "Gagal mencatat transfer: \(error.localizedDescription)")
        }
    }

    func saveBudget(
        categoryId: UUID?,
        amount: Int64,
        cycleStartDay: Int? = nil,
        openingSpentForCurrentPeriod: Int64? = nil
    ) {
        guard let store, amount > 0 else { return }
        if categoryId == nil, let cycleStartDay {
            settings.budgetCycleStartDay = min(max(cycleStartDay, 1), 28)
        }
        let periodKey = activePeriod.periodKey
        let existing = budgets.first { $0.categoryId == categoryId && $0.effectiveFromMonth == periodKey }
        let budget = Budget(
            id: existing?.id ?? UUID(),
            categoryId: categoryId,
            amount: amount,
            effectiveFromMonth: periodKey,
            isActive: true,
            createdAt: existing?.createdAt ?? clock.now,
            updatedAt: clock.now
        )
        do {
            try store.saveBudget(budget)
            if categoryId == nil, let opening = openingSpentForCurrentPeriod {
                if opening > 0 {
                    settings.budgetOpeningSpentByPeriod[periodKey] = opening
                } else {
                    settings.budgetOpeningSpentByPeriod.removeValue(forKey: periodKey)
                }
            }
            if categoryId == nil && (cycleStartDay != nil || openingSpentForCurrentPeriod != nil) {
                settingsStore.saveSettings(settings)
            }
            reloadAllData()
            showToast("Anggaran diperbarui")
        } catch {
            diagnostics.log(level: "ERROR", category: "Budget", message: "Gagal menyimpan anggaran: \(error.localizedDescription)")
        }
    }

    func deleteBudget(id: UUID) {
        guard let store else { return }
        let isTotal = budgets.first(where: { $0.id == id })?.categoryId == nil
        do {
            try store.deleteBudget(id: id)
            if isTotal {
                settings.budgetOpeningSpentByPeriod.removeValue(forKey: activePeriod.periodKey)
                settingsStore.saveSettings(settings)
            }
            reloadAllData()
        } catch {
            diagnostics.log(level: "ERROR", category: "Budget", message: "Gagal menghapus anggaran: \(error.localizedDescription)")
        }
    }

    // MARK: - Bills (F-10)

    func saveBill(_ bill: Bill, rule: RecurrenceRule) {
        guard let store else { return }
        do {
            try store.saveRecurrenceRule(rule)
            try store.saveBill(bill)
            let rems = ReminderPlanner.planBillReminders(for: bill, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: bill.id, ownerType: .bill, reminders: rems)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Bill", message: "Gagal menyimpan tagihan: \(error.localizedDescription)")
        }
    }

    func markBillPaid(bill: Bill, actualAmount: Int64, updateEstimatedAmount: Bool) {
        guard let store, let rule = recurrenceRule(for: bill.recurrenceRuleId) else { return }
        let nextDue = RecurrenceEngine.nextOccurrence(after: bill.nextDueDateLocal, rule: rule)
        do {
            _ = try store.markBillPaid(
                bill: bill,
                actualAmount: actualAmount,
                updateEstimatedAmount: updateEstimatedAmount,
                paidDate: today,
                nextDueDate: nextDue,
                now: clock.now
            )

            // Refresh reminders for the bill's next cycle
            reloadAllData()
            if let refreshedBill = bills.first(where: { $0.id == bill.id }) {
                let rems = ReminderPlanner.planBillReminders(for: refreshedBill, now: currentDateTime, settings: settings)
                try store.replaceReminders(forOwnerId: bill.id, ownerType: .bill, reminders: rems)
                reloadAllData()
            }
            _Concurrency.Task { await syncNotificationQueueNow() }
            showToast("Tagihan \(bill.name) ditandai lunas")
        } catch {
            diagnostics.log(level: "ERROR", category: "Bill", message: "Gagal menandai tagihan lunas: \(error.localizedDescription)")
        }
    }

    /// AC-10.3: Skip current bill cycle without creating a transaction.
    func skipBillCycle(_ bill: Bill) {
        guard let store, let rule = recurrenceRule(for: bill.recurrenceRuleId) else { return }
        var updated = bill
        if let nextDue = RecurrenceEngine.nextOccurrence(after: bill.nextDueDateLocal, rule: rule) {
            updated.nextDueDateLocal = nextDue
        } else {
            updated.isActive = false
        }
        updated.updatedAt = clock.now
        do {
            try store.saveBill(updated)
            let rems = ReminderPlanner.planBillReminders(for: updated, now: currentDateTime, settings: settings)
            try store.replaceReminders(forOwnerId: updated.id, ownerType: .bill, reminders: rems)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
            showToast("Siklus \(bill.name) dilewati")
        } catch {
            diagnostics.log(level: "ERROR", category: "Bill", message: "Gagal melewati siklus tagihan: \(error.localizedDescription)")
        }
    }

    func deleteBill(id: UUID) {
        guard let store else { return }
        do {
            try store.deleteBill(id: id)
            reloadAllData()
            _Concurrency.Task { await syncNotificationQueueNow() }
        } catch {
            diagnostics.log(level: "ERROR", category: "Bill", message: "Gagal menghapus tagihan: \(error.localizedDescription)")
        }
    }

    // MARK: - Insights Feedback & Dismiss (AC-11.4, SC-16)

    func dismissInsight(_ insight: FinancialInsight) {
        guard let store else { return }
        let existing = insightRecords.first {
            $0.ruleCode == insight.ruleCode.rawValue &&
            $0.periodKey == insight.periodKey &&
            $0.subjectId == insight.subjectId
        }
        let rec = InsightRecord(
            id: existing?.id ?? UUID(),
            ruleCode: insight.ruleCode.rawValue,
            periodKey: insight.periodKey,
            subjectId: insight.subjectId,
            severity: insight.severity,
            dismissedAt: clock.now,
            feedback: existing?.feedback,
            generatedAt: existing?.generatedAt ?? clock.now
        )
        do {
            try store.saveInsight(rec)
            reloadAllData()
        } catch {
            diagnostics.log(level: "ERROR", category: "Insight", message: "Gagal menutup insight: \(error.localizedDescription)")
        }
    }

    func rateInsight(_ insight: FinancialInsight, useful: Bool) {
        guard let store else { return }
        let existing = insightRecords.first {
            $0.ruleCode == insight.ruleCode.rawValue &&
            $0.periodKey == insight.periodKey &&
            $0.subjectId == insight.subjectId
        }
        let rec = InsightRecord(
            id: existing?.id ?? UUID(),
            ruleCode: insight.ruleCode.rawValue,
            periodKey: insight.periodKey,
            subjectId: insight.subjectId,
            severity: insight.severity,
            dismissedAt: existing?.dismissedAt,
            feedback: useful ? 1 : -1,
            generatedAt: existing?.generatedAt ?? clock.now
        )
        do {
            try store.saveInsight(rec)
            reloadAllData()
            showToast(useful ? "Terima kasih atas penilaiannya!" : "Masukan dicatat untuk evaluasi")
        } catch {
            diagnostics.log(level: "ERROR", category: "Insight", message: "Gagal menyimpan umpan balik insight: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings & Backup/Restore (F-13, F-14)

    func updateSettings(_ mutate: (inout UserSettings) -> Void) {
        mutate(&settings)
        settingsStore.saveSettings(settings)
        if !settings.financeLockEnabled {
            authService.isFinanceUnlocked = true
        }
        syncWidgetSnapshot()
        _Concurrency.Task { await syncNotificationQueueNow() }
    }

    func recordManualSideloadRefreshToday() {
        settingsStore.saveManualSideloadRefreshDate(today)
        refreshSystemStatusAndSyncNotifications()
        showToast("Tanggal refresh SideStore dicatat (+7 hari)")
    }

    func exportBackupJSON() throws -> Data {
        guard let store else { throw BackupCodecError.invalidJSON }
        let payload = try store.exportFullPayload(settings: settings)
        return try BackupCodec.encode(payload: payload, exportedAt: clock.now)
    }

    func validateBackupFile(data: Data) -> Result<BackupPreview, BackupCodecError> {
        BackupCodec.decodeAndValidate(data: data)
    }

    func restoreBackup(preview: BackupPreview) throws {
        guard let store else { return }
        // AC-13.3: Create emergency internal sqlite snapshot before atomic restore
        if let dbURL = store.dbManager.databaseURL {
            let emergencyURL = dbURL.deletingLastPathComponent().appendingPathComponent("pla_pre_restore_snapshot.sqlite")
            try? FileManager.default.removeItem(at: emergencyURL)
            try? FileManager.default.copyItem(at: dbURL, to: emergencyURL)
        }
        try store.restoreAtomically(payload: preview.payload)
        settings = preview.payload.settings
        settings.hasCompletedOnboarding = true
        settingsStore.saveSettings(settings)
        reloadAllData()
        refreshSystemStatusAndSyncNotifications()
        showToast("Backup berhasil dipulihkan")
    }

    func exportTransactionsCSV(from startDate: LocalDate, to endDate: LocalDate) -> Data {
        CSVExporter.exportTransactions(
            transactions: transactions,
            accounts: accounts,
            categories: categories,
            from: startDate,
            to: endDate
        )
    }

    func seedBenchmarkDatasetForSC07() {
        guard let store else { return }
        do {
            try store.seedBenchmarkDataset(transactionCount: 2000, taskCount: 500, today: today, now: clock.now)
            reloadAllData()
            showToast("2.000 transaksi & 500 tugas uji ditambahkan")
        } catch {
            diagnostics.log(level: "ERROR", category: "Seed", message: "Gagal seed data benchmark: \(error.localizedDescription)")
        }
    }

    // MARK: - Toast & Observers

    func showToast(_ message: String, undoTitle: String? = nil, onUndo: (() -> Void)? = nil) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastUndoTitle = undoTitle
        toastUndoAction = onUndo

        toastDismissTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            guard !_Concurrency.Task.isCancelled else { return }
            self?.clearToast()
        }
    }

    func triggerToastUndo() {
        let action = toastUndoAction
        clearToast()
        action?()
    }

    func clearToast() {
        toastDismissTask?.cancel()
        toastMessage = nil
        toastUndoTitle = nil
        toastUndoAction = nil
    }

    private func handleNotificationAction(_ event: NotificationActionEvent) {
        switch event {
        case .completeTask(let taskId):
            if let task = tasks.first(where: { $0.id == taskId && $0.status == .active }) {
                completeTask(task)
            }
        case .snoozeTaskOneHour(let taskId):
            snoozeTaskOneHour(taskId: taskId)
        case .markBillPaid(let billId):
            if let bill = bills.first(where: { $0.id == billId && $0.isActive }) {
                markBillPaid(bill: bill, actualAmount: bill.amount, updateEstimatedAmount: false)
            }
        }
    }

    private func setupSystemTimeObservers() {
        // PRD §9.3 Trigger #4: Rebuild notification queue on timezone or system clock changes
        let tzObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.diagnostics.log(category: "Clock", message: "Zona waktu berubah: menyusun ulang antrean notifikasi")
                self?.refreshSystemStatusAndSyncNotifications()
            }
        }
        let clockObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.diagnostics.log(category: "Clock", message: "Jam perangkat berubah: menyusun ulang antrean notifikasi")
                self?.refreshSystemStatusAndSyncNotifications()
            }
        }
        let externalObserver = NotificationCenter.default.addObserver(
            forName: .plaExternalDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.reloadAllData()
                await self?.syncNotificationQueueNow()
            }
        }
        let ocrObserver = NotificationCenter.default.addObserver(
            forName: .plaPendingOCRReceiptArrived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.consumePendingOCRReceiptIfAny()
            }
        }
        systemObservers = [tzObserver, clockObserver, externalObserver, ocrObserver]
    }

    // MARK: - Pasca-MVP Helpers (P-01, P-03, P-08, P-09)

    func createTaskFromNaturalLanguage(_ phrase: String) {
        let parsed = NaturalLanguageTaskParser.parse(phrase, today: today, categories: categories)
        guard PLATask.isValidTitle(parsed.title) else { return }
        createOrUpdateTask(
            existing: nil,
            title: parsed.title,
            notes: nil,
            dueDate: parsed.dueDate,
            dueTimeMinutes: parsed.dueTimeMinutes,
            priority: parsed.priority,
            categoryId: parsed.matchedCategoryId ?? defaultTaskCategory?.id,
            recurrenceRule: nil
        )
        showToast("Tugas \"\(parsed.title)\" ditambahkan")
    }

    func saveSavingsGoal(_ goal: SavingsGoal) {
        guard let store else { return }
        do {
            try store.saveSavingsGoal(goal)
            reloadAllData()
            showToast("Target tabungan tersimpan")
        } catch {
            diagnostics.log(level: "ERROR", category: "SavingsGoal", message: "Gagal menyimpan target tabungan: \(error.localizedDescription)")
        }
    }

    func adjustSavingsGoal(_ goal: SavingsGoal, delta: Int64) {
        var updated = goal
        updated.currentAmount = max(Int64(0), goal.currentAmount + delta)
        updated.status = updated.currentAmount >= updated.targetAmount ? .achieved : .active
        updated.updatedAt = clock.now
        saveSavingsGoal(updated)
    }

    func deleteSavingsGoal(id: UUID) {
        guard let store else { return }
        do {
            try store.deleteSavingsGoal(id: id)
            reloadAllData()
        } catch {
            diagnostics.log(level: "ERROR", category: "SavingsGoal", message: "Gagal menghapus target tabungan: \(error.localizedDescription)")
        }
    }

    func acceptPersonalSuggestion(_ suggestion: PersonalSuggestion) {
        switch suggestion.kind {
        case .productiveTimeBlock(let block, _, _):
            updateSettings { $0.preferredReminderMinutes = block.suggestedReminderMinutes }
            showToast("Jam default pengingat diatur ke \(PLAFormatters.time24(block.suggestedReminderMinutes))")
        case .categoryLatenessHabit(let catId, let name, _, _):
            updateSettings { $0.extraEarlyReminderDaysByCategory[catId.uuidString] = 1 }
            showToast("Pengingat kategori \(name) dimajukan 1 hari lebih awal")
        }
        dismissedPersonalSuggestionIds.insert(suggestion.id)
    }

    func dismissPersonalSuggestion(_ suggestion: PersonalSuggestion) {
        dismissedPersonalSuggestionIds.insert(suggestion.id)
    }

    func calendarEventCountsForNext7Days() -> [LocalDate: Int] {
        guard settings.useCalendarForReschedule else { return [:] }
        return calendarService.eventCountsForNext7Days(from: today, timeZone: clock.timeZone)
    }

    // MARK: - Appearance & Real-Data UI Telemetry

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        settingsStore.saveAppearanceMode(mode)
    }

    /// Real local daily expense totals over the last `days` calendar days ending on `today`.
    func dailyExpenseSeries(days: Int) -> [PLADailyMetricPoint] {
        let count = max(days, 2)
        let start = today.addingDays(-(count - 1))
        var totalsByDate: [LocalDate: Int64] = [:]
        for tx in transactions where tx.type == .expense && tx.dateLocal >= start && tx.dateLocal <= today {
            totalsByDate[tx.dateLocal, default: 0] += tx.amount
        }
        return (0..<count).map { offset in
            let date = start.addingDays(offset)
            let axisLabel: String
            if count <= 7 {
                axisLabel = PLAFormatters.shortWeekday(date.weekdayISO)
            } else {
                axisLabel = "\(date.day)"
            }
            return PLADailyMetricPoint(
                date: date,
                axisLabel: axisLabel,
                amount: totalsByDate[date] ?? 0,
                isToday: date == today
            )
        }
    }

    /// Real local daily expense totals from the start of the active budget cycle up to `today`.
    func cycleDailyExpenseSeries() -> [PLADailyMetricPoint] {
        let period = activePeriod
        let spanDays = max(1, period.start.days(until: today) + 1)
        let effectiveCount = min(spanDays, 31)
        let start = today.addingDays(-(effectiveCount - 1))
        var totalsByDate: [LocalDate: Int64] = [:]
        for tx in transactions where tx.type == .expense && tx.dateLocal >= start && tx.dateLocal <= today {
            totalsByDate[tx.dateLocal, default: 0] += tx.amount
        }
        return (0..<effectiveCount).map { offset in
            let date = start.addingDays(offset)
            return PLADailyMetricPoint(
                date: date,
                axisLabel: "\(date.day)",
                amount: totalsByDate[date] ?? 0,
                isToday: date == today
            )
        }
    }

    /// Real 7-day task completion breakdown for the expandable Overview ring card.
    func last7DaysTaskProgress() -> (points: [PLADailyRingPoint], completedDays: Int, scheduledDays: Int) {
        let start = today.addingDays(-6)
        var points: [PLADailyRingPoint] = []
        var completedDays = 0
        var scheduledDays = 0

        for offset in 0..<7 {
            let date = start.addingDays(offset)
            let dayTasks = tasks.filter { task in
                if task.dueDateLocal == date { return true }
                if task.status == .completed,
                   let doneAt = task.completedAt,
                   LocalDate.from(date: doneAt, timeZone: clock.timeZone) == date {
                    return true
                }
                return false
            }
            let total = dayTasks.count
            let done = dayTasks.filter { $0.status == .completed }.count
            let progress: Double = total > 0 ? Double(done) / Double(total) : 0
            if total > 0 {
                scheduledDays += 1
                if done == total {
                    completedDays += 1
                }
            }
            points.append(PLADailyRingPoint(
                date: date,
                letter: PLAFormatters.singleLetterWeekday(date.weekdayISO),
                completedCount: done,
                totalCount: total,
                progress: progress,
                isToday: date == today
            ))
        }
        return (points, completedDays, scheduledDays)
    }

    /// Tasks due on a specific local date, ordered chronologically by time-of-day then priority.
    func tasksScheduled(on date: LocalDate) -> [PLATask] {
        tasks
            .filter { $0.dueDateLocal == date }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status == .active
                }
                let lTime = lhs.dueTimeMinutes ?? Int.max
                let rTime = rhs.dueTimeMinutes ?? Int.max
                if lTime != rTime { return lTime < rTime }
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
    }

    /// Set of dates inside a given 7-day slice that have at least one active task scheduled.
    func datesWithActiveTasks(in dates: [LocalDate]) -> Set<LocalDate> {
        let set = Set(dates)
        var result: Set<LocalDate> = []
        for task in tasks where task.status == .active {
            if let due = task.dueDateLocal, set.contains(due) {
                result.insert(due)
            }
        }
        return result
    }
}

struct PLADailyMetricPoint: Identifiable, Hashable {
    var id: String { date.isoString }
    let date: LocalDate
    let axisLabel: String
    let amount: Int64
    let isToday: Bool
}

struct PLADailyRingPoint: Identifiable, Hashable {
    var id: String { date.isoString }
    let date: LocalDate
    let letter: String
    let completedCount: Int
    let totalCount: Int
    let progress: Double
    let isToday: Bool
}
