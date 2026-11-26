import Foundation

/// Deterministic recurrence calculation handling day 29-31 clamping, end-of-month, and leap years (PRD §12).
public enum RecurrenceEngine {
    /// Computes the next occurrence strictly after `currentDate` (or relative to `completedOn` for P-10 `.fromCompletionDate` rules).
    /// - Parameters:
    ///   - currentDate: The date of the cycle being completed or skipped.
    ///   - completedOn: Optional actual completion date used when `rule.anchorMode == .fromCompletionDate`.
    ///   - rule: The recurrence rule.
    ///   - completedOccurrences: Count of occurrences already completed INCLUDING `currentDate`.
    public static func nextOccurrence(
        after currentDate: LocalDate,
        completedOn: LocalDate? = nil,
        rule: RecurrenceRule,
        completedOccurrences: Int = 1
    ) -> LocalDate? {
        if let maxOccurrences = rule.maxOccurrences, completedOccurrences >= maxOccurrences {
            return nil
        }

        let baseDate: LocalDate
        if rule.anchorMode == .fromCompletionDate, let completion = completedOn {
            baseDate = completion
        } else {
            baseDate = currentDate
        }

        let step = max(1, rule.interval)
        let candidate: LocalDate

        switch rule.frequency {
        case .daily:
            candidate = baseDate.addingDays(step)

        case .weekly:
            candidate = nextWeeklyOccurrence(after: baseDate, interval: step, weekdaysMask: rule.weekdaysMask)

        case .monthly:
            let anchor = rule.anchorMode == .fromCompletionDate ? baseDate.day : (rule.anchorDayOfMonth ?? baseDate.day)
            candidate = baseDate.addingMonths(step, anchorDay: anchor)

        case .yearly:
            let anchorMonth = rule.anchorMode == .fromCompletionDate ? baseDate.month : (rule.anchorMonth ?? baseDate.month)
            let anchorDay = rule.anchorMode == .fromCompletionDate ? baseDate.day : (rule.anchorDayOfMonth ?? baseDate.day)
            candidate = baseDate.addingYears(step, anchorMonth: anchorMonth, anchorDay: anchorDay)
        }

        if let end = rule.endDateLocal, candidate > end {
            return nil
        }
        return candidate
    }

    /// Counts how many scheduled cycles were missed strictly before `today` (PRD §12 overdue recurring).
    public static func missedCycleCount(
        from dueDate: LocalDate,
        upTo today: LocalDate,
        rule: RecurrenceRule,
        maxScan: Int = 500
    ) -> Int {
        guard dueDate < today else { return 0 }
        var count = 0
        var cursor = dueDate
        while count < maxScan {
            guard let next = nextOccurrence(after: cursor, rule: rule, completedOccurrences: count + 1) else {
                break
            }
            if next <= today {
                count += 1
                cursor = next
            } else {
                break
            }
        }
        return count
    }

    /// Computes the next future occurrence strictly after `today` when catching up an overdue recurring task.
    public static func nextOccurrenceFromToday(
        overdueDate: LocalDate,
        today: LocalDate,
        rule: RecurrenceRule
    ) -> LocalDate? {
        if overdueDate >= today {
            return nextOccurrence(after: overdueDate, rule: rule)
        }
        var cursor = overdueDate
        var safety = 0
        while cursor <= today && safety < 2000 {
            guard let next = nextOccurrence(after: cursor, rule: rule) else { return nil }
            cursor = next
            safety += 1
        }
        if cursor <= today {
            return nextOccurrence(after: today, rule: rule)
        }
        return cursor
    }

    private static func nextWeeklyOccurrence(
        after currentDate: LocalDate,
        interval: Int,
        weekdaysMask: Int?
    ) -> LocalDate {
        let validMask = (weekdaysMask ?? 0) & 0b1111111
        guard validMask != 0 else {
            return currentDate.addingDays(7 * interval)
        }

        let currentWeekday = currentDate.weekdayISO // 1 = Mon .. 7 = Sun
        // Check if there is another selected weekday later in the same ISO week
        if currentWeekday < 7 {
            for wd in (currentWeekday + 1)...7 {
                if (validMask & (1 << (wd - 1))) != 0 {
                    return currentDate.addingDays(wd - currentWeekday)
                }
            }
        }

        // Otherwise advance `interval` weeks to Monday of target week, then pick the first selected weekday
        let mondayOfCurrentWeek = currentDate.addingDays(-(currentWeekday - 1))
        let mondayOfTargetWeek = mondayOfCurrentWeek.addingDays(7 * interval)
        for wd in 1...7 {
            if (validMask & (1 << (wd - 1))) != 0 {
                return mondayOfTargetWeek.addingDays(wd - 1)
            }
        }
        return currentDate.addingDays(7 * interval)
    }
}
