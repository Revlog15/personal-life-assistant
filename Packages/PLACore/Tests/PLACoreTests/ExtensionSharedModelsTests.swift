import XCTest
@testable import PLACore

final class ExtensionSharedModelsTests: XCTestCase {
    func testWidgetSnapshotBuilderPrioritizesOverdueTasksRespectsMaskingAndFindsNearestDeadline() {
        let today = LocalDate(year: 2026, month: 11, day: 26)!
        let now = LocalDateTime(date: today, minutesFromMidnight: 10 * 60)
        let fixedDate = Date(timeIntervalSince1970: 1_795_687_200)

        let acc = Account(name: "BCA", type: .bank, initialBalance: 5_000_000, isDefault: true, createdAt: fixedDate)
        let catFood = PLACategory(name: "Makan & Minum", scope: .expense)
        let catBills = PLACategory(name: "Tagihan", scope: .expense)
        let budget = Budget(categoryId: nil, amount: 3_000_000, effectiveFromMonth: "2026-11", isActive: true, createdAt: fixedDate, updatedAt: fixedDate)
        let tx = PLATransaction(type: .expense, amount: 1_200_000, accountId: acc.id, categoryId: catFood.id, dateLocal: today, note: "Makan", createdAt: fixedDate, updatedAt: fixedDate)
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, anchorDayOfMonth: 28)
        let bill = Bill(
            name: "Internet Biznet",
            amount: 350_000,
            nextDueDateLocal: LocalDate(year: 2026, month: 11, day: 28)!,
            recurrenceRuleId: rule.id,
            defaultAccountId: acc.id,
            categoryId: catBills.id,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let tOverdue = PLATask(title: "Kirim laporan", dueDateLocal: today.addingDays(-1), priority: .medium, createdAt: fixedDate, updatedAt: fixedDate)
        let tTodayHigh = PLATask(title: "Rapat penting", dueDateLocal: today, dueTimeMinutes: 14 * 60, priority: .high, createdAt: fixedDate, updatedAt: fixedDate)
        let tTodayLow = PLATask(title: "Beli air", dueDateLocal: today, dueTimeMinutes: 18 * 60, priority: .low, createdAt: fixedDate, updatedAt: fixedDate)

        var settings = UserSettings()
        settings.financeLockEnabled = true
        settings.showBudgetStatusWhenLocked = true

        let summary = BudgetCalculator.summarize(
            today: today,
            cycleStartDay: 1,
            transactions: [tx],
            budgets: [budget],
            bills: [bill],
            categories: [catFood, catBills]
        )

        let snapshot = WidgetSnapshotBuilder.build(
            today: today,
            now: now,
            summary: summary,
            tasks: [tTodayLow, tTodayHigh, tOverdue],
            bills: [bill],
            settings: settings,
            generatedAt: fixedDate
        )

        XCTAssertTrue(snapshot.maskAmounts)
        XCTAssertTrue(snapshot.hasBudget)
        XCTAssertEqual(snapshot.budgetTotal, 3_000_000)
        XCTAssertEqual(snapshot.spentTotal, 1_200_000)
        XCTAssertEqual(snapshot.overdueTaskCount, 1)
        XCTAssertEqual(snapshot.todayTaskCount, 2)
        XCTAssertEqual(snapshot.todayTasks.first?.title, "Kirim laporan")
        XCTAssertTrue(snapshot.todayTasks.first?.isOverdue == true)
        XCTAssertEqual(snapshot.todayTasks[1].title, "Rapat penting")
        XCTAssertEqual(snapshot.upcomingBills.count, 1)
        XCTAssertEqual(snapshot.upcomingBills.first?.name, "Internet Biznet")
        XCTAssertEqual(snapshot.nearestDeadline?.title, "Kirim laporan")
        XCTAssertTrue(snapshot.nearestDeadline?.isOverdue == true)

        // Codable round-trip
        let encoded = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(PLAWidgetSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snapshot)
    }

    func testURLRouteOCRDraftRoundTripAndTabRoutes() {
        let draftId = UUID()
        let payload = SharedOCRReceiptPayload(
            id: draftId,
            amount: 45_500,
            date: LocalDate(year: 2026, month: 11, day: 26)!,
            merchant: "Kopi Kenangan Sudirman",
            detectedSourceApp: "BCA",
            rawLineCount: 8
        )

        let url = PLAURLRoute.makeOCRDraftURL(payload)
        XCTAssertNotNil(url)
        let parsed = url.flatMap(PLAURLRoute.parse(url:))
        guard case .ocrDraft(let decoded)? = parsed else {
            return XCTFail("Expected ocrDraft route")
        }
        XCTAssertEqual(decoded.id, draftId)
        XCTAssertEqual(decoded.amount, 45_500)
        XCTAssertEqual(decoded.date, LocalDate(year: 2026, month: 11, day: 26))
        XCTAssertEqual(decoded.merchant, "Kopi Kenangan Sudirman")
        XCTAssertEqual(decoded.detectedSourceApp, "BCA")
        XCTAssertEqual(decoded.rawLineCount, 8)

        XCTAssertEqual(PLAURLRoute.parse(url: PLAURLRoute.makeTabURL(.finance)!), .finance)
        XCTAssertEqual(PLAURLRoute.parse(url: PLAURLRoute.makeTabURL(.tasks)!), .tasks)
        XCTAssertEqual(PLAURLRoute.parse(url: PLAURLRoute.makeTabURL(.dashboard)!), .dashboard)
        XCTAssertEqual(PLAURLRoute.parse(url: PLAURLRoute.makeTabURL(.quickAddTask)!), .quickAddTask)
        XCTAssertEqual(PLAURLRoute.parse(url: PLAURLRoute.makeTabURL(.quickAddExpense)!), .quickAddExpense)
        XCTAssertNil(PLAURLRoute.parse(url: URL(string: "https://example.com")!))
    }
}
