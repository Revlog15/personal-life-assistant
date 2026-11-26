import XCTest
@testable import PLACore

final class HelpersAndExportTests: XCTestCase {
    func testRescheduleSuggesterPicksLightestDayInNext7Days() {
        let today = LocalDate(year: 2026, month: 11, day: 26)! // Thursday
        let overdue = PLATask(title: "Terlambat", dueDateLocal: today.addingDays(-2))
        let busy1 = PLATask(title: "B1", dueDateLocal: today.addingDays(1))
        let busy2 = PLATask(title: "B2", dueDateLocal: today.addingDays(1))
        let busy3 = PLATask(title: "B3", dueDateLocal: today.addingDays(2))
        // Day +3 (Sunday Nov 29) has 0 tasks!

        let suggestion = RescheduleSuggester.bestDayInNext7Days(
            from: today,
            activeTasks: [overdue, busy1, busy2, busy3],
            excludingTaskId: overdue.id
        )
        XCTAssertEqual(suggestion.date, today.addingDays(3))
        XCTAssertEqual(suggestion.existingTaskCount, 0)
    }

    func testNextWeekendDate() {
        // Thursday Nov 26 -> Saturday Nov 28
        XCTAssertEqual(RescheduleSuggester.nextWeekendDate(from: LocalDate(year: 2026, month: 11, day: 26)!), LocalDate(year: 2026, month: 11, day: 28))
        // Saturday Nov 28 -> Sunday Nov 29
        XCTAssertEqual(RescheduleSuggester.nextWeekendDate(from: LocalDate(year: 2026, month: 11, day: 28)!), LocalDate(year: 2026, month: 11, day: 29))
        // Sunday Nov 29 -> Next Saturday Dec 5
        XCTAssertEqual(RescheduleSuggester.nextWeekendDate(from: LocalDate(year: 2026, month: 11, day: 29)!), LocalDate(year: 2026, month: 12, day: 5))
    }

    func testCategorySuggesterMatchesNoteAfterTwoHistoricalEntries() {
        // AC-08.2
        let catFood = PLACategory(name: "Makan & Minum", scope: .expense, sortOrder: 1)
        let catTrans = PLACategory(name: "Transportasi", scope: .expense, sortOrder: 2)
        let acc = UUID()
        let d = LocalDate(year: 2026, month: 11, day: 10)!

        let history = [
            PLATransaction(type: .expense, amount: 25_000, accountId: acc, categoryId: catFood.id, dateLocal: d, note: "Kopi kenangan"),
            PLATransaction(type: .expense, amount: 30_000, accountId: acc, categoryId: catFood.id, dateLocal: d, note: "Kopi pagi"),
            PLATransaction(type: .expense, amount: 15_000, accountId: acc, categoryId: catTrans.id, dateLocal: d, note: "Gojek kantor")
        ]

        let suggested = CategorySuggester.suggestCategories(
            forNote: "Kopi susu gula aren",
            scope: .expense,
            transactions: history,
            categories: [catFood, catTrans]
        )
        XCTAssertEqual(suggested.first?.id, catFood.id)

        // Single match (< 2) falls back to frequency order
        let fallback = CategorySuggester.suggestCategories(
            forNote: "Gojek pulang",
            scope: .expense,
            transactions: history,
            categories: [catFood, catTrans]
        )
        XCTAssertEqual(fallback.first?.id, catFood.id) // Food used twice vs Trans once
    }

