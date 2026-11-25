import XCTest
@testable import PLACore

final class BudgetAndInsightEngineTests: XCTestCase {
    private let accCash = Account(name: "Tunai", type: .cash, initialBalance: 500_000, isDefault: true)
    private let accBank = Account(name: "BCA", type: .bank, initialBalance: 5_000_000)
    private let catFood = Category(name: "Makan & Minum", scope: .expense)
    private let catTransport = Category(name: "Transportasi", scope: .expense)
    private let catBills = Category(name: "Tagihan & Utilitas", scope: .expense)
    private let catSalary = Category(name: "Gaji", scope: .income)

    func testPRDExample1NearLimitExactNumbers() {
        // PRD §10.1 Contoh 1:
        // B = 3.000.000, P = 30 (Nov 2026), d = 26 (sisaHari = 5, hariSetelahIni = 4)
        // E_bill_paid = 1.200.000 (1 tx), E_var = 1.500.000 (21 tx: Makan 900.000 + Transport 600.000) -> 22 expense tx total
        // E_bill_due = 0
        let today = LocalDate(year: 2026, month: 11, day: 26)!
        let billId = UUID()
        var txs: [PLATransaction] = [
            PLATransaction(type: .expense, amount: 1_200_000, accountId: accBank.id, categoryId: catBills.id, billId: billId, dateLocal: LocalDate(year: 2026, month: 11, day: 1)!)
        ]
        // 15 food transactions * 60.000 = 900.000
        for i in 1...15 {
            txs.append(PLATransaction(type: .expense, amount: 60_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: i)!))
        }
        // 6 transport transactions * 100.000 = 600.000
        for i in 16...21 {
            txs.append(PLATransaction(type: .expense, amount: 100_000, accountId: accCash.id, categoryId: catTransport.id, dateLocal: LocalDate(year: 2026, month: 11, day: i)!))
        }

