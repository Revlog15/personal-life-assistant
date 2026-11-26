import Foundation

public enum WhatIfVerdict: String, Equatable, Sendable {
    case comfortable
    case tightenDaily
    case exceedsBudget
    case noBudgetSet
}

public struct WhatIfSimulationResult: Equatable, Sendable {
    public let plannedAmount: Int64
    public let beforeTotalExpense: Int64
    public let afterTotalExpense: Int64
    public let beforeFreeRemaining: Int64?
    public let afterFreeRemaining: Int64?
    public let beforeSafeDailyLimit: Int64?
    public let afterSafeDailyLimit: Int64?
    public let safeDailyDrop: Int64?
    public let beforeForecastTotal: Int64
    public let afterForecastTotal: Int64
    public let beforeBudgetStatus: BudgetHealthStatus
    public let afterBudgetStatus: BudgetHealthStatus
    public let afterPercentUsed: Double?
    public let verdict: WhatIfVerdict
}

/// Non-mutating "Bagaimana Jika" financial purchase simulator using the exact same `BudgetCalculator` formulas (PRD P-04).
public enum WhatIfSimulator {
    public static func simulatePurchase(
        summary: FinancialPeriodSummary,
        plannedAmount: Int64
    ) -> WhatIfSimulationResult {
        let clampedPlanned = max(Int64(0), plannedAmount)
        let afterExpense = summary.totalExpense + clampedPlanned
        let afterForecast = summary.forecastTotal + clampedPlanned

        guard let budget = summary.totalBudget, budget > 0 else {
            return WhatIfSimulationResult(
                plannedAmount: clampedPlanned,
                beforeTotalExpense: summary.totalExpense,
                afterTotalExpense: afterExpense,
                beforeFreeRemaining: nil,
                afterFreeRemaining: nil,
                beforeSafeDailyLimit: nil,
                afterSafeDailyLimit: nil,
                safeDailyDrop: nil,
                beforeForecastTotal: summary.forecastTotal,
                afterForecastTotal: afterForecast,
                beforeBudgetStatus: .notSet,
                afterBudgetStatus: .notSet,
                afterPercentUsed: nil,
                verdict: .noBudgetSet
            )
        }

        let afterPct = Double(afterExpense) / Double(budget)
        let afterFree = (summary.freeRemainingBudget ?? (budget - summary.totalExpense - summary.unpaidBillsDue)) - clampedPlanned
        let sisaHari = Int64(max(summary.period.remainingDaysInclusive, 1))
        let afterSafeDaily = afterFree > 0 ? (afterFree / sisaHari) : 0
        let beforeSafeDaily = summary.safeDailyLimit ?? 0
        let drop = max(Int64(0), beforeSafeDaily - afterSafeDaily)

        let afterStatus: BudgetHealthStatus
        if afterPct >= 1.0 {
            afterStatus = .exceeded
        } else if afterPct >= 0.75 {
            afterStatus = .warning
        } else {
            afterStatus = .safe
        }

        let verdict: WhatIfVerdict
        if afterExpense > budget || afterFree < 0 {
            verdict = .exceedsBudget
        } else if afterPct >= 0.85 || (summary.isForecastReady && afterForecast > budget) {
            verdict = .tightenDaily
        } else {
            verdict = .comfortable
        }

        return WhatIfSimulationResult(
            plannedAmount: clampedPlanned,
            beforeTotalExpense: summary.totalExpense,
            afterTotalExpense: afterExpense,
            beforeFreeRemaining: summary.freeRemainingBudget,
            afterFreeRemaining: afterFree,
            beforeSafeDailyLimit: beforeSafeDaily,
            afterSafeDailyLimit: afterSafeDaily,
            safeDailyDrop: drop,
            beforeForecastTotal: summary.forecastTotal,
            afterForecastTotal: afterForecast,
            beforeBudgetStatus: summary.budgetStatus,
            afterBudgetStatus: afterStatus,
            afterPercentUsed: afterPct,
            verdict: verdict
        )
    }
}
