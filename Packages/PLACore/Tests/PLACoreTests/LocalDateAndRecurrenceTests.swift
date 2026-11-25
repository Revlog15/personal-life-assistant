import XCTest
@testable import PLACore

final class LocalDateAndRecurrenceTests: XCTestCase {
    func testLocalDateValidationAndLeapYears() {
        XCTAssertTrue(LocalDate.isLeapYear(2024))
        XCTAssertTrue(LocalDate.isLeapYear(2028))
        XCTAssertTrue(LocalDate.isLeapYear(2000))
        XCTAssertFalse(LocalDate.isLeapYear(2026))
        XCTAssertFalse(LocalDate.isLeapYear(1900))

        XCTAssertNotNil(LocalDate(year: 2024, month: 2, day: 29))
        XCTAssertNil(LocalDate(year: 2026, month: 2, day: 29))
        XCTAssertNil(LocalDate(year: 2026, month: 4, day: 31))
        XCTAssertNil(LocalDate(year: 2026, month: 13, day: 1))
    }

    func testLocalDateISOParsingAndFormatting() {
        let d = LocalDate(isoString: "2026-11-26")
        XCTAssertEqual(d, LocalDate(year: 2026, month: 11, day: 26))
        XCTAssertEqual(d?.isoString, "2026-11-26")
        XCTAssertEqual(d?.yearMonthString, "2026-11")
        XCTAssertNil(LocalDate(isoString: "2026-1-5"))
        XCTAssertNil(LocalDate(isoString: "invalid"))
    }

    func testWeekdayISOStartsMonday() {
        // 2026-11-26 is Thursday (Kamis = 4)
        let thu = LocalDate(year: 2026, month: 11, day: 26)!
        XCTAssertEqual(thu.weekdayISO, 4)
        XCTAssertEqual(thu.addingDays(-3).weekdayISO, 1) // Monday 2026-11-23
        XCTAssertEqual(thu.addingDays(3).weekdayISO, 7)  // Sunday 2026-11-29
    }

    func testAddingDaysAndDistanceRoundtrip() {
        let start = LocalDate(year: 2026, month: 12, day: 30)!
        let next = start.addingDays(5)
        XCTAssertEqual(next, LocalDate(year: 2027, month: 1, day: 4))
        XCTAssertEqual(start.days(until: next), 5)
        XCTAssertEqual(next.days(until: start), -5)
        XCTAssertEqual(next.addingDays(-5), start)
    }

