import WidgetKit
import SwiftUI
import PLACore

// MARK: - Timeline Entry & Provider

struct PLAWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PLAWidgetSnapshot?
    let isPlaceholder: Bool
}

struct PLATimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PLAWidgetEntry {
        PLAWidgetEntry(date: Date(), snapshot: Self.sampleSnapshot, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PLAWidgetEntry) -> Void) {
        if let live = PLASharedContainer.loadWidgetSnapshot() {
            completion(PLAWidgetEntry(date: Date(), snapshot: live, isPlaceholder: false))
        } else if context.isPreview {
            completion(PLAWidgetEntry(date: Date(), snapshot: Self.sampleSnapshot, isPlaceholder: true))
        } else {
            completion(PLAWidgetEntry(date: Date(), snapshot: nil, isPlaceholder: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PLAWidgetEntry>) -> Void) {
        let now = Date()
        let live = PLASharedContainer.loadWidgetSnapshot()
        let entry = PLAWidgetEntry(date: now, snapshot: live, isPlaceholder: false)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static var sampleSnapshot: PLAWidgetSnapshot {
        let today = LocalDate.from(date: Date(), timeZone: .current)
        return PLAWidgetSnapshot(
            generatedAt: Date(),
            snapshotDate: today,
            maskAmounts: false,
            showBudgetStatusWhenMasked: true,
            hasBudget: true,
            budgetTotal: 3_000_000,
            spentTotal: 1_850_000,
            freeRemaining: 800_000,
            safeDailyLimit: 80_000,
            percentUsed: 0.62,
            budgetStatus: .safe,
            daysRemainingInPeriod: 10,
            overdueTaskCount: 0,
            todayTaskCount: 2,
            todayTasks: [
                PLAWidgetTaskItem(id: UUID(), title: "Kirim laporan mingguan", dueDateLocal: today, dueTimeMinutes: 15 * 60, priority: .high, isOverdue: false),
                PLAWidgetTaskItem(id: UUID(), title: "Review anggaran bulan ini", dueDateLocal: today, dueTimeMinutes: 19 * 60, priority: .medium, isOverdue: false)
            ],
            upcomingBills: [
                PLAWidgetBillItem(id: UUID(), name: "Internet Biznet", amount: 350_000, dueDateLocal: today.addingDays(2), isOverdue: false, isTrial: false)
            ],
            nearestDeadline: PLAWidgetDeadlineItem(
                title: "Kirim laporan mingguan",
                isBill: false,
                dueDateLocal: today,
                dueTimeMinutes: 15 * 60,
                daysRemaining: 0,
                isOverdue: false
            )
        )
    }
}

// MARK: - Widget Formatters (Self-Contained, Zero UIKit/GRDB)

private enum PLAWidgetFormat {
    static let accent = Color(red: 0.145, green: 0.388, blue: 0.922) // #2563EB Royal Blue

    static func rupiah(_ amount: Int64) -> String {
        let isNegative = amount < 0
        let absVal = abs(amount)
        let raw = Array(String(absVal))
        var grouped = ""
        for idx in raw.indices {
            if idx > 0 && (raw.count - idx) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(raw[idx])
        }
        return isNegative ? "-Rp\(grouped)" : "Rp\(grouped)"
    }

    static func compactRupiah(_ amount: Int64) -> String {
        let isNegative = amount < 0
        let absVal = Double(abs(amount))
        let prefix = isNegative ? "-Rp" : "Rp"
        if absVal >= 1_000_000 {
            return "\(prefix)\(String(format: "%.1f", absVal / 1_000_000).replacingOccurrences(of: ".", with: ",")) jt"
        }
        if absVal >= 1_000 {
            return "\(prefix)\(Int(absVal / 1_000)) rb"
        }
        return rupiah(amount)
    }

    static func timeString(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 1439)
        let h = clamped / 60
        let m = clamped % 60
        return String(format: "%02d.%02d", h, m)
    }

    static func shortDate(_ date: LocalDate) -> String {
        let months = ["", "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]
        let m = (1...12).contains(date.month) ? months[date.month] : ""
        return "\(date.day) \(m)"
    }

    static func statusLabel(_ status: BudgetHealthStatus) -> String {
        switch status {
        case .notSet: return "Belum Diatur"
        case .safe: return "Aman"
        case .warning: return "Waspada"
        case .exceeded: return "Melebihi"
        }
    }

    static func statusIcon(_ status: BudgetHealthStatus) -> String {
        switch status {
        case .notSet: return "sliders"
        case .safe: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .exceeded: return "xmark.octagon.fill"
        }
    }

    static func statusColor(_ status: BudgetHealthStatus) -> Color {
        switch status {
        case .notSet: return .secondary
        case .safe: return .green
        case .warning: return .orange
        case .exceeded: return .red
        }
    }

    static func priorityIcon(_ priority: TaskPriority) -> String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "circle.fill"
        case .low: return "arrow.down.circle"
        }
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        }
    }

    static func countdownText(daysRemaining: Int, isOverdue: Bool, dueTimeMinutes: Int?) -> String {
        if isOverdue { return "Terlambat" }
        if daysRemaining == 0 {
            if let mins = dueTimeMinutes {
                return "Hari ini \(timeString(mins))"
            }
            return "Hari ini"
        }
        if daysRemaining == 1 { return "Besok" }
        return "H-\(daysRemaining)"
    }
}

