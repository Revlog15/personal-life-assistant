import XCTest
@testable import PLACore

final class ReminderAndQueuePlannerTests: XCTestCase {
    private let baseNow = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 1)!, hour: 8, minute: 0)

    func testHighPriorityTaskGeneratesAllFiveOffsets() {
        // AC-03.1: Deadline 10 days away at 14:00 -> H-7 (09:00), H-3 (09:00), H-1 (09:00), Hari H (08:00), 2h before (12:00)
        let task = PLATask(
            title: "Presentasi Proyek",
            dueDateLocal: LocalDate(year: 2026, month: 11, day: 11)!,
            dueTimeMinutes: 14 * 60,
            priority: .high
        )
        let reminders = ReminderPlanner.planTaskReminders(for: task, now: baseNow, settings: .default)
        XCTAssertEqual(reminders.count, 5)
        XCTAssertEqual(reminders.map(\.fireDateLocal.isoString), [
            "2026-11-04T09:00",
            "2026-11-08T09:00",
            "2026-11-10T09:00",
            "2026-11-11T08:00",
            "2026-11-11T12:00"
        ])
        XCTAssertTrue(reminders.allSatisfy { $0.soundName == ReminderSound.plaUrgent.rawValue })
    }

    func testPastOffsetsAreDropped() {
        // AC-03.2: Deadline 2 days away -> H-7 and H-3 are in the past and must NOT be created
        let task = PLATask(
            title: "Kumpul Laporan",
            dueDateLocal: LocalDate(year: 2026, month: 11, day: 3)!,
            dueTimeMinutes: 17 * 60,
            priority: .high
        )
        let reminders = ReminderPlanner.planTaskReminders(for: task, now: baseNow, settings: .default)
        XCTAssertEqual(reminders.map(\.fireDateLocal.isoString), [
            "2026-11-02T09:00",
            "2026-11-03T08:00",
            "2026-11-03T15:00"
        ])
    }

    func testDuplicateTimestampOnDayHMergedToOne() {
        // AC-03.3: High priority due at 10:00 -> Hari H (08:00) and 2h before (08:00) collide -> merged to 1!
        let task = PLATask(
            title: "Meeting Pagi",
            dueDateLocal: LocalDate(year: 2026, month: 11, day: 11)!,
            dueTimeMinutes: 10 * 60,
            priority: .high
        )
        let reminders = ReminderPlanner.planTaskReminders(for: task, now: baseNow, settings: .default)
        let dayH = reminders.filter { $0.fireDateLocal.date == LocalDate(year: 2026, month: 11, day: 11)! }
        XCTAssertEqual(dayH.count, 1)
        XCTAssertEqual(dayH.first?.fireDateLocal.isoString, "2026-11-11T08:00")
    }

    func testCustomPreferencesDisableH7() {
        // AC-03.4
        var settings = UserSettings.default
        settings.reminderPreferences.highEnableH7 = false
        let task = PLATask(
            title: "Ujian",
            dueDateLocal: LocalDate(year: 2026, month: 11, day: 11)!,
            priority: .high
        )
        let reminders = ReminderPlanner.planTaskReminders(for: task, now: baseNow, settings: settings)
        XCTAssertEqual(reminders.map(\.fireDateLocal.isoString), [
            "2026-11-08T09:00",
            "2026-11-10T09:00",
            "2026-11-11T08:00"
        ])
    }

    func testMediumAndLowPriorityDefaultPatterns() {
        let due = LocalDate(year: 2026, month: 11, day: 11)!
        let med = PLATask(title: "Beli Galon", dueDateLocal: due, priority: .medium)
        let low = PLATask(title: "Rapikan Meja", dueDateLocal: due, priority: .low)

        let medRem = ReminderPlanner.planTaskReminders(for: med, now: baseNow, settings: .default)
        XCTAssertEqual(medRem.map(\.fireDateLocal.isoString), [
            "2026-11-08T09:00",
            "2026-11-10T09:00",
            "2026-11-11T08:00"
        ])

        let lowRem = ReminderPlanner.planTaskReminders(for: low, now: baseNow, settings: .default)
        XCTAssertEqual(lowRem.map(\.fireDateLocal.isoString), ["2026-11-11T09:00"])
    }

    func testQuietHoursShiftToMorningOrBeforeQuietWhenDeadlineEarly() {
        // 23:00 with deadline next day 15:00 -> shifts to 07:00 next morning
        let lateFire = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 5)!, hour: 23, minute: 0)
        let afternoonDeadline = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 6)!, hour: 15, minute: 0)
        let shiftedMorning = ReminderPlanner.adjustForQuietHours(lateFire, deadline: afternoonDeadline, settings: .default)
        XCTAssertEqual(shiftedMorning.isoString, "2026-11-06T07:00")

        // 04:00 with deadline 06:00 (before 07:00 wake) -> shifts to 21:55 previous evening!
        let earlyFire = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 6)!, hour: 4, minute: 0)
        let earlyDeadline = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 6)!, hour: 6, minute: 0)
        let shiftedBeforeQuiet = ReminderPlanner.adjustForQuietHours(earlyFire, deadline: earlyDeadline, settings: .default)
        XCTAssertEqual(shiftedBeforeQuiet.isoString, "2026-11-05T21:55")
    }

    func testManualReminderIsNotShiftedByQuietHours() {
        let task = PLATask(title: "Minum Obat Malam", dueDateLocal: LocalDate(year: 2026, month: 11, day: 2)!, priority: .medium)
        let manual = Reminder(
            ownerType: .task,
            ownerId: task.id,
            triggerType: .manual,
            fireDateLocal: LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 1)!, hour: 23, minute: 15)
        )
        let plan = NotificationQueuePlanner.buildQueue(
            now: baseNow,
            tasks: [task],
            bills: [],
            reminders: [manual],
            settings: .default
        )
        let scheduled = plan.items.first { $0.kind == .taskReminder }
        XCTAssertEqual(scheduled?.fireDateLocal.isoString, "2026-11-01T23:15")
    }

    func testBillRemindersUseBillSound() {
        let bill = Bill(
            name: "Internet",
            amount: 350_000,
            nextDueDateLocal: LocalDate(year: 2026, month: 11, day: 15)!,
            recurrenceRuleId: UUID(),
            defaultAccountId: UUID(),
            categoryId: UUID()
        )
        let rems = ReminderPlanner.planBillReminders(for: bill, now: baseNow, settings: .default)
        XCTAssertEqual(rems.map(\.fireDateLocal.isoString), [
            "2026-11-12T09:00",
            "2026-11-14T09:00",
            "2026-11-15T08:00"
        ])
        XCTAssertTrue(rems.allSatisfy { $0.soundName == ReminderSound.plaBill.rawValue })
    }

    func testQueueHardLimit64With200CandidatesAndOverflowGuard() {
        // SC-06 & PRD §9.2: 200 reminders in next 5 days + 7 digests + 2 sideload slots -> strictly <= 64 and overflow guard inserted!
        var tasks: [PLATask] = []
        var reminders: [Reminder] = []

        for i in 0..<200 {
            let dayOffset = (i / 40) + 1 // days 1..5 (all < 7 days)
            let dueDate = baseNow.date.addingDays(dayOffset)
            let task = PLATask(title: "Task #\(i)", dueDateLocal: dueDate, priority: .medium)
            tasks.append(task)
            let fire = LocalDateTime(date: dueDate, hour: 9 + (i % 10), minute: (i % 40))
            reminders.append(Reminder(ownerType: .task, ownerId: task.id, triggerType: .manual, fireDateLocal: fire))
        }

        // Also put a task on days 1..7 so morning digest wants all 7 slots
        for d in 6...7 {
            tasks.append(PLATask(title: "Digest day \(d)", dueDateLocal: baseNow.date.addingDays(d), priority: .low))
        }

        let expiry = baseNow.date.addingDays(5) // produces H-2 and H-1 (2 system slots)
        let plan = NotificationQueuePlanner.buildQueue(
            now: baseNow,
            tasks: tasks,
            bills: [],
            reminders: reminders,
            settings: .default,
            sideloadExpiryDate: expiry
        )

        XCTAssertLessThanOrEqual(plan.count, 64)
        XCTAssertEqual(plan.count, 64) // 2 system + 7 digest + 54 reminders + 1 refill nudge
        XCTAssertEqual(plan.items.filter { $0.kind == .sideloadExpiry }.count, 2)
        XCTAssertEqual(plan.items.filter { $0.kind == .morningDigest }.count, 7)
        XCTAssertEqual(plan.items.filter { $0.kind == .queueRefillNudge }.count, 1)
        XCTAssertTrue(plan.overflowGuardInserted)
    }

    func testQueuePriorityTieBreakerAtIdenticalFireTime() {
        let sameFire = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 3)!, hour: 9, minute: 0)
        let tLow = PLATask(title: "Low", dueDateLocal: sameFire.date, priority: .low)
        let tMed = PLATask(title: "Med", dueDateLocal: sameFire.date, priority: .medium)
        let tHigh = PLATask(title: "High", dueDateLocal: sameFire.date, priority: .high)
        let bill = Bill(name: "Listrik", amount: 200_000, nextDueDateLocal: sameFire.date, recurrenceRuleId: UUID(), defaultAccountId: UUID(), categoryId: UUID())

        let rems = [
            Reminder(ownerType: .task, ownerId: tLow.id, fireDateLocal: sameFire),
            Reminder(ownerType: .task, ownerId: tMed.id, fireDateLocal: sameFire),
            Reminder(ownerType: .bill, ownerId: bill.id, fireDateLocal: sameFire),
            Reminder(ownerType: .task, ownerId: tHigh.id, fireDateLocal: sameFire)
        ]

        var settings = UserSettings.default
        settings.morningDigestEnabled = false

        let plan = NotificationQueuePlanner.buildQueue(
            now: baseNow,
            tasks: [tLow, tMed, tHigh],
            bills: [bill],
            reminders: rems,
            settings: settings
        )

        let ownerIds = plan.items.compactMap(\.ownerId)
        XCTAssertEqual(ownerIds, [tHigh.id, bill.id, tMed.id, tLow.id])
    }

    func testMorningDigestSkippedOnEmptyDays() {
        // AC-05.5
        let taskDay3 = PLATask(title: "Hanya hari 3", dueDateLocal: LocalDate(year: 2026, month: 11, day: 4)!)
        let plan = NotificationQueuePlanner.buildQueue(
            now: baseNow,
            tasks: [taskDay3],
            bills: [],
            reminders: [],
            settings: .default
        )
        let digests = plan.items.filter { $0.kind == .morningDigest }
        XCTAssertEqual(digests.count, 1)
        XCTAssertEqual(digests.first?.fireDateLocal.isoString, "2026-11-04T07:30")
        XCTAssertTrue(digests.first?.body.contains("1 tugas, 0 tagihan") == true)
    }

    func testQueueIgnoresCompletedTasksAndInactiveBills() {
        let doneTask = PLATask(title: "Selesai", dueDateLocal: LocalDate(year: 2026, month: 11, day: 3)!, status: .completed)
        let inactiveBill = Bill(name: "Cancel", amount: 50_000, nextDueDateLocal: LocalDate(year: 2026, month: 11, day: 3)!, recurrenceRuleId: UUID(), defaultAccountId: UUID(), categoryId: UUID(), isActive: false)
        let rems = [
            Reminder(ownerType: .task, ownerId: doneTask.id, fireDateLocal: LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 3)!, hour: 9, minute: 0)),
            Reminder(ownerType: .bill, ownerId: inactiveBill.id, fireDateLocal: LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 3)!, hour: 9, minute: 0))
        ]
        let plan = NotificationQueuePlanner.buildQueue(now: baseNow, tasks: [doneTask], bills: [inactiveBill], reminders: rems, settings: .default)
        XCTAssertEqual(plan.count, 0)
    }
}
