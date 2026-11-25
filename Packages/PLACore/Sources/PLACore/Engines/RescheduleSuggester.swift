import Foundation

public struct RescheduleSuggestion: Equatable, Sendable {
    public let date: LocalDate
    public let existingTaskCount: Int

    public init(date: LocalDate, existingTaskCount: Int) {
        self.date = date
        self.existingTaskCount = existingTaskCount
    }
}

/// Suggests the lightest day in the upcoming 7 days for rescheduling an overdue task (PRD F-06 / AC-06.2).
public enum RescheduleSuggester {
    public static func bestDayInNext7Days(
        from today: LocalDate,
        activeTasks: [PLATask],
        excludingTaskId: UUID? = nil
    ) -> RescheduleSuggestion {
        let filtered = activeTasks.filter { $0.status == .active && $0.id != excludingTaskId }
        var countsByDate: [LocalDate: Int] = [:]
        for task in filtered {
            if let due = task.dueDateLocal {
                countsByDate[due, default: 0] += 1
            }
        }

        var bestDate = today.addingDays(1)
        var bestCount = Int.max

        for offset in 1...7 {
            let candidate = today.addingDays(offset)
            let count = countsByDate[candidate] ?? 0
            if count < bestCount {
                bestCount = count
                bestDate = candidate
            }
        }

        return RescheduleSuggestion(date: bestDate, existingTaskCount: bestCount)
    }

    /// Computes upcoming Saturday (or Sunday if today is Saturday) for "Akhir pekan" quick chip.
    public static func nextWeekendDate(from today: LocalDate) -> LocalDate {
        // weekdayISO: 1 = Mon ... 6 = Sat, 7 = Sun
        let wd = today.weekdayISO
        if wd < 6 {
            return today.addingDays(6 - wd)
        } else if wd == 6 {
            return today.addingDays(1) // Sunday
        } else {
            return today.addingDays(6) // Next Saturday
        }
    }
}