// MARK: - Widget 1: Home Screen 2x2 Sisa Anggaran (PRD §18 P-07)

struct PLABudgetWidgetView: View {
    let entry: PLAWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                content(snap)
            } else {
                emptyState
            }
        }
        .widgetURL(PLAURLRoute.makeTabURL(.finance))
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ snap: PLAWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "wallet.pass.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PLAWidgetFormat.accent)
                Text("Sisa Anggaran")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !snap.hasBudget {
                Spacer(minLength: 2)
                Text("Belum Diatur")
                    .font(.headline)
                Text("Atur anggaran bulanan di Life Assistant.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            } else {
                if snap.maskAmounts {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Rp••••••")
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Text(PLAWidgetFormat.compactRupiah(snap.freeRemaining))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(snap.freeRemaining < 0 ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if !snap.maskAmounts || snap.showBudgetStatusWhenMasked {
                    HStack(spacing: 4) {
                        Image(systemName: PLAWidgetFormat.statusIcon(snap.budgetStatus))
                            .font(.caption2)
                        Text(PLAWidgetFormat.statusLabel(snap.budgetStatus))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(PLAWidgetFormat.statusColor(snap.budgetStatus))
                }

                ProgressView(value: min(max(snap.percentUsed, 0), 1))
                    .tint(PLAWidgetFormat.statusColor(snap.budgetStatus))

                Spacer(minLength: 2)

                HStack {
                    if snap.maskAmounts {
                        Text("Batas aman terkunci")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(PLAWidgetFormat.compactRupiah(snap.safeDailyLimit))/hr")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 2)
                    Text("\(snap.daysRemainingInPeriod)h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "wallet.pass.fill")
                .foregroundStyle(PLAWidgetFormat.accent)
            Text("Life Assistant")
                .font(.caption.weight(.semibold))
            Text("Buka aplikasi untuk menyinkronkan anggaran.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PLABudgetWidget: Widget {
    let kind: String = "PLABudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PLATimelineProvider()) { entry in
            PLABudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Sisa Anggaran")
        .description("Pantau sisa anggaran bebas, batas aman harian, dan status siklus aktif.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Widget 2: Home Screen 4x2 Agenda Hari Ini & Tagihan (PRD §18 P-07)

struct PLAAgendaWidgetView: View {
    let entry: PLAWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                content(snap)
            } else {
                emptyState
            }
        }
        .widgetURL(PLAURLRoute.makeTabURL(.tasks))
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ snap: PLAWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Today's tasks & overdue indicator
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Agenda Hari Ini")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PLAWidgetFormat.accent)
                    if snap.overdueTaskCount > 0 {
                        Text("\(snap.overdueTaskCount) telat")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }

                if snap.todayTasks.isEmpty {
                    Spacer(minLength: 4)
                    Label("Semua tugas beres", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer(minLength: 4)
                } else {
                    ForEach(snap.todayTasks.prefix(3)) { task in
                        HStack(spacing: 5) {
                            Image(systemName: task.isOverdue ? "clock.badge.exclamationmark" : PLAWidgetFormat.priorityIcon(task.priority))
                                .font(.caption2)
                                .foregroundStyle(task.isOverdue ? .red : PLAWidgetFormat.priorityColor(task.priority))
                            Text(task.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if let mins = task.dueTimeMinutes {
                                Text(PLAWidgetFormat.timeString(mins))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right: Upcoming 7-day bills + mini budget health pill
            VStack(alignment: .leading, spacing: 6) {
                Text("Tagihan 7 Hari")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                if snap.upcomingBills.isEmpty {
                    Text("Tidak ada tagihan dekat.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snap.upcomingBills.prefix(2)) { bill in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bill.isTrial ? "Trial: \(bill.name)" : bill.name)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text(bill.isOverdue ? "Terlewat" : PLAWidgetFormat.shortDate(bill.dueDateLocal))
                                .font(.caption2)
                                .foregroundStyle(bill.isOverdue ? .red : .secondary)
                        }
                    }
                }

                Spacer(minLength: 2)

                if snap.hasBudget && (!snap.maskAmounts || snap.showBudgetStatusWhenMasked) {
                    HStack(spacing: 4) {
                        Image(systemName: PLAWidgetFormat.statusIcon(snap.budgetStatus))
                            .font(.caption2)
                        Text(PLAWidgetFormat.statusLabel(snap.budgetStatus))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(PLAWidgetFormat.statusColor(snap.budgetStatus))
                }
            }
            .frame(width: 112, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(PLAWidgetFormat.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Agenda Life Assistant")
                    .font(.headline)
                Text("Buka aplikasi Life Assistant sekali untuk menyinkronkan tugas dan tagihan hari ini.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PLAAgendaWidget: Widget {
    let kind: String = "PLAAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PLATimelineProvider()) { entry in
            PLAAgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Agenda Hari Ini")
        .description("Lihat daftar tugas hari ini, tugas terlambat, dan tagihan 7 hari ke depan.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget 3: Lock Screen Deadline Terdekat (PRD §18 P-07)

struct PLADeadlineLockWidgetView: View {
    let entry: PLAWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            case .accessoryInline:
                inlineBody
            default:
                rectangularBody
            }
        }
        .widgetURL(PLAURLRoute.makeTabURL(.dashboard))
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private var rectangularBody: some View {
        if let deadline = entry.snapshot?.nearestDeadline {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: deadline.isBill ? "creditcard.fill" : "calendar.badge.clock")
                        .font(.caption2)
                    Text(PLAWidgetFormat.countdownText(
                        daysRemaining: deadline.daysRemaining,
                        isOverdue: deadline.isOverdue,
                        dueTimeMinutes: deadline.dueTimeMinutes
                    ))
                    .font(.caption2.weight(.semibold))
                }
                .widgetAccentable()

                Text(deadline.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)

                Text(PLAWidgetFormat.shortDate(deadline.dueDateLocal))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Life Assistant", systemImage: "checkmark.circle")
                    .font(.caption2.weight(.semibold))
                Text("Tidak ada deadline dekat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var circularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let deadline = entry.snapshot?.nearestDeadline {
                VStack(spacing: 1) {
                    Image(systemName: deadline.isBill ? "creditcard" : "checklist")
                        .font(.caption2)
                    Text(deadline.isOverdue ? "!" : (deadline.daysRemaining == 0 ? "H-0" : "H-\(min(deadline.daysRemaining, 99))"))
                        .font(.caption.weight(.bold))
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private var inlineBody: some View {
        if let deadline = entry.snapshot?.nearestDeadline {
            let suffix = PLAWidgetFormat.countdownText(
                daysRemaining: deadline.daysRemaining,
                isOverdue: deadline.isOverdue,
                dueTimeMinutes: deadline.dueTimeMinutes
            )
            Label("\(deadline.title) • \(suffix)", systemImage: deadline.isBill ? "creditcard" : "calendar.badge.clock")
        } else {
            Label("Semua jadwal aman", systemImage: "checkmark.circle")
        }
    }
}

struct PLADeadlineLockWidget: Widget {
    let kind: String = "PLADeadlineLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PLATimelineProvider()) { entry in
            PLADeadlineLockWidgetView(entry: entry)
        }
        .configurationDisplayName("Deadline Terdekat")
        .description("Menampilkan tugas atau tagihan dengan jatuh tempo terdekat di Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - WidgetBundle Entry Point

@main
struct PLAWidgetBundle: WidgetBundle {
    var body: some Widget {
        PLABudgetWidget()
        PLAAgendaWidget()
        PLADeadlineLockWidget()
    }
}