        let budget = Budget(categoryId: nil, amount: 3_000_000, effectiveFromMonth: "2026-11")
        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: txs,
            budgets: [budget],
            bills: [],
            categories: [catFood, catTransport, catBills]
        )

        XCTAssertEqual(summary.period.totalDays, 30)
        XCTAssertEqual(summary.period.currentDay, 26)
        XCTAssertEqual(summary.period.remainingDaysInclusive, 5)
        XCTAssertEqual(summary.period.remainingDaysAfterToday, 4)
        XCTAssertEqual(summary.totalExpense, 2_700_000)
        XCTAssertEqual(summary.paidBillsExpense, 1_200_000)
        XCTAssertEqual(summary.variableExpense, 1_500_000)
        XCTAssertEqual(summary.remainingBudget, 300_000)
        XCTAssertEqual(summary.freeRemainingBudget, 300_000)
        XCTAssertEqual(summary.safeDailyLimit, 60_000)
        XCTAssertEqual(summary.forecastTotal, 2_930_769)
        XCTAssertTrue(summary.isForecastReady)
        XCTAssertEqual(summary.budgetStatus, .warning)

        let insights = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood, catTransport, catBills]
        )
        let ruleCodes = insights.map(\.ruleCode)
        XCTAssertTrue(ruleCodes.contains(.budgetNearLimit))
        XCTAssertTrue(ruleCodes.contains(.categoryDominance))
        XCTAssertFalse(ruleCodes.contains(.forecastOverBudget))
    }

    func testPRDExample2ColdStartAndEarlyMonthRentPreventsFalseAlarm() {
        // PRD §10.1 Contoh 2:
        // B = 3.000.000, P = 30, d = 2 (Nov 2), E_bill_paid = 1.500.000, E_var = 80.000 (2 tx), E_bill_due = 350.000
        let today = LocalDate(year: 2026, month: 11, day: 2)!
        let paidBillId = UUID()
        let txs = [
            PLATransaction(type: .expense, amount: 1_500_000, accountId: accBank.id, categoryId: catBills.id, billId: paidBillId, dateLocal: LocalDate(year: 2026, month: 11, day: 1)!),
            PLATransaction(type: .expense, amount: 40_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: 1)!),
            PLATransaction(type: .expense, amount: 40_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: 2)!)
        ]
        let unpaidInternet = Bill(
            name: "Internet",
            amount: 350_000,
            nextDueDateLocal: LocalDate(year: 2026, month: 11, day: 15)!,
            recurrenceRuleId: UUID(),
            defaultAccountId: accBank.id,
            categoryId: catBills.id
        )
        let budget = Budget(categoryId: nil, amount: 3_000_000, effectiveFromMonth: "2026-11")

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: txs,
            budgets: [budget],
            bills: [unpaidInternet],
            categories: [catFood, catBills]
        )

        XCTAssertFalse(summary.isForecastReady)
        XCTAssertEqual(summary.unpaidBillsDue, 350_000)
        XCTAssertEqual(summary.freeRemainingBudget, 1_070_000)
        XCTAssertEqual(summary.period.remainingDaysInclusive, 29)
        XCTAssertEqual(summary.safeDailyLimit, 36_896) // floor(1.070.000 / 29)

        let insights = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood, catBills]
        )
        XCTAssertFalse(insights.contains { $0.ruleCode == .forecastOverBudget })
        XCTAssertFalse(insights.contains { $0.ruleCode == .fastBurnPace })
    }

    func testTransferDoesNotAffectBudgetOrExpense() {
        // AC-07.3 & AC-09.2
        let today = LocalDate(year: 2026, month: 11, day: 15)!
        let transfer = PLATransaction(type: .transfer, amount: 1_000_000, accountId: accBank.id, destinationAccountId: accCash.id, dateLocal: today)
        let adminFee = PLATransaction(type: .expense, amount: 2_500, accountId: accBank.id, categoryId: catBills.id, dateLocal: today, note: "Biaya Admin")
        let budget = Budget(categoryId: nil, amount: 2_000_000, effectiveFromMonth: "2026-11")

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: [transfer, adminFee],
            budgets: [budget],
            bills: [],
            categories: [catBills]
        )

        XCTAssertEqual(summary.totalExpense, 2_500)
        XCTAssertEqual(summary.remainingBudget, 1_997_500)
    }

    func testCustomCycleStartDay25() {
        // AC-09.3: On Nov 10 with cycle start 25 -> period is Oct 25 .. Nov 24
        let p1 = BudgetPeriod.current(for: LocalDate(year: 2026, month: 11, day: 10)!, cycleStartDay: 25)
        XCTAssertEqual(p1.start, LocalDate(year: 2026, month: 10, day: 25))
        XCTAssertEqual(p1.end, LocalDate(year: 2026, month: 11, day: 24))
        XCTAssertEqual(p1.totalDays, 31)
        XCTAssertEqual(p1.currentDay, 17)

        // On Nov 26 with cycle start 25 -> period is Nov 25 .. Dec 24
        let p2 = BudgetPeriod.current(for: LocalDate(year: 2026, month: 11, day: 26)!, cycleStartDay: 25)
        XCTAssertEqual(p2.start, LocalDate(year: 2026, month: 11, day: 25))
        XCTAssertEqual(p2.end, LocalDate(year: 2026, month: 12, day: 24))
        XCTAssertEqual(p2.totalDays, 30)
        XCTAssertEqual(p2.currentDay, 2)
    }

    func testPostDatedTransactionExcludedUntilDateArrives() {
        // PRD §12
        let today = LocalDate(year: 2026, month: 11, day: 10)!
        let pastTx = PLATransaction(type: .expense, amount: 100_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: 5)!)
        let futureTx = PLATransaction(type: .expense, amount: 500_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: 20)!)

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: [pastTx, futureTx],
            budgets: [],
            bills: [],
            categories: [catFood]
        )
        XCTAssertEqual(summary.totalExpense, 100_000)
        XCTAssertEqual(summary.budgetStatus, .notSet)
        XCTAssertNil(summary.percentUsed)
        XCTAssertNil(summary.safeDailyLimit)
    }

    func testBudgetExceededForecastAndPaceAndCategoryRules() {
        let today = LocalDate(year: 2026, month: 11, day: 10)! // d=10, P=30
        var txs: [PLATransaction] = []
        // 6 food expenses * 250.000 = 1.500.000 (> budget 1.000.000!)
        for i in 1...6 {
            txs.append(PLATransaction(type: .expense, amount: 250_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: i)!))
        }
        let totalBudget = Budget(categoryId: nil, amount: 1_000_000, effectiveFromMonth: "2026-11")
        let foodBudget = Budget(categoryId: catFood.id, amount: 800_000, effectiveFromMonth: "2026-11")

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: txs,
            budgets: [totalBudget, foodBudget],
            bills: [],
            categories: [catFood]
        )
        XCTAssertEqual(summary.budgetStatus, .exceeded)
        XCTAssertEqual(summary.safeDailyLimit, 0)

        let allInsights = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood],
            maxCards: 10
        )
        let codes = Set(allInsights.map(\.ruleCode))
        XCTAssertTrue(codes.contains(.budgetExceeded))
        XCTAssertTrue(codes.contains(.forecastOverBudget))
        XCTAssertTrue(codes.contains(.fastBurnPace))
        XCTAssertTrue(codes.contains(.categoryBudgetNearLimit))

        // Max 3 cards enforced by default (§10.1 anti-spam)
        let capped = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood]
        )
        XCTAssertEqual(capped.count, 3)
        XCTAssertEqual(capped.first?.severity, .critical)
    }

    func testHistoricalSpikeRuleRFIN05b() {
        let today = LocalDate(year: 2026, month: 11, day: 20)!
        var txs: [PLATransaction] = []
        // Previous month (Oct 2026): 10 food transactions of 20.000 = 200.000 (satisfies >= 10 tx cold start!)
        for i in 1...10 {
            txs.append(PLATransaction(type: .expense, amount: 20_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 10, day: i)!))
        }
        // Current month (Nov 2026): 350.000 in food (> 130% of 200k = 260k, and diff 150k >= 50k)
        for i in 1...5 {
            txs.append(PLATransaction(type: .expense, amount: 70_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: LocalDate(year: 2026, month: 11, day: i)!))
        }

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: txs,
            budgets: [],
            bills: [],
            categories: [catFood]
        )
        let insights = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood],
            maxCards: 10
        )
        XCTAssertTrue(insights.contains { $0.ruleCode == .categoryHistoricalSpike && $0.subjectId == catFood.id })
    }

    func testDismissedInsightIsHiddenUnlessSeverityEscalates() {
        let today = LocalDate(year: 2026, month: 11, day: 15)!
        let txs = [
            PLATransaction(type: .expense, amount: 1_200_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: today)
        ]
        let budget = Budget(categoryId: nil, amount: 1_000_000, effectiveFromMonth: "2026-11")
        let summary = BudgetCalculator.summarize(today: today, cycleStartDay: 1, transactions: txs, budgets: [budget], bills: [], categories: [catFood])

        let dismissedCritical = InsightRecord(
            ruleCode: InsightRuleCode.budgetExceeded.rawValue,
            periodKey: "2026-11",
            subjectId: nil,
            severity: .critical,
            dismissedAt: Date()
        )
        let afterDismiss = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood],
            existingRecords: [dismissedCritical]
        )
        XCTAssertFalse(afterDismiss.contains { $0.ruleCode == .budgetExceeded })

        // If a lower-severity dismissal existed, higher severity still shows (AC-11.4)
        let dismissedLower = InsightRecord(
            ruleCode: InsightRuleCode.budgetExceeded.rawValue,
            periodKey: "2026-11",
            subjectId: nil,
            severity: .high,
            dismissedAt: Date()
        )
        let afterEscalate = InsightEngine.evaluate(
            summary: summary,
            today: today,
            cycleStartDay: 1,
            allTransactions: txs,
            categories: [catFood],
            existingRecords: [dismissedLower]
        )
        XCTAssertTrue(afterEscalate.contains { $0.ruleCode == .budgetExceeded })
    }

    func testAccountBalancesAllowNegativeAndHandleTransfersAndArchiving() {
        let archived = Account(name: "Lama", type: .ewallet, initialBalance: 100_000, isArchived: true)
        let date = LocalDate(year: 2026, month: 11, day: 26)!
        let txs = [
            PLATransaction(type: .expense, amount: 600_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: date), // cash goes -100k
            PLATransaction(type: .transfer, amount: 500_000, accountId: accBank.id, destinationAccountId: accCash.id, dateLocal: date), // bank 4.5M, cash +400k
            PLATransaction(type: .income, amount: 1_000_000, accountId: accBank.id, categoryId: catSalary.id, dateLocal: date) // bank 5.5M
        ]

        XCTAssertEqual(AccountBalanceCalculator.balance(for: accCash, transactions: txs), 400_000)
        XCTAssertEqual(AccountBalanceCalculator.balance(for: accBank, transactions: txs), 5_500_000)
        // Only active accounts included in liquid wealth
        XCTAssertEqual(AccountBalanceCalculator.totalLiquidWealth(accounts: [accCash, accBank, archived], transactions: txs), 5_900_000)

        // Negative balance check (§12)
        let hugeExpense = [PLATransaction(type: .expense, amount: 750_000, accountId: accCash.id, categoryId: catFood.id, dateLocal: date)]
        XCTAssertEqual(AccountBalanceCalculator.balance(for: accCash, transactions: hugeExpense), -250_000)
    }
}
