import Foundation

public enum SavingsGoalPaceStatus: String, Hashable, Sendable {
    case achieved
    case onTrack
    case overdue
    case noDeadline
}

public struct SavingsGoalProgress: Equatable, Sendable {
    public let goal: SavingsGoal
    public let percentComplete: Double
    public let remainingAmount: Int64
    public let daysRemaining: Int?
    public let requiredMonthlyDeposit: Int64?
    public let requiredWeeklyDeposit: Int64?
    public let paceStatus: SavingsGoalPaceStatus

    public init(
        goal: SavingsGoal,
        percentComplete: Double,
        remainingAmount: Int64,
        daysRemaining: Int?,
        requiredMonthlyDeposit: Int64?,
        requiredWeeklyDeposit: Int64?,
        paceStatus: SavingsGoalPaceStatus
    ) {
        self.goal = goal
        self.percentComplete = percentComplete
        self.remainingAmount = remainingAmount
        self.daysRemaining = daysRemaining
        self.requiredMonthlyDeposit = requiredMonthlyDeposit
        self.requiredWeeklyDeposit = requiredWeeklyDeposit
        self.paceStatus = paceStatus
    }
}

/// Deterministic Savings Goal calculator (PRD P-03).
public enum SavingsGoalCalculator {
    public static func evaluate(goal: SavingsGoal, today: LocalDate) -> SavingsGoalProgress {
        let target = max(Int64(1), goal.targetAmount)
        let current = max(Int64(0), goal.currentAmount)
        let remaining = max(Int64(0), target - current)
        let pct = min(Double(current) / Double(target), 1.0)

        if remaining == 0 || goal.status == .achieved {
            return SavingsGoalProgress(
                goal: goal,
                percentComplete: 1.0,
                remainingAmount: 0,
                daysRemaining: goal.targetDateLocal.map { today.days(until: $0) },
                requiredMonthlyDeposit: 0,
                requiredWeeklyDeposit: 0,
                paceStatus: .achieved
            )
        }

        guard let targetDate = goal.targetDateLocal else {
            return SavingsGoalProgress(
                goal: goal,
                percentComplete: pct,
                remainingAmount: remaining,
                daysRemaining: nil,
                requiredMonthlyDeposit: nil,
                requiredWeeklyDeposit: nil,
                paceStatus: .noDeadline
            )
        }

        let days = today.days(until: targetDate)
        if days <= 0 {
            return SavingsGoalProgress(
                goal: goal,
                percentComplete: pct,
                remainingAmount: remaining,
                daysRemaining: days,
                requiredMonthlyDeposit: remaining,
                requiredWeeklyDeposit: remaining,
                paceStatus: .overdue
            )
        }

        let months = max(Int64(1), Int64((Double(days) / 30.0).rounded(.up)))
        let weeks = max(Int64(1), Int64((Double(days) / 7.0).rounded(.up)))
        let monthlyDeposit = (remaining + months - 1) / months
        let weeklyDeposit = (remaining + weeks - 1) / weeks

        return SavingsGoalProgress(
            goal: goal,
            percentComplete: pct,
            remainingAmount: remaining,
            daysRemaining: days,
            requiredMonthlyDeposit: monthlyDeposit,
            requiredWeeklyDeposit: weeklyDeposit,
            paceStatus: .onTrack
        )
    }
}
