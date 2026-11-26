import Foundation

// MARK: - P-07: WidgetKit Shared Snapshot Models (Home 2x2, Home 4x2, Lock Screen)

public struct PLAWidgetTaskItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var dueDateLocal: LocalDate?
    public var dueTimeMinutes: Int?
    public var priority: TaskPriority
    public var isOverdue: Bool

    public init(
        id: UUID,
        title: String,
        dueDateLocal: LocalDate?,
        dueTimeMinutes: Int?,
        priority: TaskPriority,
        isOverdue: Bool
    ) {
        self.id = id
        self.title = title
        self.dueDateLocal = dueDateLocal
        self.dueTimeMinutes = dueTimeMinutes
        self.priority = priority
        self.isOverdue = isOverdue
    }
}

public struct PLAWidgetBillItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var amount: Int64
    public var dueDateLocal: LocalDate
    public var isOverdue: Bool
    public var isTrial: Bool

    public init(
        id: UUID,
        name: String,
        amount: Int64,
        dueDateLocal: LocalDate,
        isOverdue: Bool,
        isTrial: Bool
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDateLocal = dueDateLocal
        self.isOverdue = isOverdue
        self.isTrial = isTrial
    }
}

public struct PLAWidgetDeadlineItem: Codable, Equatable, Sendable {
    public var title: String
    public var isBill: Bool
    public var dueDateLocal: LocalDate
    public var dueTimeMinutes: Int?
    public var daysRemaining: Int
    public var isOverdue: Bool

    public init(
        title: String,
        isBill: Bool,
        dueDateLocal: LocalDate,
        dueTimeMinutes: Int?,
        daysRemaining: Int,
        isOverdue: Bool
    ) {
        self.title = title
        self.isBill = isBill
        self.dueDateLocal = dueDateLocal
        self.dueTimeMinutes = dueTimeMinutes
        self.daysRemaining = daysRemaining
        self.isOverdue = isOverdue
    }
}

public struct PLAWidgetSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var snapshotDate: LocalDate
    public var maskAmounts: Bool
    public var showBudgetStatusWhenMasked: Bool
    public var hasBudget: Bool
    public var budgetTotal: Int64
    public var spentTotal: Int64
    public var freeRemaining: Int64
    public var safeDailyLimit: Int64
    public var percentUsed: Double
    public var budgetStatus: BudgetHealthStatus
    public var daysRemainingInPeriod: Int
    public var overdueTaskCount: Int
    public var todayTaskCount: Int
    public var todayTasks: [PLAWidgetTaskItem]
    public var upcomingBills: [PLAWidgetBillItem]
    public var nearestDeadline: PLAWidgetDeadlineItem?

    public init(
        generatedAt: Date,
        snapshotDate: LocalDate,
        maskAmounts: Bool,
        showBudgetStatusWhenMasked: Bool = true,
        hasBudget: Bool,
        budgetTotal: Int64,
        spentTotal: Int64,
        freeRemaining: Int64,
        safeDailyLimit: Int64,
        percentUsed: Double,
        budgetStatus: BudgetHealthStatus,
        daysRemainingInPeriod: Int,
        overdueTaskCount: Int,
        todayTaskCount: Int,
        todayTasks: [PLAWidgetTaskItem],
        upcomingBills: [PLAWidgetBillItem],
        nearestDeadline: PLAWidgetDeadlineItem?
    ) {
        self.generatedAt = generatedAt
        self.snapshotDate = snapshotDate
        self.maskAmounts = maskAmounts
        self.showBudgetStatusWhenMasked = showBudgetStatusWhenMasked
        self.hasBudget = hasBudget
        self.budgetTotal = budgetTotal
        self.spentTotal = spentTotal
        self.freeRemaining = freeRemaining
        self.safeDailyLimit = safeDailyLimit
        self.percentUsed = percentUsed
        self.budgetStatus = budgetStatus
        self.daysRemainingInPeriod = daysRemainingInPeriod
        self.overdueTaskCount = overdueTaskCount
        self.todayTaskCount = todayTaskCount
        self.todayTasks = todayTasks
        self.upcomingBills = upcomingBills
        self.nearestDeadline = nearestDeadline
    }
}

