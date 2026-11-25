import XCTest
@testable import PLACore

final class EdgeCasesAndClockTests: XCTestCase {
    func testFixedClockAndSystemClockProperties() {
        let dt = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 26)!, hour: 9, minute: 30)
        let wib = TimeZone(secondsFromGMT: 7 * 3600)!
        let clock = FixedClock(localDateTime: dt, timeZone: wib)
        XCTAssertEqual(clock.today, dt.date)
        XCTAssertEqual(clock.currentLocalDateTime, dt)
        XCTAssertEqual(clock.calendar.firstWeekday, 2)

        let sys = SystemClock()
        XCTAssertEqual(sys.calendar.firstWeekday, 2)
        _ = sys.now
    }

    func testLocalDateAndDateTimeCodableFailurePaths() {
        let badDate = Data("\"2026-02-30\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LocalDate.self, from: badDate))

        let badDateTime = Data("\"2026-11-26T25:99\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LocalDateTime.self, from: badDateTime))
    }

    func testLocalDateMonthArithmeticNegativeAndZeroAnchor() {
        let mar31 = LocalDate(year: 2026, month: 3, day: 31)!
        XCTAssertEqual(mar31.addingMonths(-1, anchorDay: 31), LocalDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(mar31.addingMonths(-3, anchorDay: 31), LocalDate(year: 2025, month: 12, day: 31))
        XCTAssertEqual(mar31.addingMonths(-1), LocalDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(mar31.addingYears(-1), LocalDate(year: 2025, month: 3, day: 31))
        XCTAssertEqual(mar31.addingYears(1, anchorMonth: 2, anchorDay: -1), LocalDate(year: 2027, month: 2, day: 28))
    }

    func testTaskOverdueAllDayVsTimed() {
        let today = LocalDate(year: 2026, month: 11, day: 26)!
        let nowNoon = LocalDateTime(date: today, hour: 12, minute: 0)

        let allDayToday = PLATask(title: "Hari ini", dueDateLocal: today, dueTimeMinutes: nil)
        XCTAssertFalse(allDayToday.isOverdue(at: nowNoon))

        let allDayYesterday = PLATask(title: "Kemarin", dueDateLocal: today.addingDays(-1), dueTimeMinutes: nil)
        XCTAssertTrue(allDayYesterday.isOverdue(at: nowNoon))

        let timedMorning = PLATask(title: "Pagi", dueDateLocal: today, dueTimeMinutes: 9 * 60)
        XCTAssertTrue(timedMorning.isOverdue(at: nowNoon))

        let timedEvening = PLATask(title: "Sore", dueDateLocal: today, dueTimeMinutes: 17 * 60)
        XCTAssertFalse(timedEvening.isOverdue(at: nowNoon))

        let doneYesterday = PLATask(title: "Done", dueDateLocal: today.addingDays(-1), status: .completed)
        XCTAssertFalse(doneYesterday.isOverdue(at: nowNoon))
    }

    func testBillOverdueAndDueWithin7Days() {
        let today = LocalDate(year: 2026, month: 11, day: 26)!
        let ruleId = UUID(), accId = UUID(), catId = UUID()

        let overdue = Bill(name: "Air", amount: 80_000, nextDueDateLocal: today.addingDays(-1), recurrenceRuleId: ruleId, defaultAccountId: accId, categoryId: catId)
        let in5Days = Bill(name: "Kos", amount: 1_500_000, nextDueDateLocal: today.addingDays(5), recurrenceRuleId: ruleId, defaultAccountId: accId, categoryId: catId)
        let in10Days = Bill(name: "Netflix", amount: 120_000, nextDueDateLocal: today.addingDays(10), recurrenceRuleId: ruleId, defaultAccountId: accId, categoryId: catId)
        let inactive = Bill(name: "Lama", amount: 50_000, nextDueDateLocal: today.addingDays(-2), recurrenceRuleId: ruleId, defaultAccountId: accId, categoryId: catId, isActive: false)

        XCTAssertTrue(overdue.isOverdue(on: today))
        XCTAssertTrue(overdue.isDueWithin(days: 7, from: today))
        XCTAssertFalse(in5Days.isOverdue(on: today))
        XCTAssertTrue(in5Days.isDueWithin(days: 7, from: today))
        XCTAssertFalse(in10Days.isDueWithin(days: 7, from: today))
        XCTAssertFalse(inactive.isOverdue(on: today))
        XCTAssertFalse(inactive.isDueWithin(days: 7, from: today))
    }

    func testSameDayQuietHoursWindow() {
        var settings = UserSettings.default
        settings.quietStartMinutes = 13 * 60
        settings.quietEndMinutes = 15 * 60
        let fire = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 26)!, hour: 13, minute: 30)
        let shifted = ReminderPlanner.adjustForQuietHours(fire, deadline: nil, settings: settings)
        XCTAssertEqual(shifted.isoString, "2026-11-26T15:00")

        settings.quietHoursEnabled = false
        XCTAssertEqual(ReminderPlanner.adjustForQuietHours(fire, deadline: nil, settings: settings), fire)
    }

    func testNotificationQueueNoOverflowGuardWhen55thSlotAfter7Days() {
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 1)!, hour: 8, minute: 0)
        var tasks: [PLATask] = []
        var reminders: [Reminder] = []

        // 70 reminders spread evenly across days 1..25 -> slot #55 is well after day 7!
        for i in 0..<70 {
            let dayOffset = (i / 3) + 1
            let dueDate = now.date.addingDays(dayOffset)
            let task = PLATask(title: "Spread #\(i)", dueDateLocal: dueDate)
            tasks.append(task)
            reminders.append(Reminder(
                ownerType: .task,
                ownerId: task.id,
                triggerType: .manual,
                fireDateLocal: LocalDateTime(date: dueDate, hour: 9 + (i % 3), minute: 0)
            ))
        }

        var settings = UserSettings.default
        settings.morningDigestEnabled = false
        let plan = NotificationQueuePlanner.buildQueue(now: now, tasks: tasks, bills: [], reminders: reminders, settings: settings)
        XCTAssertEqual(plan.count, 55)
        XCTAssertFalse(plan.overflowGuardInserted)
        XCTAssertEqual(plan.totalCandidatesInHorizon, 70)
    }

    func testForecastColdStartBoundaryDay4VsDay5AndTx4VsTx5() {
        let acc = Account(name: "Cash", type: .cash)
        let cat = Category(name: "Makan", scope: .expense)
        let budget = Budget(categoryId: nil, amount: 1_000_000, effectiveFromMonth: "2026-11")

        // Day 4 with 5 tx -> NOT ready
        let txs5 = (1...5).map { i in
            PLATransaction(type: .expense, amount: 100_000, accountId: acc.id, categoryId: cat.id, dateLocal: LocalDate(year: 2026, month: 11, day: min(i, 4))!)
        }
        let sDay4 = BudgetCalculator.summarize(today: LocalDate(year: 2026, month: 11, day: 4)!, cycleStartDay: 1, transactions: txs5, budgets: [budget], bills: [], categories: [cat])
        XCTAssertFalse(sDay4.isForecastReady)

        // Day 5 with 4 tx -> NOT ready
        let sTx4 = BudgetCalculator.summarize(today: LocalDate(year: 2026, month: 11, day: 5)!, cycleStartDay: 1, transactions: Array(txs5.prefix(4)), budgets: [budget], bills: [], categories: [cat])
        XCTAssertFalse(sTx4.isForecastReady)

        // Day 5 with 5 tx -> READY!
        let sReady = BudgetCalculator.summarize(today: LocalDate(year: 2026, month: 11, day: 5)!, cycleStartDay: 1, transactions: txs5, budgets: [budget], bills: [], categories: [cat])
        XCTAssertTrue(sReady.isForecastReady)
    }

    func testBudgetEffectiveFromMonthHistoryIsolation() {
        // Changing budget effective 2026-11 must not alter 2026-10 effective budget
        let octBudget = Budget(categoryId: nil, amount: 2_000_000, effectiveFromMonth: "2026-10")
        let novBudget = Budget(categoryId: nil, amount: 3_500_000, effectiveFromMonth: "2026-11")

        let resolvedOct = BudgetCalculator.resolveEffectiveBudget(categoryId: nil, periodKey: "2026-10", budgets: [octBudget, novBudget])
        let resolvedNov = BudgetCalculator.resolveEffectiveBudget(categoryId: nil, periodKey: "2026-11", budgets: [octBudget, novBudget])
        let resolvedDec = BudgetCalculator.resolveEffectiveBudget(categoryId: nil, periodKey: "2026-12", budgets: [octBudget, novBudget])

        XCTAssertEqual(resolvedOct?.amount, 2_000_000)
        XCTAssertEqual(resolvedNov?.amount, 3_500_000)
        XCTAssertEqual(resolvedDec?.amount, 3_500_000)
    }

    func testBackupErrorUserMessagesNonEmpty() {
        let errors: [BackupCodecError] = [
            .invalidJSON,
            .unsupportedFutureVersion(found: 2, maxSupported: 1),
            .checksumMismatch,
            .invalidSchemaVersion
        ]
        for err in errors {
            XCTAssertFalse(err.userMessage.isEmpty)
        }
    }

    func testUserSettingsClampsCycleDayAndMinutes() {
        let s = UserSettings(quietStartMinutes: -10, quietEndMinutes: 9999, budgetCycleStartDay: 31)
        XCTAssertEqual(s.quietStartMinutes, 0)
        XCTAssertEqual(s.quietEndMinutes, 1439)
        XCTAssertEqual(s.budgetCycleStartDay, 28)
    }

    func testCategorySuggesterExcludesArchivedCategories() {
        let archived = Category(name: "Kopi Lama", scope: .expense, isArchived: true)
        let active = Category(name: "Makan", scope: .expense, isArchived: false)
        let acc = UUID()
        let d = LocalDate(year: 2026, month: 11, day: 10)!
        let history = [
            PLATransaction(type: .expense, amount: 25_000, accountId: acc, categoryId: archived.id, dateLocal: d, note: "Kopi"),
            PLATransaction(type: .expense, amount: 25_000, accountId: acc, categoryId: archived.id, dateLocal: d, note: "Kopi")
        ]
        let suggested = CategorySuggester.suggestCategories(forNote: "Kopi", scope: .expense, transactions: history, categories: [archived, active])
        XCTAssertFalse(suggested.contains { $0.id == archived.id })
    }

    func testRecurrenceWeeklyFallbackWhenMaskIsZeroOrNil() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdaysMask: nil)
        let start = LocalDate(year: 2026, month: 11, day: 1)!
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: start, rule: rule), LocalDate(year: 2026, month: 11, day: 15))
    }

    func testReminderPlannerReturnsEmptyForTaskWithoutDueDateOrCompleted() {
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 1)!, hour: 8, minute: 0)
        let noDue = PLATask(title: "Kapan saja", dueDateLocal: nil)
        let done = PLATask(title: "Done", dueDateLocal: LocalDate(year: 2026, month: 11, day: 10)!, status: .completed)
        XCTAssertTrue(ReminderPlanner.planTaskReminders(for: noDue, now: now, settings: .default).isEmpty)
        XCTAssertTrue(ReminderPlanner.planTaskReminders(for: done, now: now, settings: .default).isEmpty)
    }

    func testTransactionMissingDestinationThrows() {
        let tx = PLATransaction(type: .transfer, amount: 50_000, accountId: UUID(), destinationAccountId: nil, dateLocal: LocalDate(year: 2026, month: 11, day: 26)!)
        XCTAssertThrowsError(try tx.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .missingDestinationAccount)
        }
    }
}
