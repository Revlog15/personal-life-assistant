import Foundation

public struct BudgetPeriod: Hashable, Sendable {
    public let start: LocalDate
    public let end: LocalDate
    /// Key representing the active cycle (e.g. "2026-11")
    public let periodKey: String
    /// Total calendar days P (28...31)
    public let totalDays: Int
    /// Current day index d (1...P)
    public let currentDay: Int
    /// Remaining days inclusive of today: max(P - d + 1, 1)
    public let remainingDaysInclusive: Int
    /// Full days strictly after today: max(P - d, 0)
    public let remainingDaysAfterToday: Int

    public static func current(for today: LocalDate, cycleStartDay: Int) -> BudgetPeriod {
        let clampedStart = min(max(cycleStartDay, 1), 28)
        let startDate: LocalDate
        let endDate: LocalDate

        if clampedStart == 1 {
            startDate = LocalDate(year: today.year, month: today.month, day: 1)!
            let lastDay = LocalDate.daysInMonth(year: today.year, month: today.month)
            endDate = LocalDate(year: today.year, month: today.month, day: lastDay)!
        } else if today.day >= clampedStart {
            startDate = LocalDate(year: today.year, month: today.month, day: clampedStart)!
            endDate = startDate.addingMonths(1, anchorDay: clampedStart).addingDays(-1)
        } else {
            let prev = today.addingMonths(-1, anchorDay: clampedStart)
            startDate = prev
            endDate = LocalDate(year: today.year, month: today.month, day: clampedStart)!.addingDays(-1)
        }

        let p = max(startDate.days(until: endDate) + 1, 1)
        let rawDay = startDate.days(until: today) + 1
        let d = min(max(rawDay, 1), p)
        let sisaHari = max(p - d + 1, 1)
        let hariSetelahIni = max(p - d, 0)

        return BudgetPeriod(
            start: startDate,
            end: endDate,
            periodKey: startDate.yearMonthString,
            totalDays: p,
            currentDay: d,
            remainingDaysInclusive: sisaHari,
            remainingDaysAfterToday: hariSetelahIni
        )
    }

    public func previousPeriod(cycleStartDay: Int) -> BudgetPeriod {
        let dayBeforeStart = start.addingDays(-1)
        return BudgetPeriod.current(for: dayBeforeStart, cycleStartDay: cycleStartDay)
    }
}

public enum BudgetHealthStatus: String, Codable, Hashable, Sendable {
    case notSet
    case safe       // < 75%
    case warning    // 75% ..< 100%
    case exceeded   // >= 100%
}

public struct CategorySpendingSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let categoryName: String
    public let totalSpent: Int64
    public let variableSpent: Int64
    public let budgetAmount: Int64?
    public let percentageOfBudget: Double?
    public let percentageOfVariable: Double
    public let status: BudgetHealthStatus
}

public struct FinancialPeriodSummary: Equatable, Sendable {
    public let period: BudgetPeriod
    public let totalIncome: Int64
    /// E_total (expense transactions in period up to today; transfers excluded)
    public let totalExpense: Int64
    /// E_bill_paid (portion of totalExpense linked to a bill)
    public let paidBillsExpense: Int64
    /// E_bill_due (unpaid active bills due within this period)
    public let unpaidBillsDue: Int64
    /// E_var = E_total - E_bill_paid
    public let variableExpense: Int64
    public let expenseTransactionCount: Int
    /// Net cash flow = totalIncome - totalExpense
    public let netCashFlow: Int64
    /// B (nil or <= 0 means budget not set)
    public let totalBudget: Int64?
    /// E_total / B
    public let percentUsed: Double?
    /// B - E_total
    public let remainingBudget: Int64?
    /// B - E_total - E_bill_due
    public let freeRemainingBudget: Int64?
    /// max(0, floor(sisaBebas / sisaHari))
    public let safeDailyLimit: Int64?
    /// E_var / max(d, 1)
    public let averageDailyVariableExpense: Double
    /// Forecast total: E_total + E_bill_due + round(rataHarianVar * hariSetelahIni)
    public let forecastTotal: Int64
    /// True only when d >= 5 AND expenseTransactionCount >= 5 (PRD §10.1 cold start)
    public let isForecastReady: Bool
    /// (E_total / B) / (d / P)
    public let paceRatio: Double?
    public let budgetStatus: BudgetHealthStatus
    public let categorySummaries: [CategorySpendingSummary]
    public let topExpenseCategories: [CategorySpendingSummary]
}