/// Deterministic builder for P-07 WidgetKit snapshots (Home 2x2 Budget, Home 4x2 Agenda, Lock Screen Deadline).
public enum WidgetSnapshotBuilder {
    public static func build(
        today: LocalDate,
        now: LocalDateTime,
        summary: FinancialPeriodSummary,
        tasks: [PLATask],
        bills: [Bill],
        settings: UserSettings,
        generatedAt: Date
    ) -> PLAWidgetSnapshot {
        let overdueTasks = tasks.filter { $0.isOverdue(at: now) }
        let todayActive = tasks.filter { task in
            task.status == .active && task.dueDateLocal == today && !task.isOverdue(at: now)
        }

        let combinedTodayAndOverdue: [PLATask] = (overdueTasks + todayActive).sorted { lhs, rhs in
            let lOverdue = lhs.isOverdue(at: now)
            let rOverdue = rhs.isOverdue(at: now)
            if lOverdue != rOverdue { return lOverdue }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return (lhs.dueTimeMinutes ?? 1440) < (rhs.dueTimeMinutes ?? 1440)
        }

        let widgetTasks = combinedTodayAndOverdue.prefix(4).map { task in
            PLAWidgetTaskItem(
                id: task.id,
                title: task.title,
                dueDateLocal: task.dueDateLocal,
                dueTimeMinutes: task.dueTimeMinutes,
                priority: task.priority,
                isOverdue: task.isOverdue(at: now)
            )
        }

        let horizon7 = today.addingDays(7)
        let activeBills = bills
            .filter { $0.isActive && $0.nextDueDateLocal <= horizon7 }
            .sorted { $0.nextDueDateLocal < $1.nextDueDateLocal }

        let widgetBills = activeBills.prefix(3).map { bill in
            PLAWidgetBillItem(
                id: bill.id,
                name: bill.name,
                amount: bill.amount,
                dueDateLocal: bill.nextDueDateLocal,
                isOverdue: bill.nextDueDateLocal < today,
                isTrial: bill.isTrial
            )
        }

        // Nearest deadline across all active dated tasks and active bills (for Lock Screen widget)
        var deadlineCandidates: [PLAWidgetDeadlineItem] = []

        for task in tasks where task.status == .active {
            guard let due = task.dueDateLocal else { continue }
            let days = today.days(until: due)
            deadlineCandidates.append(
                PLAWidgetDeadlineItem(
                    title: task.title,
                    isBill: false,
                    dueDateLocal: due,
                    dueTimeMinutes: task.dueTimeMinutes,
                    daysRemaining: days,
                    isOverdue: task.isOverdue(at: now)
                )
            )
        }

        for bill in bills where bill.isActive {
            let due = bill.isTrial ? (bill.trialEndDateLocal ?? bill.nextDueDateLocal) : bill.nextDueDateLocal
            let days = today.days(until: due)
            deadlineCandidates.append(
                PLAWidgetDeadlineItem(
                    title: bill.isTrial ? "Trial: \(bill.name)" : bill.name,
                    isBill: true,
                    dueDateLocal: due,
                    dueTimeMinutes: 9 * 60,
                    daysRemaining: days,
                    isOverdue: due < today
                )
            )
        }

        let nearest = deadlineCandidates.sorted { lhs, rhs in
            if lhs.dueDateLocal != rhs.dueDateLocal {
                return lhs.dueDateLocal < rhs.dueDateLocal
            }
            return (lhs.dueTimeMinutes ?? 1440) < (rhs.dueTimeMinutes ?? 1440)
        }.first

        let shouldMask = settings.financeLockEnabled
        let budgetAmount = summary.totalBudget ?? 0
        let hasBudget = budgetAmount > 0

        return PLAWidgetSnapshot(
            generatedAt: generatedAt,
            snapshotDate: today,
            maskAmounts: shouldMask,
            showBudgetStatusWhenMasked: settings.showBudgetStatusWhenLocked,
            hasBudget: hasBudget,
            budgetTotal: budgetAmount,
            spentTotal: summary.totalExpense,
            freeRemaining: summary.freeRemainingBudget ?? 0,
            safeDailyLimit: summary.safeDailyLimit ?? 0,
            percentUsed: summary.percentUsed ?? 0.0,
            budgetStatus: summary.budgetStatus,
            daysRemainingInPeriod: summary.period.remainingDaysInclusive,
            overdueTaskCount: overdueTasks.count,
            todayTaskCount: todayActive.count,
            todayTasks: widgetTasks,
            upcomingBills: widgetBills,
            nearestDeadline: nearest
        )
    }
}

