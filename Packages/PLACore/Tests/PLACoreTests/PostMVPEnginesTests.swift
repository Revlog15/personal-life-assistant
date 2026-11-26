import XCTest
@testable import PLACore

final class PostMVPEnginesTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 26)!
    private let wib = TimeZone(secondsFromGMT: 7 * 3600)!

    // MARK: - P-03 SavingsGoalCalculator

    func testSavingsGoalProgressAndRequiredDeposits() {
        let goal = SavingsGoal(
            name: "Dana Darurat",
            targetAmount: 12_000_000,
            currentAmount: 3_000_000,
            targetDateLocal: today.addingDays(90) // 3 months
        )
        let progress = SavingsGoalCalculator.evaluate(goal: goal, today: today)
        XCTAssertEqual(progress.percentComplete, 0.25, accuracy: 0.001)
        XCTAssertEqual(progress.remainingAmount, 9_000_000)
        XCTAssertEqual(progress.daysRemaining, 90)
        XCTAssertEqual(progress.requiredMonthlyDeposit, 3_000_000)
        XCTAssertEqual(progress.paceStatus, .onTrack)

        let achieved = SavingsGoal(name: "Laptop", targetAmount: 10_000_000, currentAmount: 10_500_000)
        let doneProg = SavingsGoalCalculator.evaluate(goal: achieved, today: today)
        XCTAssertEqual(doneProg.paceStatus, .achieved)
        XCTAssertEqual(doneProg.remainingAmount, 0)

        let overdue = SavingsGoal(name: "Liburan", targetAmount: 5_000_000, currentAmount: 2_000_000, targetDateLocal: today.addingDays(-5))
        let overdueProg = SavingsGoalCalculator.evaluate(goal: overdue, today: today)
        XCTAssertEqual(overdueProg.paceStatus, .overdue)
        XCTAssertEqual(overdueProg.requiredMonthlyDeposit, 3_000_000)

        let noDate = SavingsGoal(name: "Cadangan", targetAmount: 5_000_000, currentAmount: 1_000_000, targetDateLocal: nil)
        XCTAssertEqual(SavingsGoalCalculator.evaluate(goal: noDate, today: today).paceStatus, .noDeadline)
    }

    // MARK: - P-04 WhatIfSimulator

    func testWhatIfSimulatorBeforeAndAfterImpact() {
        let acc = Account(name: "BCA", type: .bank, initialBalance: 5_000_000)
        let cat = PLACategory(name: "Belanja", scope: .expense)
        let budget = Budget(categoryId: nil, amount: 3_000_000, effectiveFromMonth: "2026-11")
        let txs = (1...5).map { day in
            PLATransaction(type: .expense, amount: 400_000, accountId: acc.id, categoryId: cat.id, dateLocal: LocalDate(year: 2026, month: 11, day: day)!)
        } // total 2.000.000; remaining 1.000.000 for 5 days (Nov 26..30) -> safeDaily = 200.000

        let summary = BudgetCalculator.summarize(today: today, cycleStartDay: 1, transactions: txs, budgets: [budget], bills: [], categories: [cat])
        XCTAssertEqual(summary.safeDailyLimit, 200_000)

        // Planned purchase 500.000 -> remaining 500.000 -> safeDaily drops to 100.000 (tightenDaily)
        let sim1 = WhatIfSimulator.simulatePurchase(summary: summary, plannedAmount: 500_000)
        XCTAssertEqual(sim1.afterTotalExpense, 2_500_000)
        XCTAssertEqual(sim1.afterFreeRemaining, 500_000)
        XCTAssertEqual(sim1.afterSafeDailyLimit, 100_000)
        XCTAssertEqual(sim1.safeDailyDrop, 100_000)
        XCTAssertEqual(sim1.afterBudgetStatus, .warning)
        XCTAssertEqual(sim1.verdict, .tightenDaily)

        // Planned purchase 1.500.000 -> exceeds budget (3.5M > 3M)
        let sim2 = WhatIfSimulator.simulatePurchase(summary: summary, plannedAmount: 1_500_000)
        XCTAssertEqual(sim2.afterBudgetStatus, .exceeded)
        XCTAssertEqual(sim2.afterSafeDailyLimit, 0)
        XCTAssertEqual(sim2.verdict, .exceedsBudget)

        // No budget set
        let noBudgetSummary = BudgetCalculator.summarize(today: today, cycleStartDay: 1, transactions: txs, budgets: [], bills: [], categories: [cat])
        XCTAssertEqual(WhatIfSimulator.simulatePurchase(summary: noBudgetSummary, plannedAmount: 100_000).verdict, .noBudgetSet)
    }

    // MARK: - P-08 Smart Rescheduling (R-PER-03)

    func testSmartReschedulingWeightedWorkloadAndCalendarEvents() {
        let day1 = today.addingDays(1) // 1 High (score 3) + 2 calendar events = 5
        let day2 = today.addingDays(2) // 2 Low (score 2) + 0 calendar events = 2
        let day3 = today.addingDays(3) // 0 tasks + 4 calendar events = 4
        let day4 = today.addingDays(4) // 1 Low (score 1) + 0 calendar events = 1  <-- BEST!

        let tasks = [
            PLATask(title: "H1", dueDateLocal: day1, priority: .high),
            PLATask(title: "L1", dueDateLocal: day2, priority: .low),
            PLATask(title: "L2", dueDateLocal: day2, priority: .low),
            PLATask(title: "L3", dueDateLocal: day4, priority: .low),
            PLATask(title: "M5", dueDateLocal: today.addingDays(5), priority: .medium),
            PLATask(title: "M6", dueDateLocal: today.addingDays(6), priority: .medium),
            PLATask(title: "M7", dueDateLocal: today.addingDays(7), priority: .medium)
        ]

        let calCounts: [LocalDate: Int] = [day1: 2, day3: 4]
        let best = RescheduleSuggester.smartBestDayInNext7Days(from: today, activeTasks: tasks, calendarEventCounts: calCounts)
        XCTAssertEqual(best.date, day4)
        XCTAssertEqual(best.workloadScore, 1)
        XCTAssertEqual(best.lowCount, 1)
        XCTAssertEqual(best.calendarEventCount, 0)
    }

    // MARK: - P-09 Personal Intelligence (R-PER-01 & R-PER-02)

    func testPersonalIntelligenceColdStartAndRules() {
        let now = LocalDateTime(date: today, hour: 12, minute: 0).toDate(timeZone: wib)
        let catKuliah = PLACategory(name: "Kuliah", scope: .task)
        let catKerja = PLACategory(name: "Kerja", scope: .task)

        // Only 10 tasks completed -> below R-PER-01 cold start (15)
        let smallSet = (1...10).map { i in
            PLATask(
                title: "T\(i)",
                dueDateLocal: today.addingDays(-i),
                status: .completed,
                categoryId: catKuliah.id,
                completedAt: LocalDateTime(date: today.addingDays(-i), hour: 9, minute: 0).toDate(timeZone: wib)
            )
        }
        let coldRes = PersonalIntelligenceEngine.evaluate(tasks: smallSet, categories: [catKuliah], now: now, timeZone: wib, settings: .default)
        XCTAssertFalse(coldRes.contains { $0.ruleCode == "R-PER-01" })

        // 16 completed tasks: 12 finished in Morning (08:30 = 75% >= 40%) and 6/10 in Kuliah finished LATE (>= 40%)
        var fullTasks: [PLATask] = []
        for i in 1...10 {
            let due = today.addingDays(-i - 2)
            let isLate = i <= 6
            let completedDay = isLate ? due.addingDays(1) : due
            let completedAt = LocalDateTime(date: completedDay, hour: 8, minute: 30).toDate(timeZone: wib)
            fullTasks.append(PLATask(
                title: "Kuliah \(i)",
                dueDateLocal: due,
                dueTimeMinutes: 9 * 60,
                status: .completed,
                categoryId: catKuliah.id,
                completedAt: completedAt
            ))
        }
        for i in 1...6 {
            let completedAt = LocalDateTime(date: today.addingDays(-i), hour: i <= 2 ? 9 : 16, minute: 0).toDate(timeZone: wib)
            fullTasks.append(PLATask(
                title: "Kerja \(i)",
                dueDateLocal: nil,
                status: .completed,
                categoryId: catKerja.id,
                completedAt: completedAt
            ))
        }

        let suggestions = PersonalIntelligenceEngine.evaluate(
            tasks: fullTasks,
            categories: [catKuliah, catKerja],
            now: now,
            timeZone: wib,
            settings: .default
        )

        XCTAssertTrue(suggestions.contains {
            if case .productiveTimeBlock(let block, let pct, _) = $0.kind {
                return block == .morning && pct >= 40
            }
            return false
        })
        XCTAssertTrue(suggestions.contains {
            if case .categoryLatenessHabit(let catId, _, let pct, _) = $0.kind {
                return catId == catKuliah.id && pct >= 40
            }
            return false
        })

        // Accepting suggestions applies them to ReminderPlanner and silences duplicate suggestions
        var accepted = UserSettings.default
        accepted.preferredReminderMinutes = ProductiveTimeBlock.morning.suggestedReminderMinutes
        accepted.extraEarlyReminderDaysByCategory[catKuliah.id.uuidString] = 1
        let afterAccept = PersonalIntelligenceEngine.evaluate(tasks: fullTasks, categories: [catKuliah, catKerja], now: now, timeZone: wib, settings: accepted)
        XCTAssertTrue(afterAccept.isEmpty)

        // Verify ReminderPlanner respects accepted preferred hour (08:00) and +1 extra early day
        let newTask = PLATask(title: "Makalah", dueDateLocal: today.addingDays(10), priority: .low, categoryId: catKuliah.id)
        let planned = ReminderPlanner.planTaskReminders(for: newTask, now: LocalDateTime(date: today, hour: 8, minute: 0), settings: accepted)
        XCTAssertEqual(planned.map(\.fireDateLocal.isoString), [
            "\(today.addingDays(9).isoString)T08:00",
            "\(today.addingDays(10).isoString)T08:00"
        ])
    }

    // MARK: - P-10 Recurring "From Completion Date"

    func testRecurrenceFromCompletionDateMode() {
        // Motor service every 60 days from completion date (PRD §18 P-10)
        let rule = RecurrenceRule(frequency: .daily, interval: 60, anchorMode: .fromCompletionDate)
        let scheduled = LocalDate(year: 2026, month: 10, day: 1)!
        let completedLate = LocalDate(year: 2026, month: 10, day: 15)!
        let next = RecurrenceEngine.nextOccurrence(after: scheduled, completedOn: completedLate, rule: rule)
        XCTAssertEqual(next, completedLate.addingDays(60))
    }

    // MARK: - P-11 Subscription Trial End Alerts

    func testTrialBillPlansH3AndH1AndUrgentQueueTitle() {
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 1)!, hour: 8, minute: 0)
        let trialEnd = LocalDate(year: 2026, month: 11, day: 14)!
        let trialBill = Bill(
            name: "Apple Music Trial",
            amount: 55_000,
            nextDueDateLocal: trialEnd,
            recurrenceRuleId: UUID(),
            defaultAccountId: UUID(),
            categoryId: UUID(),
            isTrial: true,
            trialEndDateLocal: trialEnd
        )

        let rems = ReminderPlanner.planBillReminders(for: trialBill, now: now, settings: .default)
        XCTAssertEqual(rems.map(\.fireDateLocal.isoString), [
            "2026-11-11T09:00",
            "2026-11-13T09:00"
        ])
        XCTAssertTrue(rems.allSatisfy { $0.soundName == ReminderSound.plaUrgent.rawValue })

        var settings = UserSettings.default
        settings.morningDigestEnabled = false
        let plan = NotificationQueuePlanner.buildQueue(now: now, tasks: [], bills: [trialBill], reminders: rems, settings: settings)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.items.first?.title, "Masa Trial Segera Berakhir")
        XCTAssertTrue(plan.items.first?.body.contains("batalkan sebelum terdebit otomatis") == true)
    }

    // MARK: - Backwards-compatible v1 -> v2 JSON Backup Import

    func testBackupCodecDecodesLegacyV1BackupWithValidChecksum() throws {
        // Construct an authentic v1 payload JSON (without savingsGoals, anchorMode, isTrial, etc.)
        let v1PayloadDict: [String: Any] = [
            "accounts": [],
            "bills": [],
            "budgets": [],
            "categories": [],
            "insights": [],
            "recurrenceRules": [],
            "reminders": [],
            "settings": [
                "autoLockTimeout": 0,
                "billSound": "pla_bill.caf",
                "budgetCycleStartDay": 1,
                "defaultTaskSound": "pla_default.caf",
                "digestSound": "pla_digest.caf",
                "financeLockEnabled": true,
                "hasCompletedOnboarding": true,
                "morningDigestEnabled": true,
                "morningDigestMinutes": 450,
                "quietEndMinutes": 420,
                "quietHoursEnabled": true,
                "quietStartMinutes": 1320,
                "reminderPreferences": [
                    "billEnableDayOf": true, "billEnableH1": true, "billEnableH3": true,
                    "highEnableDayOf": true, "highEnableH1": true, "highEnableH3": true, "highEnableH7": true, "highEnableTwoHoursBefore": true,
                    "lowEnableDayOf": true,
                    "mediumEnableDayOf": true, "mediumEnableH1": true, "mediumEnableH3": true
                ],
                "showBudgetStatusWhenLocked": true,
                "urgentTaskSound": "pla_urgent.caf"
            ],
            "tasks": [],
            "transactions": []
        ]
        let canonicalV1 = try JSONSerialization.data(withJSONObject: v1PayloadDict, options: [.sortedKeys])
        let sha = SHA256.hexDigest(canonicalV1)

        let envelopeDict: [String: Any] = [
            "exportSchemaVersion": 1,
            "exportedAt": "2026-11-26T00:00:00Z",
            "sha256": sha,
            "payload": v1PayloadDict
        ]
        let v1FileData = try JSONSerialization.data(withJSONObject: envelopeDict, options: [.prettyPrinted, .sortedKeys])

        let decoded = BackupCodec.decodeAndValidate(data: v1FileData)
        switch decoded {
        case .success(let preview):
            XCTAssertEqual(preview.exportSchemaVersion, 1)
            XCTAssertEqual(preview.savingsGoalCount, 0)
            XCTAssertTrue(preview.payload.settings.hasCompletedOnboarding)
        case .failure(let err):
            XCTFail("Expected legacy v1 backup to decode cleanly, got \(err)")
        }
    }
}
