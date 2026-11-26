import Foundation

/// P-09 (R-PER-01): 4 productive time blocks matching PRD §10.2.
public enum ProductiveTimeBlock: String, Codable, CaseIterable, Hashable, Sendable {
    case morning    // Pagi 06:00 - 10:59
    case midday     // Siang 11:00 - 14:59
    case afternoon  // Sore 15:00 - 18:59
    case evening    // Malam 19:00 - 22:59

    public var labelIndonesian: String {
        switch self {
        case .morning: return "Pagi (06.00–11.00)"
        case .midday: return "Siang (11.00–15.00)"
        case .afternoon: return "Sore (15.00–19.00)"
        case .evening: return "Malam (19.00–23.00)"
        }
    }

    public var suggestedReminderMinutes: Int {
        switch self {
        case .morning: return 8 * 60
        case .midday: return 12 * 60
        case .afternoon: return 16 * 60
        case .evening: return 19 * 60 + 30
        }
    }

    public static func block(forHour hour: Int) -> ProductiveTimeBlock? {
        switch hour {
        case 6..<11: return .morning
        case 11..<15: return .midday
        case 15..<19: return .afternoon
        case 19..<23: return .evening
        default: return nil
        }
    }
}

public enum PersonalSuggestionKind: Equatable, Sendable {
    /// R-PER-01: User completes >= 40% of tasks in a specific time block (cold start >= 15 tasks in 30d).
    case productiveTimeBlock(block: ProductiveTimeBlock, sharePercent: Int, sampleCount: Int)
    /// R-PER-02: Category has >= 40% late completion rate (cold start >= 10 completed due tasks in 30d).
    case categoryLatenessHabit(categoryId: UUID, categoryName: String, latePercent: Int, sampleCount: Int)
}

public struct PersonalSuggestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let ruleCode: String
    public let kind: PersonalSuggestionKind

    public init(id: String, ruleCode: String, kind: PersonalSuggestionKind) {
        self.id = id
        self.ruleCode = ruleCode
        self.kind = kind
    }
}

/// Deterministic Personal Intelligence Engine (PRD §10.2 & P-09):
/// Produces opt-in suggestions only after cold-start minimums are satisfied — never modifies settings without user confirmation.
public enum PersonalIntelligenceEngine {
    public static let productiveBlockMinSamples = 15
    public static let productiveBlockMinShare = 0.40

    public static let latenessGlobalMinSamples = 10
    public static let latenessCategoryMinSamples = 3
    public static let latenessMinRate = 0.40

    public static func evaluate(
        tasks: [PLATask],
        categories: [PLACategory],
        now: Date,
        timeZone: TimeZone,
        settings: UserSettings
    ) -> [PersonalSuggestion] {
        var suggestions: [PersonalSuggestion] = []
        let thirtyDaysAgo = now.addingTimeInterval(-30.0 * 86400.0)

        let recentCompleted = tasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= thirtyDaysAgo && completedAt <= now
        }

        // R-PER-01: Productive Time Block (cold start >= 15 completed tasks in 30 days)
        if recentCompleted.count >= productiveBlockMinSamples {
            var blockCounts: [ProductiveTimeBlock: Int] = [:]
            var bucketedTotal = 0

            for task in recentCompleted {
                guard let completedAt = task.completedAt else { continue }
                let localDT = LocalDateTime.from(date: completedAt, timeZone: timeZone)
                if let block = ProductiveTimeBlock.block(forHour: localDT.hour) {
                    blockCounts[block, default: 0] += 1
                    bucketedTotal += 1
                }
            }

            if bucketedTotal >= productiveBlockMinSamples,
               let top = blockCounts.max(by: { lhs, rhs in
                   if lhs.value != rhs.value { return lhs.value < rhs.value }
                   return lhs.key.suggestedReminderMinutes > rhs.key.suggestedReminderMinutes
               }) {
                let share = Double(top.value) / Double(bucketedTotal)
                if share >= productiveBlockMinShare,
                   settings.preferredReminderMinutes != top.key.suggestedReminderMinutes {
                    suggestions.append(PersonalSuggestion(
                        id: "R-PER-01|\(top.key.rawValue)",
                        ruleCode: "R-PER-01",
                        kind: .productiveTimeBlock(
                            block: top.key,
                            sharePercent: Int((share * 100.0).rounded()),
                            sampleCount: bucketedTotal
                        )
                    ))
                }
            }
        }

        // R-PER-02: Category Lateness Habit (cold start >= 10 completed tasks WITH dueDate in 30 days)
        let recentCompletedWithDue = recentCompleted.filter { $0.dueDateLocal != nil }
        if recentCompletedWithDue.count >= latenessGlobalMinSamples {
            let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
            var totalByCat: [UUID: Int] = [:]
            var lateByCat: [UUID: Int] = [:]

            for task in recentCompletedWithDue {
                guard let catId = task.categoryId,
                      let completedAt = task.completedAt,
                      let dueDT = task.dueDateTime else { continue }
                totalByCat[catId, default: 0] += 1
                let dueInstant = dueDT.toDate(timeZone: timeZone)
                if completedAt > dueInstant {
                    lateByCat[catId, default: 0] += 1
                }
            }

            let rankedLate = totalByCat
                .compactMap { (catId, total) -> (UUID, Double, Int)? in
                    guard total >= latenessCategoryMinSamples else { return nil }
                    // Skip if user already enabled extra early offset for this category
                    if (settings.extraEarlyReminderDaysByCategory[catId.uuidString] ?? 0) > 0 {
                        return nil
                    }
                    let late = lateByCat[catId] ?? 0
                    let rate = Double(late) / Double(total)
                    guard rate >= latenessMinRate else { return nil }
                    return (catId, rate, total)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.2 > rhs.2
                }

            if let worst = rankedLate.first {
                suggestions.append(PersonalSuggestion(
                    id: "R-PER-02|\(worst.0.uuidString)",
                    ruleCode: "R-PER-02",
                    kind: .categoryLatenessHabit(
                        categoryId: worst.0,
                        categoryName: catMap[worst.0] ?? "Kategori",
                        latePercent: Int((worst.1 * 100.0).rounded()),
                        sampleCount: worst.2
                    )
                ))
            }
        }

        return suggestions
    }
}
