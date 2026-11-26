import Foundation

public struct RescheduleSuggestion: Equatable, Sendable {
    public let date: LocalDate
    public let existingTaskCount: Int

    public init(date: LocalDate, existingTaskCount: Int) {
        self.date = date
        self.existingTaskCount = existingTaskCount
    }
}

/// P-08 (R-PER-03): Weighted daily workload score = (High*3) + (Medium*2) + (Low*1) + calendarEvents.
public struct SmartRescheduleOption: Identifiable, Equatable, Sendable {
    public var id: String { date.isoString }
    public let date: LocalDate
    public let workloadScore: Int
    public let highCount: Int
    public let mediumCount: Int
    public let lowCount: Int
    public let calendarEventCount: Int

    public var totalTaskCount: Int { highCount + mediumCount + lowCount }

    public init(
        date: LocalDate,
        workloadScore: Int,
        highCount: Int,
        mediumCount: Int,
        lowCount: Int,
        calendarEventCount: Int
    ) {
        self.date = date
        self.workloadScore = workloadScore
        self.highCount = highCount
        self.mediumCount = mediumCount
        self.lowCount = lowCount
        self.calendarEventCount = calendarEventCount
    }
}

/// Suggests the lightest day in the upcoming 7 days (MVP F-06 + Pasca-MVP P-08 R-PER-03 weighted score & EventKit).
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

    /// P-08 R-PER-03: Computes weighted daily workload scores across the next 7 days (including optional EventKit event counts).
    public static func smartOptionsInNext7Days(
        from today: LocalDate,
        activeTasks: [PLATask],
        calendarEventCounts: [LocalDate: Int] = [:],
        excludingTaskId: UUID? = nil
    ) -> [SmartRescheduleOption] {
        let filtered = activeTasks.filter { $0.status == .active && $0.id != excludingTaskId }
        var highByDate: [LocalDate: Int] = [:]
        var medByDate: [LocalDate: Int] = [:]
        var lowByDate: [LocalDate: Int] = [:]

        for task in filtered {
            guard let due = task.dueDateLocal else { continue }
            switch task.priority {
            case .high: highByDate[due, default: 0] += 1
            case .medium: medByDate[due, default: 0] += 1
            case .low: lowByDate[due, default: 0] += 1
            }
        }

        var options: [SmartRescheduleOption] = []
        for offset in 1...7 {
            let candidate = today.addingDays(offset)
            let h = highByDate[candidate] ?? 0
            let m = medByDate[candidate] ?? 0
            let l = lowByDate[candidate] ?? 0
            let cal = max(0, calendarEventCounts[candidate] ?? 0)
            let score = (h * 3) + (m * 2) + (l * 1) + cal
            options.append(SmartRescheduleOption(
                date: candidate,
                workloadScore: score,
                highCount: h,
                mediumCount: m,
                lowCount: l,
                calendarEventCount: cal
            ))
        }

        return options.sorted { lhs, rhs in
            if lhs.workloadScore != rhs.workloadScore {
                return lhs.workloadScore < rhs.workloadScore
            }
            return lhs.date < rhs.date
        }
    }

    public static func smartBestDayInNext7Days(
        from today: LocalDate,
        activeTasks: [PLATask],
        calendarEventCounts: [LocalDate: Int] = [:],
        excludingTaskId: UUID? = nil
    ) -> SmartRescheduleOption {
        smartOptionsInNext7Days(
            from: today,
            activeTasks: activeTasks,
            calendarEventCounts: calendarEventCounts,
            excludingTaskId: excludingTaskId
        ).first ?? SmartRescheduleOption(
            date: today.addingDays(1),
            workloadScore: 0,
            highCount: 0,
            mediumCount: 0,
            lowCount: 0,
            calendarEventCount: 0
        )
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