    func testSHA256MatchesNISTTestVectors() {
        XCTAssertEqual(
            SHA256.hexDigest(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    func testBackupCodecRoundTripIdenticalDataAndWealth() throws {
        // SC-14 & AC-13.1/13.3
        let ts = Date(timeIntervalSince1970: 1_795_620_000)
        let acc = Account(name: "BCA", type: .bank, initialBalance: 2_000_000, isDefault: true, createdAt: ts)
        let cat = PLACategory(name: "Makan & Minum", scope: .expense, isSystem: true)
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, anchorDayOfMonth: 15)
        let task = PLATask(title: "Bayar pajak", dueDateLocal: LocalDate(year: 2026, month: 12, day: 1)!, priority: .high, createdAt: ts, updatedAt: ts)
        let bill = Bill(name: "Internet", amount: 350_000, nextDueDateLocal: LocalDate(year: 2026, month: 12, day: 15)!, recurrenceRuleId: rule.id, defaultAccountId: acc.id, categoryId: cat.id, createdAt: ts, updatedAt: ts)
        let tx = PLATransaction(type: .expense, amount: 150_000, accountId: acc.id, categoryId: cat.id, dateLocal: LocalDate(year: 2026, month: 11, day: 25)!, note: "Makan siang", createdAt: ts, updatedAt: ts)
        let budget = Budget(categoryId: nil, amount: 3_000_000, effectiveFromMonth: "2026-11", createdAt: ts, updatedAt: ts)
        let reminder = Reminder(ownerType: .task, ownerId: task.id, fireDateLocal: LocalDateTime(date: LocalDate(year: 2026, month: 12, day: 1)!, hour: 8, minute: 0))
        let insight = InsightRecord(ruleCode: "R-FIN-05c", periodKey: "2026-11", severity: .info, feedback: 1, generatedAt: ts)

        let payload = BackupPayload(
            tasks: [task],
            reminders: [reminder],
            recurrenceRules: [rule],
            accounts: [acc],
            categories: [cat],
            transactions: [tx],
            budgets: [budget],
            bills: [bill],
            insights: [insight],
            settings: UserSettings(budgetCycleStartDay: 25, hasCompletedOnboarding: true)
        )

        let data = try BackupCodec.encode(payload: payload, exportedAt: ts)
        let decoded = BackupCodec.decodeAndValidate(data: data)

        switch decoded {
        case .success(let preview):
            XCTAssertEqual(preview.exportSchemaVersion, BackupCodec.currentSchemaVersion)
            XCTAssertEqual(preview.taskCount, 1)
            XCTAssertEqual(preview.transactionCount, 1)
            XCTAssertEqual(preview.billCount, 1)
            XCTAssertEqual(preview.accountCount, 1)
            XCTAssertEqual(preview.budgetCount, 1)
            XCTAssertEqual(preview.totalLiquidWealth, 1_850_000)
            XCTAssertEqual(preview.payload, payload)
        case .failure(let error):
            XCTFail("Expected valid backup decode, got \(error)")
        }
    }

    func testBackupCodecRejectsTamperedChecksumAndFutureVersionAndCorruptJSON() throws {
        // AC-13.4
        let payload = BackupPayload(accounts: [Account(name: "Tunai", type: .cash, initialBalance: 100_000)])
        let validData = try BackupCodec.encode(payload: payload, exportedAt: Date(timeIntervalSince1970: 1_795_620_000))

        // Corrupt JSON
        XCTAssertEqual(BackupCodec.decodeAndValidate(data: Data("{not json".utf8)), .failure(.invalidJSON))

        // Tampered payload -> checksum mismatch
        var jsonText = String(data: validData, encoding: .utf8)!
        jsonText = jsonText.replacingOccurrences(of: "100000", with: "999999")
        XCTAssertEqual(BackupCodec.decodeAndValidate(data: Data(jsonText.utf8)), .failure(.checksumMismatch))

        // Future schema version
        var futureText = String(data: validData, encoding: .utf8)!
        futureText = futureText.replacingOccurrences(of: "\"exportSchemaVersion\" : 2", with: "\"exportSchemaVersion\" : 99")
        XCTAssertEqual(
            BackupCodec.decodeAndValidate(data: Data(futureText.utf8)),
            .failure(.unsupportedFutureVersion(found: 99, maxSupported: BackupCodec.currentSchemaVersion))
        )
    }

    func testBackupSuggestedFilenameFormat() {
        let dt = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 26)!, hour: 8, minute: 5)
        XCTAssertEqual(BackupCodec.suggestedFilename(at: dt), "pla-backup-20261126-0805.json")
    }

    func testCSVExporterUTF8BOMAndEscapingAndDateRange() {
        // AC-13.2
        let acc1 = Account(name: "BCA", type: .bank)
        let acc2 = Account(name: "GoPay", type: .ewallet)
        let cat = PLACategory(name: "Makan & Minum", scope: .expense)
        let billId = UUID()

        let tx1 = PLATransaction(
            type: .expense,
            amount: 75_000,
            accountId: acc1.id,
            categoryId: cat.id,
            billId: billId,
            dateLocal: LocalDate(year: 2026, month: 11, day: 10)!,
            note: "Warung \"Bu Sari\", nasi & es"
        )
        let tx2 = PLATransaction(
            type: .transfer,
            amount: 500_000,
            accountId: acc1.id,
            destinationAccountId: acc2.id,
            dateLocal: LocalDate(year: 2026, month: 11, day: 20)!,
            note: "Topup"
        )
        let txOutOfRange = PLATransaction(
            type: .income,
            amount: 5_000_000,
            accountId: acc1.id,
            categoryId: cat.id,
            dateLocal: LocalDate(year: 2026, month: 10, day: 1)!
        )

        let data = CSVExporter.exportTransactions(
            transactions: [tx1, tx2, txOutOfRange],
            accounts: [acc1, acc2],
            categories: [cat],
            from: LocalDate(year: 2026, month: 11, day: 1)!,
            to: LocalDate(year: 2026, month: 11, day: 30)!
        )

        // Check UTF-8 BOM bytes EF BB BF
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])

        let text = String(data: data.dropFirst(3), encoding: .utf8)!
        let lines = text.split(separator: "\r\n")
        XCTAssertEqual(lines.count, 3) // header + 2 rows (Oct excluded)
        XCTAssertEqual(String(lines[0]), CSVExporter.headerRow)
        XCTAssertTrue(lines[1].contains("2026-11-20,Transfer,500000,,BCA,GoPay,Topup,"))
        XCTAssertTrue(lines[2].contains("\"Warung \"\"Bu Sari\"\", nasi & es\",Tagihan Lunas"))
    }
}
