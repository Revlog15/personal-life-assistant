import Foundation

public enum InsightRuleCode: String, Codable, Hashable, Sendable {
    case budgetExceeded = "R-FIN-01"
    case budgetNearLimit = "R-FIN-02"
    case forecastOverBudget = "R-FIN-03"
    case fastBurnPace = "R-FIN-04"
    case categoryBudgetNearLimit = "R-FIN-05a"
    case categoryHistoricalSpike = "R-FIN-05b"
    case categoryDominance = "R-FIN-05c"
}

/// Locale-independent structured insight produced by `InsightEngine` (PRD §10.1).
/// Formatting into Indonesian Rupiah strings happens in `PLAApp` (PRD §5.2).
public struct FinancialInsight: Identifiable, Hashable, Sendable {
    public let id: String
    public let ruleCode: InsightRuleCode
    public let periodKey: String
    public let subjectId: UUID?
    public let severity: InsightSeverity
    public let categoryName: String?
    /// Contextual Rupiah metrics (e.g., overage, freeRemaining, forecastTotal, delta)
    public let primaryAmount: Int64?
    /// Contextual secondary Rupiah metric (e.g., safeDailyLimit, dailyCutNeeded)
    public let secondaryAmount: Int64?
    /// Whole percentage (e.g., 90 for 90%, 25 for +25%)
    public let percentage: Int?
    /// Contextual day count (e.g., remainingDaysInclusive or currentDay)
    public let dayCount: Int?
    /// Total days P (for pace rule)
    public let totalDays: Int?

    public init(
        ruleCode: InsightRuleCode,
        periodKey: String,
        subjectId: UUID? = nil,
        severity: InsightSeverity,
        categoryName: String? = nil,
        primaryAmount: Int64? = nil,
        secondaryAmount: Int64? = nil,
        percentage: Int? = nil,
        dayCount: Int? = nil,
        totalDays: Int? = nil
    ) {
        self.id = "\(ruleCode.rawValue)|\(periodKey)|\(subjectId?.uuidString ?? "global")"
        self.ruleCode = ruleCode
        self.periodKey = periodKey
        self.subjectId = subjectId
        self.severity = severity
        self.categoryName = categoryName
        self.primaryAmount = primaryAmount
        self.secondaryAmount = secondaryAmount
        self.percentage = percentage
        self.dayCount = dayCount
        self.totalDays = totalDays
    }
}

/// Deterministic Financial Insight Engine implementing rules R-FIN-01..05c + cold start + anti-spam (PRD §10.1).
public enum InsightEngine {
    public static let maxDashboardCards = 3