/// Computes Account balances from initialBalance + transactions (single source of truth, PRD §11.3).
public enum AccountBalanceCalculator {
    public static func balance(for account: Account, transactions: [PLATransaction]) -> Int64 {
        var total = account.initialBalance
        for tx in transactions {
            switch tx.type {
            case .income:
                if tx.accountId == account.id {
                    total += tx.amount
                }
            case .expense:
                if tx.accountId == account.id {
                    total -= tx.amount
                }
            case .transfer:
                if tx.accountId == account.id {
                    total -= tx.amount
                }
                if tx.destinationAccountId == account.id {
                    total += tx.amount
                }
            }
        }
        return total
    }

    public static func balancesByAccount(
        accounts: [Account],
        transactions: [PLATransaction]
    ) -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for acc in accounts {
            result[acc.id] = acc.initialBalance
        }
        for tx in transactions {
            switch tx.type {
            case .income:
                if result[tx.accountId] != nil {
                    result[tx.accountId, default: 0] += tx.amount
                }
            case .expense:
                if result[tx.accountId] != nil {
                    result[tx.accountId, default: 0] -= tx.amount
                }
            case .transfer:
                if result[tx.accountId] != nil {
                    result[tx.accountId, default: 0] -= tx.amount
                }
                if let dest = tx.destinationAccountId, result[dest] != nil {
                    result[dest, default: 0] += tx.amount
                }
            }
        }
        return result
    }

    public static func totalLiquidWealth(accounts: [Account], transactions: [PLATransaction]) -> Int64 {
        let balances = balancesByAccount(accounts: accounts, transactions: transactions)
        return accounts
            .filter { !$0.isArchived }
            .reduce(Int64(0)) { $0 + (balances[$1.id] ?? $1.initialBalance) }
    }
}

/// Deterministic Financial & Forecast Calculator matching PRD §10.1 formulas to the exact rupiah.
public enum BudgetCalculator {
    public static func summarize(
        today: LocalDate,
        cycleStartDay: Int,
        transactions: [PLATransaction],
        budgets: [Budget],
        bills: [Bill],
        categories: [PLACategory]
    ) -> FinancialPeriodSummary {
        let period = BudgetPeriod.current(for: today, cycleStartDay: cycleStartDay)
        return summarize(
            period: period,
            asOfDate: today,
            transactions: transactions,
            budgets: budgets,
            bills: bills,
            categories: categories
        )
    }