    func testLocalDateTimeCarryAcrossMidnightAndTimezoneFloating() {
        let base = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 26)!, hour: 23, minute: 30)
        XCTAssertEqual(base.addingMinutes(45), LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 27)!, hour: 0, minute: 15))
        XCTAssertEqual(base.addingMinutes(-1500), LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 25)!, hour: 22, minute: 30))

        // Floating local time stays 09:00 in both WIB (+7) and WITA (+8)
        let wib = TimeZone(secondsFromGMT: 7 * 3600)!
        let wita = TimeZone(secondsFromGMT: 8 * 3600)!
        let nineAM = LocalDateTime(isoString: "2026-12-01T09:00")!
        let dateWIB = nineAM.toDate(timeZone: wib)
        let dateWITA = nineAM.toDate(timeZone: wita)
        XCTAssertEqual(LocalDateTime.from(date: dateWIB, timeZone: wib), nineAM)
        XCTAssertEqual(LocalDateTime.from(date: dateWITA, timeZone: wita), nineAM)
        // WITA 09:00 happens 1 hour earlier in UTC than WIB 09:00
        XCTAssertEqual(dateWIB.timeIntervalSince(dateWITA), 3600, accuracy: 1.0)
    }

    func testMonthlyRecurrenceAnchorDay31NonLeapYear() {
        // PRD §12: 31 Jan -> 28 Feb -> 31 Mar -> 30 Apr -> 31 Mei
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, anchorDayOfMonth: 31)
        let jan31 = LocalDate(year: 2026, month: 1, day: 31)!
        let feb = RecurrenceEngine.nextOccurrence(after: jan31, rule: rule)!
        XCTAssertEqual(feb, LocalDate(year: 2026, month: 2, day: 28))
        let mar = RecurrenceEngine.nextOccurrence(after: feb, rule: rule)!
        XCTAssertEqual(mar, LocalDate(year: 2026, month: 3, day: 31))
        let apr = RecurrenceEngine.nextOccurrence(after: mar, rule: rule)!
        XCTAssertEqual(apr, LocalDate(year: 2026, month: 4, day: 30))
        let may = RecurrenceEngine.nextOccurrence(after: apr, rule: rule)!
        XCTAssertEqual(may, LocalDate(year: 2026, month: 5, day: 31))
    }

    func testMonthlyRecurrenceAnchorDay31LeapYear() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, anchorDayOfMonth: 31)
        let jan31 = LocalDate(year: 2028, month: 1, day: 31)!
        let feb = RecurrenceEngine.nextOccurrence(after: jan31, rule: rule)!
        XCTAssertEqual(feb, LocalDate(year: 2028, month: 2, day: 29))
        let mar = RecurrenceEngine.nextOccurrence(after: feb, rule: rule)!
        XCTAssertEqual(mar, LocalDate(year: 2028, month: 3, day: 31))
    }

    func testMonthlyRecurrenceLastDayOfMonthAnchor() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, anchorDayOfMonth: -1)
        let feb = LocalDate(year: 2026, month: 2, day: 28)!
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: feb, rule: rule), LocalDate(year: 2026, month: 3, day: 31))
        let mar = LocalDate(year: 2026, month: 3, day: 31)!
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: mar, rule: rule), LocalDate(year: 2026, month: 4, day: 30))
    }

    func testYearlyRecurrenceFeb29LeapRestoration() {
        // PRD §12: 29 Feb 2024 -> 28 Feb 2025 -> 28 Feb 2026 -> 28 Feb 2027 -> 29 Feb 2028
        let rule = RecurrenceRule(frequency: .yearly, interval: 1, anchorDayOfMonth: 29, anchorMonth: 2)
        var d = LocalDate(year: 2024, month: 2, day: 29)!
        d = RecurrenceEngine.nextOccurrence(after: d, rule: rule)!
        XCTAssertEqual(d, LocalDate(year: 2025, month: 2, day: 28))
        d = RecurrenceEngine.nextOccurrence(after: d, rule: rule)!
        XCTAssertEqual(d, LocalDate(year: 2026, month: 2, day: 28))
        d = RecurrenceEngine.nextOccurrence(after: d, rule: rule)!
        XCTAssertEqual(d, LocalDate(year: 2027, month: 2, day: 28))
        d = RecurrenceEngine.nextOccurrence(after: d, rule: rule)!
        XCTAssertEqual(d, LocalDate(year: 2028, month: 2, day: 29))
    }

    func testWeeklyRecurrenceWithWeekdaysMask() {
        // Mon (bit 0) + Wed (bit 2) + Fri (bit 4), interval = 2 weeks
        let mask = (1 << 0) | (1 << 2) | (1 << 4)
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdaysMask: mask)
        let mon = LocalDate(year: 2026, month: 11, day: 23)! // Monday
        let wed = RecurrenceEngine.nextOccurrence(after: mon, rule: rule)!
        XCTAssertEqual(wed, LocalDate(year: 2026, month: 11, day: 25))
        let fri = RecurrenceEngine.nextOccurrence(after: wed, rule: rule)!
        XCTAssertEqual(fri, LocalDate(year: 2026, month: 11, day: 27))
        // Next after Fri jumps 2 weeks to Monday Dec 7
        let nextMon = RecurrenceEngine.nextOccurrence(after: fri, rule: rule)!
        XCTAssertEqual(nextMon, LocalDate(year: 2026, month: 12, day: 7))
    }

    func testRecurrenceEndDateAndMaxOccurrences() {
        let end = LocalDate(year: 2026, month: 11, day: 28)!
        let ruleEnd = RecurrenceRule(frequency: .daily, interval: 2, endDateLocal: end)
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: LocalDate(year: 2026, month: 11, day: 26)!, rule: ruleEnd), end)
        XCTAssertNil(RecurrenceEngine.nextOccurrence(after: end, rule: ruleEnd))

        let ruleMax = RecurrenceRule(frequency: .daily, interval: 1, maxOccurrences: 3)
        XCTAssertNotNil(RecurrenceEngine.nextOccurrence(after: LocalDate(year: 2026, month: 11, day: 26)!, rule: ruleMax, completedOccurrences: 2))
        XCTAssertNil(RecurrenceEngine.nextOccurrence(after: LocalDate(year: 2026, month: 11, day: 26)!, rule: ruleMax, completedOccurrences: 3))
    }

    func testOverdueRecurringMissedCyclesAndCatchUp() {
        let rule = RecurrenceRule(frequency: .daily, interval: 1)
        let due = LocalDate(year: 2026, month: 11, day: 20)!
        let today = LocalDate(year: 2026, month: 11, day: 26)!
        XCTAssertEqual(RecurrenceEngine.missedCycleCount(from: due, upTo: today, rule: rule), 6)
        XCTAssertEqual(RecurrenceEngine.nextOccurrenceFromToday(overdueDate: due, today: today, rule: rule), LocalDate(year: 2026, month: 11, day: 27))
    }
}