    public static func evaluate(
        summary: FinancialPeriodSummary,
        today: LocalDate,
        cycleStartDay: Int,
        allTransactions: [PLATransaction],
        categories: [Category],
        existingRecords: [InsightRecord] = [],
        maxCards: Int = maxDashboardCards
    ) -> [FinancialInsight] {
        var rawInsights: [FinancialInsight] = []
        let period = summary.period
        let periodKey = period.periodKey

        // R-FIN-01 (Kritis): E_total > B
        if let budget = summary.totalBudget, budget > 0, summary.totalExpense > budget {
            let overage = summary.totalExpense - budget
            let pct = Int((Double(summary.totalExpense) / Double(budget) * 100.0).rounded())
            rawInsights.append(FinancialInsight(
                ruleCode: .budgetExceeded,
                periodKey: periodKey,
                severity: .critical,
                primaryAmount: overage,
                percentage: pct
            ))
        }

        // R-FIN-02 (Tinggi): persenTerpakai >= 0.85 && sisaHari >= 2 (and not already over budget)
        if let budget = summary.totalBudget,
           budget > 0,
           summary.totalExpense <= budget,
           let pctUsed = summary.percentUsed,
           pctUsed >= 0.85,
           period.remainingDaysInclusive >= 2 {
            rawInsights.append(FinancialInsight(
                ruleCode: .budgetNearLimit,
                periodKey: periodKey,
                severity: .high,
                primaryAmount: max(0, summary.freeRemainingBudget ?? 0),
                secondaryAmount: summary.safeDailyLimit ?? 0,
                percentage: Int((pctUsed * 100.0).rounded()),
                dayCount: period.remainingDaysInclusive
            ))
        }

        // R-FIN-03 (Tinggi): forecastTotal > round(B * 1.10), cold start d >= 5 & tx >= 5
        if let budget = summary.totalBudget,
           budget > 0,
           summary.isForecastReady {
            let threshold = Int64((Double(budget) * 1.10).rounded())
            if summary.forecastTotal > threshold {
                let overForecast = summary.forecastTotal - budget
                let pctOver = Int((Double(overForecast) / Double(budget) * 100.0).rounded())
                let sisa = Int64(max(period.remainingDaysInclusive, 1))
                // ceil((forecastTotal - B) / sisaHari)
                let dailyCut = (overForecast + sisa - 1) / sisa
                let topVarCategory = summary.categorySummaries
                    .filter { $0.variableSpent > 0 }
                    .max { $0.variableSpent < $1.variableSpent }
                rawInsights.append(FinancialInsight(
                    ruleCode: .forecastOverBudget,
                    periodKey: periodKey,
                    subjectId: topVarCategory?.id,
                    severity: .high,
                    categoryName: topVarCategory?.categoryName,
                    primaryAmount: summary.forecastTotal,
                    secondaryAmount: dailyCut,
                    percentage: pctOver,
                    dayCount: period.remainingDaysInclusive
                ))
            }
        }

        // R-FIN-04 (Sedang): paceRatio >= 1.25 && persenTerpakai >= 0.30, cold start d >= 5 & tx >= 5
        if let budget = summary.totalBudget,
           budget > 0,
           summary.isForecastReady,
           let pace = summary.paceRatio,
           let pctUsed = summary.percentUsed,
           pace >= 1.25,
           pctUsed >= 0.30 {
            rawInsights.append(FinancialInsight(
                ruleCode: .fastBurnPace,
                periodKey: periodKey,
                severity: .medium,
                percentage: Int((pctUsed * 100.0).rounded()),
                dayCount: period.currentDay,
                totalDays: period.totalDays
            ))
        }

        // R-FIN-05a (Tinggi): budgeted category E_cat >= round(0.85 * B_cat)
        for cat in summary.categorySummaries {
            guard let bCat = cat.budgetAmount, bCat > 0 else { continue }
            let threshold = Int64((0.85 * Double(bCat)).rounded())
            if cat.totalSpent >= threshold {
                let pct = Int((Double(cat.totalSpent) / Double(bCat) * 100.0).rounded())
                rawInsights.append(FinancialInsight(
                    ruleCode: .categoryBudgetNearLimit,
                    periodKey: periodKey,
                    subjectId: cat.id,
                    severity: .high,
                    categoryName: cat.categoryName,
                    primaryAmount: max(0, bCat - cat.totalSpent),
                    percentage: pct
                ))
            }
        }

        // R-FIN-05b (Sedang): historical spike E_cat > round(1.30 * avg3Months(Cat)) and diff >= 50_000
        // Cold start: >= 1 full previous period with >= 10 expense transactions
        let historicalAvgs = computePreviousThreeMonthCategoryAverages(
            currentPeriod: period,
            cycleStartDay: cycleStartDay,
            allTransactions: allTransactions
        )
        if !historicalAvgs.isEmpty {
            let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
            for cat in summary.categorySummaries {
                guard let avg = historicalAvgs[cat.id], avg > 0 else { continue }
                let threshold = Int64((1.30 * avg).rounded())
                let diff = cat.totalSpent - Int64(avg.rounded())
                if cat.totalSpent > threshold && diff >= 50_000 {
                    let pctHigher = Int(((Double(cat.totalSpent) - avg) / avg * 100.0).rounded())
                    rawInsights.append(FinancialInsight(
                        ruleCode: .categoryHistoricalSpike,
                        periodKey: periodKey,
                        subjectId: cat.id,
                        severity: .medium,
                        categoryName: catMap[cat.id] ?? cat.categoryName,
                        primaryAmount: diff,
                        percentage: pctHigher
                    ))
                }
            }
        }

        // R-FIN-05c (Info): 1 variable category > 40% of E_var when jumlahTxExpense >= 3
        if summary.expenseTransactionCount >= 3 && summary.variableExpense > 0 {
            if let dominant = summary.categorySummaries
                .filter({ $0.variableSpent > 0 })
                .max(by: { $0.variableSpent < $1.variableSpent }),
               dominant.percentageOfVariable > 0.40 {
                rawInsights.append(FinancialInsight(
                    ruleCode: .categoryDominance,
                    periodKey: periodKey,
                    subjectId: dominant.id,
                    severity: .info,
                    categoryName: dominant.categoryName,
                    primaryAmount: dominant.variableSpent,
                    percentage: Int((dominant.percentageOfVariable * 100.0).rounded())
                ))
            }
        }

        // Filter dismissed cards unless severity escalated (AC-11.4)
        let filtered = rawInsights.filter { insight in
            let matchingDismissed = existingRecords.filter { rec in
                rec.dismissedAt != nil &&
                rec.ruleCode == insight.ruleCode.rawValue &&
                rec.periodKey == insight.periodKey &&
                rec.subjectId == insight.subjectId
            }
            if matchingDismissed.isEmpty { return true }
            let highestDismissedSeverity = matchingDismissed.map(\.severity).max() ?? .info
            return insight.severity > highestDismissedSeverity
        }

        // Rank: Critical > High > Medium > Info, then deterministic ruleCode & id
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.ruleCode.rawValue != rhs.ruleCode.rawValue {
                return lhs.ruleCode.rawValue < rhs.ruleCode.rawValue
            }
            return lhs.id < rhs.id
        }

        return Array(sorted.prefix(max(0, maxCards)))
    }

    private static func computePreviousThreeMonthCategoryAverages(
        currentPeriod: BudgetPeriod,
        cycleStartDay: Int,
        allTransactions: [PLATransaction]
    ) -> [UUID: Double] {
        var prevPeriods: [BudgetPeriod] = []
        var cursor = currentPeriod
        for _ in 0..<3 {
            cursor = cursor.previousPeriod(cycleStartDay: cycleStartDay)
            prevPeriods.append(cursor)
        }

        var qualifyingPeriods: [[UUID: Int64]] = []
        for p in prevPeriods {
            let expensesInPeriod = allTransactions.filter {
                $0.type == .expense && $0.dateLocal >= p.start && $0.dateLocal <= p.end
            }
            guard expensesInPeriod.count >= 10 else { continue }
            var sums: [UUID: Int64] = [:]
            for tx in expensesInPeriod {
                if let catId = tx.categoryId {
                    sums[catId, default: 0] += tx.amount
                }
            }
            qualifyingPeriods.append(sums)
        }

        guard !qualifyingPeriods.isEmpty else { return [:] }

        var allCatIds = Set<UUID>()
        for dict in qualifyingPeriods {
            allCatIds.formUnion(dict.keys)
        }

        let count = Double(qualifyingPeriods.count)
        var averages: [UUID: Double] = [:]
        for catId in allCatIds {
            let sum = qualifyingPeriods.reduce(Int64(0)) { $0 + ($1[catId] ?? 0) }
            averages[catId] = Double(sum) / count
        }
        return averages
    }
}