    public static func summarize(
        period: BudgetPeriod,
        asOfDate: LocalDate,
        transactions: [PLATransaction],
        budgets: [Budget],
        bills: [Bill],
        categories: [PLACategory]
    ) -> FinancialPeriodSummary {
        let effectiveEnd = min(asOfDate, period.end)

        var totalIncome: Int64 = 0
        var totalExpense: Int64 = 0
        var paidBillsExpense: Int64 = 0
        var expenseCount = 0

        var spentByCategory: [UUID: Int64] = [:]
        var varSpentByCategory: [UUID: Int64] = [:]

        for tx in transactions {
            // Only count transactions inside [period.start ... effectiveEnd]; post-dated future tx excluded until date arrives (PRD §12)
            guard tx.dateLocal >= period.start && tx.dateLocal <= effectiveEnd else { continue }
            switch tx.type {
            case .income:
                totalIncome += tx.amount
            case .expense:
                totalExpense += tx.amount
                expenseCount += 1
                if tx.billId != nil {
                    paidBillsExpense += tx.amount
                }
                if let catId = tx.categoryId {
                    spentByCategory[catId, default: 0] += tx.amount
                    if tx.billId == nil {
                        varSpentByCategory[catId, default: 0] += tx.amount
                    }
                }
            case .transfer:
                // AC-09.2: Transfers never count as income, expense, or budget usage
                continue
            }
        }

        // Unpaid active bills due within or before period.end (once paid, nextDueDateLocal advances past period.end)
        let unpaidBillsDue: Int64 = bills
            .filter { $0.isActive && $0.nextDueDateLocal <= period.end }
            .reduce(Int64(0)) { $0 + $1.amount }

        let variableExpense = max(Int64(0), totalExpense - paidBillsExpense)
        let netCashFlow = totalIncome - totalExpense

        // Resolve effective budgets for period.periodKey (latest effectiveFromMonth <= periodKey)
        let activeTotalBudget = resolveEffectiveBudget(categoryId: nil, periodKey: period.periodKey, budgets: budgets)
        let totalBudgetAmount = (activeTotalBudget?.amount ?? 0) > 0 ? activeTotalBudget?.amount : nil

        let percentUsed: Double?
        let remainingBudget: Int64?
        let freeRemainingBudget: Int64?
        let safeDailyLimit: Int64?
        let paceRatio: Double?
        let budgetStatus: BudgetHealthStatus

        if let b = totalBudgetAmount, b > 0 {
            let pct = Double(totalExpense) / Double(b)
            percentUsed = pct
            let sisa = b - totalExpense
            remainingBudget = sisa
            let sisaBebas = sisa - unpaidBillsDue
            freeRemainingBudget = sisaBebas
            safeDailyLimit = sisaBebas > 0 ? (sisaBebas / Int64(period.remainingDaysInclusive)) : 0
            let dayFraction = Double(period.currentDay) / Double(max(period.totalDays, 1))
            paceRatio = dayFraction > 0 ? (pct / dayFraction) : nil

            if pct >= 1.0 {
                budgetStatus = .exceeded
            } else if pct >= 0.75 {
                budgetStatus = .warning
            } else {
                budgetStatus = .safe
            }
        } else {
            percentUsed = nil
            remainingBudget = nil
            freeRemainingBudget = nil
            safeDailyLimit = nil
            paceRatio = nil
            budgetStatus = .notSet
        }

        let avgDailyVar = Double(variableExpense) / Double(max(period.currentDay, 1))
        let projectedRemainder = Int64((avgDailyVar * Double(period.remainingDaysAfterToday)).rounded())
        let forecastTotal = totalExpense + unpaidBillsDue + projectedRemainder
        let isForecastReady = period.currentDay >= 5 && expenseCount >= 5

        // Build per-category summaries
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let allRelevantCategoryIds = Set(spentByCategory.keys)
            .union(
                budgets
                    .filter { $0.isActive && $0.categoryId != nil && $0.effectiveFromMonth <= period.periodKey }
                    .compactMap(\.categoryId)
            )

        var categorySummaries: [CategorySpendingSummary] = []
        for catId in allRelevantCategoryIds {
            let spent = spentByCategory[catId] ?? 0
            let varSpent = varSpentByCategory[catId] ?? 0
            let catBudget = resolveEffectiveBudget(categoryId: catId, periodKey: period.periodKey, budgets: budgets)?.amount
            let validBudget = (catBudget ?? 0) > 0 ? catBudget : nil
            let catPct: Double? = validBudget.map { Double(spent) / Double($0) }
            let status: BudgetHealthStatus
            if let pct = catPct {
                if pct >= 1.0 { status = .exceeded }
                else if pct >= 0.75 { status = .warning }
                else { status = .safe }
            } else {
                status = .notSet
            }
            let pctOfVar = variableExpense > 0 ? Double(varSpent) / Double(variableExpense) : 0
            categorySummaries.append(CategorySpendingSummary(
                id: catId,
                categoryName: catMap[catId]?.name ?? "Kategori",
                totalSpent: spent,
                variableSpent: varSpent,
                budgetAmount: validBudget,
                percentageOfBudget: catPct,
                percentageOfVariable: pctOfVar,
                status: status
            ))
        }

        categorySummaries.sort {
            if $0.totalSpent != $1.totalSpent { return $0.totalSpent > $1.totalSpent }
            return $0.categoryName < $1.categoryName
        }

        let topExpense = Array(categorySummaries.filter { $0.totalSpent > 0 }.prefix(3))

        return FinancialPeriodSummary(
            period: period,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            paidBillsExpense: paidBillsExpense,
            unpaidBillsDue: unpaidBillsDue,
            variableExpense: variableExpense,
            expenseTransactionCount: expenseCount,
            netCashFlow: netCashFlow,
            totalBudget: totalBudgetAmount,
            percentUsed: percentUsed,
            remainingBudget: remainingBudget,
            freeRemainingBudget: freeRemainingBudget,
            safeDailyLimit: safeDailyLimit,
            averageDailyVariableExpense: avgDailyVar,
            forecastTotal: forecastTotal,
            isForecastReady: isForecastReady,
            paceRatio: paceRatio,
            budgetStatus: budgetStatus,
            categorySummaries: categorySummaries,
            topExpenseCategories: topExpense
        )
    }

    public static func resolveEffectiveBudget(
        categoryId: UUID?,
        periodKey: String,
        budgets: [Budget]
    ) -> Budget? {
        budgets
            .filter { $0.isActive && $0.categoryId == categoryId && $0.effectiveFromMonth <= periodKey }
            .sorted {
                if $0.effectiveFromMonth != $1.effectiveFromMonth {
                    return $0.effectiveFromMonth > $1.effectiveFromMonth
                }
                return $0.updatedAt > $1.updatedAt
            }
            .first
    }
}
