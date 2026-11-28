import XCTest
@testable import PLACore

final class ScheduleConflictEngineTests: XCTestCase {
    func testDetectsExactAndOverlappingMeetingConflictAndSuggestsFreeSlots() {
        // Sunday 2026-11-29 has "Rapat Tim" at 15.00 (15.00 - 16.00)
        let sunday = LocalDate(year: 2026, month: 11, day: 29)!
        let meeting = PLATask(
            title: "Rapat Tim",
            dueDateLocal: sunday,
            dueTimeMinutes: 15 * 60,
            priority: .high
        )
        let completedOld = PLATask(
            title: "Tugas Sudah Selesai",
            dueDateLocal: sunday,
            dueTimeMinutes: 15 * 60,
            status: .completed
        )

        // User tries to schedule "Main sama teman" on Sunday at 15.00
        let report = ScheduleConflictEngine.evaluate(
            date: sunday,
            startMinutes: 15 * 60,
            tasks: [meeting, completedOld]
        )

        XCTAssertTrue(report.hasConflict)
        XCTAssertEqual(report.conflictingSlots.count, 1)
        XCTAssertEqual(report.conflictingSlots.first?.title, "Rapat Tim")

        // Free windows should be 07.00-15.00 and 16.00-22.00
        XCTAssertEqual(report.freeWindows.count, 2)
        XCTAssertEqual(report.freeWindows[0], FreeTimeWindow(startMinutes: 7 * 60, endMinutes: 15 * 60))
        XCTAssertEqual(report.freeWindows[1], FreeTimeWindow(startMinutes: 16 * 60, endMinutes: 22 * 60))

        // Suggestions should include 14.00 and 16.00 (right around 15.00) and never 15.00
        XCTAssertFalse(report.suggestedStartMinutes.contains(15 * 60))
        XCTAssertTrue(report.suggestedStartMinutes.contains(16 * 60))
        XCTAssertTrue(report.suggestedStartMinutes.contains(14 * 60))
        XCTAssertLessThanOrEqual(report.suggestedStartMinutes.count, 4)

        // Partial overlap (15.30) must also be detected
        let partialOverlap = ScheduleConflictEngine.evaluate(
            date: sunday,
            startMinutes: 15 * 60 + 30,
            tasks: [meeting]
        )
        XCTAssertTrue(partialOverlap.hasConflict)

        // Adjacent slot right after (16.00) has no conflict
        let rightAfter = ScheduleConflictEngine.evaluate(
            date: sunday,
            startMinutes: 16 * 60,
            tasks: [meeting]
        )
        XCTAssertFalse(rightAfter.hasConflict)
    }

    func testExcludesSelfWhenEditingExistingTaskAndIncludesAppleCalendarSlots() {
        let sunday = LocalDate(year: 2026, month: 11, day: 29)!
        let myTask = PLATask(title: "Main Futsal", dueDateLocal: sunday, dueTimeMinutes: 10 * 60)
        let calEvent = BusyTimeSlot(
            id: "ek-1",
            title: "Rapat Klien",
            startMinutes: 14 * 60,
            endMinutes: 15 * 60 + 30,
            isCalendarEvent: true
        )

        // Editing self at 10.00 should NOT conflict with itself
        let editSelf = ScheduleConflictEngine.evaluate(
            date: sunday,
            startMinutes: 10 * 60,
            tasks: [myTask],
            excludingTaskId: myTask.id,
            calendarBusySlots: [calEvent]
        )
        XCTAssertFalse(editSelf.hasConflict)

        // Moving to 14.30 MUST detect the Apple Calendar meeting
        let hitsCal = ScheduleConflictEngine.evaluate(
            date: sunday,
            startMinutes: 14 * 60 + 30,
            tasks: [myTask],
            excludingTaskId: myTask.id,
            calendarBusySlots: [calEvent]
        )
        XCTAssertTrue(hitsCal.hasConflict)
        XCTAssertEqual(hitsCal.conflictingSlots.first?.title, "Rapat Klien")
        XCTAssertEqual(hitsCal.conflictingSlots.first?.isCalendarEvent, true)
        XCTAssertTrue(hitsCal.suggestedStartMinutes.contains(15 * 60 + 30))
    }

    func testAvoidsPastSuggestionsWhenSchedulingForToday() {
        let today = LocalDate(year: 2026, month: 11, day: 28)!
        let now = LocalDateTime(date: today, hour: 13, minute: 10)
        let meeting = PLATask(title: "Rapat Siang", dueDateLocal: today, dueTimeMinutes: 14 * 60)

        let report = ScheduleConflictEngine.evaluate(
            date: today,
            startMinutes: 14 * 60,
            tasks: [meeting],
            now: now
        )
        XCTAssertTrue(report.hasConflict)
        // All suggested slots must be strictly after 13:10 (>= 13:30) and never overlapping 14:00-15:00
        for slot in report.suggestedStartMinutes {
            XCTAssertGreaterThanOrEqual(slot, 13 * 60 + 30)
            XCTAssertFalse(slot >= 14 * 60 && slot < 15 * 60)
        }
    }
}