// MARK: - P-06 & P-07: Shared Text-Only OCR Payload & Deep-Link URL Codec (`pla://`)

/// Strictly text-only OCR handoff shared between Share Extension (P-06), ScanReceiptIntent (P-05), and PLAApp.
/// Never contains image bytes (PRD §13.4).
public struct SharedOCRReceiptPayload: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var amount: Int64?
    public var date: LocalDate?
    public var merchant: String?
    public var detectedSourceApp: String?
    public var rawLineCount: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        amount: Int64? = nil,
        date: LocalDate? = nil,
        merchant: String? = nil,
        detectedSourceApp: String? = nil,
        rawLineCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.detectedSourceApp = detectedSourceApp
        self.rawLineCount = rawLineCount
        self.createdAt = createdAt
    }

    public init(parsed: ParsedReceiptOCR, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.amount = parsed.amount
        self.date = parsed.date
        self.merchant = parsed.merchant
        self.detectedSourceApp = parsed.detectedSourceApp
        self.rawLineCount = parsed.rawLineCount
        self.createdAt = createdAt
    }
}

public enum PLAURLRoute: Equatable, Sendable {
    case dashboard
    case tasks
    case finance
    case settings
    case quickAddTask
    case quickAddExpense
    case ocrDraft(SharedOCRReceiptPayload)

    public static let scheme = "pla"

    public static func makeTabURL(_ route: PLAURLRoute) -> URL? {
        switch route {
        case .dashboard: return URL(string: "\(scheme)://tab/dashboard")
        case .tasks: return URL(string: "\(scheme)://tab/tasks")
        case .finance: return URL(string: "\(scheme)://tab/finance")
        case .settings: return URL(string: "\(scheme)://tab/settings")
        case .quickAddTask: return URL(string: "\(scheme)://quick-add/task")
        case .quickAddExpense: return URL(string: "\(scheme)://quick-add/expense")
        case .ocrDraft(let payload): return makeOCRDraftURL(payload)
        }
    }

    /// Encodes a text-only OCR draft as a `pla://ocr-draft?...` deep link (fallback when App Group container is unavailable under V-07).
    public static func makeOCRDraftURL(_ payload: SharedOCRReceiptPayload) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "ocr-draft"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "id", value: payload.id.uuidString),
            URLQueryItem(name: "lines", value: String(payload.rawLineCount))
        ]
        if let amount = payload.amount {
            items.append(URLQueryItem(name: "amount", value: String(amount)))
        }
        if let date = payload.date {
            items.append(URLQueryItem(name: "date", value: date.isoString))
        }
        if let merchant = payload.merchant, !merchant.isEmpty {
            items.append(URLQueryItem(name: "merchant", value: String(merchant.prefix(120))))
        }
        if let source = payload.detectedSourceApp, !source.isEmpty {
            items.append(URLQueryItem(name: "source", value: String(source.prefix(40))))
        }
        components.queryItems = items
        return components.url
    }

    public static func parse(url: URL) -> PLAURLRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host ?? "").lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }

        switch host {
        case "tab":
            switch pathParts.first {
            case "tasks": return .tasks
            case "finance": return .finance
            case "settings": return .settings
            default: return .dashboard
            }
        case "quick-add":
            switch pathParts.first {
            case "expense": return .quickAddExpense
            default: return .quickAddTask
            }
        case "ocr-draft":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name.lowercased(), $0) }
                }
            )
            let id = query["id"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let amount = query["amount"].flatMap(Int64.init)
            let date = query["date"].flatMap(LocalDate.init(isoString:))
            let merchant = query["merchant"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = query["source"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = query["lines"].flatMap(Int.init) ?? 0
            let payload = SharedOCRReceiptPayload(
                id: id,
                amount: amount,
                date: date,
                merchant: (merchant?.isEmpty == false) ? merchant : nil,
                detectedSourceApp: (source?.isEmpty == false) ? source : nil,
                rawLineCount: lines
            )
            return .ocrDraft(payload)
        default:
            return nil
        }
    }
}
