import SwiftUI
import PLACore

/// Dashboard (Beranda): Distilled 3-layer White & Blue hierarchy anchored by the obsidian telemetry card,
/// flat collapsible 7-day activity rings (zero nested cards), and grouped borderless daily agenda/bills (PRD AC-01.1..01.4).
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selectedTab: AppTab
    let onQuickAdd: (QuickAddSheetKind) -> Void

    @State private var chartRange: SpendingChartRange = .sevenDays
    @State private var isRingsExpanded: Bool = true
    @State private var taskToReschedule: PLATask?
    @State private var billToPay: Bill?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.section) {
                    headerBar
                    telemetryHeroSection
                    alertBannersSection
                    firstRunGuideSection
                    weeklyActivitySection
                    dailyFocusSection
                    upcomingBillsSection
                    insightsSection
                    personalSuggestionsSection
                }
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.top, PLATokens.Spacing.sm)
                .padding(.bottom, PLATokens.floatingDockClearance)
            }
            .background(PLATokens.Colors.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.diagnostics.markDashboardInteractive()
            }
            .sheet(item: $taskToReschedule) { task in
                RescheduleSheet(task: task)
                    .environment(store)
            }
            .sheet(item: $billToPay) { bill in
                PayBillSheet(bill: bill)
                    .environment(store)
            }
        }
    }

    // MARK: - Header (Single Title + Single Quick-Add Menu)

    private var headerBar: some View {
        PLAScreenHeader("Beranda") {
            Menu {
                Section("Catat Cepat") {
                    Button { onQuickAdd(.task) } label: {
                        Label("Tugas Baru", systemImage: "checklist")
                    }
                    Button { onQuickAdd(.expense) } label: {
                        Label("Pengeluaran", systemImage: "arrow.up.right.circle")
                    }
                    Button { onQuickAdd(.income) } label: {
                        Label("Pemasukan", systemImage: "arrow.down.left.circle")
                    }
                    Button { onQuickAdd(.transfer) } label: {
                        Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle")
                    }
                }
                Section("Alat") {
                    Button { onQuickAdd(.scanReceipt) } label: {
                        Label("Scan Struk (OCR)", systemImage: "doc.text.viewfinder")
                    }
                    Button { onQuickAdd(.whatIf) } label: {
                        Label("Simulasi Beli", systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                    .background(PLATokens.Colors.primaryBlue, in: Circle())
            }
            .accessibilityLabel("Tambah cepat")
        }
    }

    // MARK: - Layer 1: Obsidian Spending Trend Hero (Integrates Safe Daily Limit)

    private var telemetryHeroSection: some View {
        let summary = store.financialSummary
        let points: [PLADailyMetricPoint]
        let subtitle: String
        switch chartRange {
        case .sevenDays:
            points = store.dailyExpenseSeries(days: 7)
            subtitle = "7 hari terakhir, ketuk titik untuk rincian"
        case .fourteenDays:
            points = store.dailyExpenseSeries(days: 14)
            subtitle = "14 hari terakhir, ketuk titik untuk rincian"
        case .cycle:
            points = store.cycleDailyExpenseSeries()
            subtitle = PLAFormatters.periodRange(summary.period)
        }
        let rangeTotal = points.reduce(Int64(0)) { $0 + $1.amount }
        let safeDailyText: String = {
            if let daily = summary.safeDailyLimit {
                return PLAFormatters.rupiah(daily)
            }
            return "Belum diatur"
        }()

        return PLAChartHeroCard(
            title: "Pengeluaran Harian",
            subtitle: subtitle,
            totalAmount: chartRange == .cycle ? summary.recordedExpense : rangeTotal,
            points: points,
            selectedRange: $chartRange,
            status: summary.budgetStatus,
            showStatusBadge: !isFinanceMasked || store.settings.showBudgetStatusWhenLocked,
            footerLeftLabel: "Batas Aman/Hari",
            footerLeftValue: safeDailyText,
            footerRightLabel: "Siklus Aktif",
            footerRightValue: "\(summary.period.remainingDaysInclusive) hari lagi",
            isMasked: isFinanceMasked,
            onUnlock: {
                _Concurrency.Task {
                    _ = await store.authService.unlockFinance()
                }
            }
        )
    }

    // MARK: - Alerts & First-Run Guide

    @ViewBuilder
    private var alertBannersSection: some View {
        if hasAnyBanner {
            PLAGroupList {
                if let dbError = store.databaseErrorMessage {
                    AlertBannerRow(
                        icon: "externaldrive.badge.exclamationmark",
                        tint: PLATokens.Colors.danger,
                        title: "Masalah Database",
                        message: dbError
                    )
                }
                if store.sideloadInfo.shouldShowBanner(on: store.today),
                   let days = store.sideloadInfo.daysRemaining(from: store.today) {
                    if store.databaseErrorMessage != nil { PLAInsetDivider() }
                    AlertBannerRow(
                        icon: "clock.badge.exclamationmark.fill",
                        tint: PLATokens.Colors.warning,
                        title: days <= 0 ? "Sertifikat Sideload Kedaluwarsa" : "Masa Berlaku Tinggal \(days) Hari",
                        message: "Buka SideStore bersama LocalDevVPN untuk memperpanjang aplikasi.",
                        actionTitle: "Lihat Detail",
                        action: { selectedTab = .settings }
                    )
                }
                if store.notificationAuthStatus == .denied {
                    if store.databaseErrorMessage != nil || store.sideloadInfo.shouldShowBanner(on: store.today) {
                        PLAInsetDivider()
                    }
                    AlertBannerRow(
                        icon: "bell.slash.fill",
                        tint: PLATokens.Colors.warning,
                        title: "Notifikasi Nonaktif",
                        message: "Aktifkan izin notifikasi di Settings iOS agar pengingat berbunyi tepat waktu.",
                        actionTitle: "Buka Settings iOS",
                        action: { store.notificationAdapter.openSystemSettings() }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var firstRunGuideSection: some View {
        if store.isCompletelyEmpty {
            PLACard(padding: PLATokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                    Text("Mulai Catatan Pertama")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    Text("Tambahkan tugas hari ini atau catat pengeluaran agar grafik dan pengingat otomatis mulai berjalan.")
                        .font(.subheadline)
                        .foregroundStyle(PLATokens.Colors.textSecondary)

                    HStack(spacing: PLATokens.Spacing.sm) {
                        PLAPrimaryPillButton(title: "Buat Tugas") {
                            onQuickAdd(.task)
                        }
                        Button("Catat Transaksi") {
                            onQuickAdd(.expense)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(PLATokens.Colors.softBlueTint, in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Layer 2: Collapsible 7-Day Activity Rings (Flat, Zero Nested Boxes)

    private var weeklyActivitySection: some View {
        let data = store.last7DaysTaskProgress()
        let totalTasks7d = data.points.reduce(0) { $0 + $1.totalCount }
        let doneTasks7d = data.points.reduce(0) { $0 + $1.completedCount }
        let ratio = totalTasks7d > 0 ? Double(doneTasks7d) / Double(totalTasks7d) : 0

        return VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Ringkasan Aktivitas",
                actionTitle: "Ke Tugas",
                action: { selectedTab = .tasks }
            )

            PLACard(padding: PLATokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                    Button {
                        if reduceMotion {
                            isRingsExpanded.toggle()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRingsExpanded.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "target", color: PLATokens.Colors.accent, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Progres Tugas Harian")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PLATokens.Colors.textPrimary)
                                Text("7 hari terakhir")
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: isRingsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                                .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRingsExpanded ? "Tutup progres tugas 7 hari" : "Buka progres tugas 7 hari")

                    if isRingsExpanded {
                        PLAInsetDivider()

                        PLABreakdownBarRow(
                            title: totalTasks7d > 0 ? "Tercapai" : "Belum ada jadwal 7 hari terakhir",
                            valueText: totalTasks7d > 0 ? "\(doneTasks7d)/\(totalTasks7d)" : "0",
                            progress: ratio,
                            barColor: PLATokens.Colors.primaryBlue
                        )

                        HStack(spacing: 4) {
                            ForEach(data.points) { point in
                                PLAMiniRingDayColumn(point: point)
                            }
                        }
                        .padding(.top, PLATokens.Spacing.xs)
                    }
                }
            }
        }
    }

    // MARK: - Layer 3: Unified Daily Agenda (Overdue + Today in One Calm Grouped Surface)

    private var dailyFocusSection: some View {
        let overdue = Array(store.overdueTasks.prefix(5))
        let todayList = Array(store.todayTasks.prefix(6))
        let combined = overdue + todayList
        let totalActive = store.overdueTasks.count + store.todayTasks.count

        return VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Agenda Hari Ini",
                actionTitle: totalActive > combined.count ? "Semua (\(totalActive))" : "Tambah",
                action: {
                    if totalActive > combined.count {
                        selectedTab = .tasks
                    } else {
                        onQuickAdd(.task)
                    }
                }
            )

            if combined.isEmpty {
                PLACard(padding: PLATokens.Spacing.lg) {
                    HStack(spacing: PLATokens.Spacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(PLATokens.Colors.safe)
                        Text("Tidak ada tugas jatuh tempo hari ini.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } else {
                PLAGroupList {
                    ForEach(Array(combined.enumerated()), id: \.element.id) { idx, task in
                        let isOverdue = task.isOverdue(at: store.currentDateTime)
                        dashboardTaskRow(task, isOverdue: isOverdue)
                        if idx < combined.count - 1 {
                            PLAInsetDivider(leadingInset: 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Upcoming 7-Day Bills (Single Grouped Surface)

    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Tagihan 7 Hari",
                actionTitle: "Keuangan",
                action: { selectedTab = .finance }
            )

            if store.upcomingBills7Days.isEmpty {
                PLACard(padding: PLATokens.Spacing.lg) {
                    HStack(spacing: PLATokens.Spacing.md) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.title3)
                            .foregroundStyle(PLATokens.Colors.accent)
                        Text("Tidak ada tagihan jatuh tempo dalam 7 hari ke depan.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } else {
                PLAGroupList {
                    ForEach(Array(store.upcomingBills7Days.enumerated()), id: \.element.id) { idx, bill in
                        dashboardBillRow(bill)
                        if idx < store.upcomingBills7Days.count - 1 {
                            PLAInsetDivider(leadingInset: 48)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Local Insights & Personal Suggestions (Shown Only When Present)

    @ViewBuilder
    private var insightsSection: some View {
        if !store.activeInsights.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Insight Keuangan")
                PLAGroupList {
                    ForEach(Array(store.activeInsights.enumerated()), id: \.element.id) { idx, insight in
                        InsightCardView(
                            insight: insight,
                            currentFeedback: store.feedbackForInsight(insight),
                            onFeedback: { useful in store.rateInsight(insight, useful: useful) },
                            onDismiss: { store.dismissInsight(insight) }
                        )
                        if idx < store.activeInsights.count - 1 {
                            PLAInsetDivider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var personalSuggestionsSection: some View {
        if !store.personalSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Saran Kebiasaan Lokal")
                PLAGroupList {
                    ForEach(Array(store.personalSuggestions.enumerated()), id: \.element.id) { idx, suggestion in
                        PersonalSuggestionRow(
                            suggestion: suggestion,
                            onAccept: { store.acceptPersonalSuggestion(suggestion) },
                            onDismiss: { store.dismissPersonalSuggestion(suggestion) }
                        )
                        if idx < store.personalSuggestions.count - 1 {
                            PLAInsetDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Clean Flat Row Builders

    private var hasAnyBanner: Bool {
        store.databaseErrorMessage != nil ||
        store.sideloadInfo.shouldShowBanner(on: store.today) ||
        store.notificationAuthStatus == .denied
    }

    private var isFinanceMasked: Bool {
        store.settings.financeLockEnabled && !store.authService.isFinanceUnlocked
    }

    private func dashboardTaskRow(_ task: PLATask, isOverdue: Bool) -> some View {
        HStack(alignment: .center, spacing: PLATokens.Spacing.sm) {
            Button {
                store.completeTask(task)
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(isOverdue ? PLATokens.Colors.danger : PLATokens.color(for: task.priority))
                    .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tandai selesai \(task.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: PLATokens.Spacing.xs) {
                    if isOverdue, let due = task.dueDateLocal {
                        Text(PLAFormatters.relativeDayLabel(due, today: store.today))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.danger)
                    } else if let mins = task.dueTimeMinutes {
                        Text(PLAFormatters.time24(mins))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PLATokens.Colors.accent)
                    }

                    Text(store.categoryName(for: task.categoryId))
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                }
            }

            Spacer(minLength: PLATokens.Spacing.xs)

            if isOverdue {
                Button("Jadwalkan") {
                    taskToReschedule = task
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(PLATokens.Colors.softBlueTint, in: Capsule())
                .buttonStyle(.plain)
            } else if task.priority == .high {
                Image(systemName: PLATokens.icon(for: TaskPriority.high))
                    .font(.subheadline)
                    .foregroundStyle(PLATokens.Colors.danger)
                    .accessibilityLabel("Prioritas tinggi")
            }
        }
        .padding(.vertical, 6)
    }

    private func dashboardBillRow(_ bill: Bill) -> some View {
        let overdue = bill.isOverdue(on: store.today)
        let tint = bill.isTrial ? PLATokens.Colors.warning : (overdue ? PLATokens.Colors.danger : PLATokens.Colors.accent)

        return AdaptiveKeyValueRow {
            HStack(spacing: PLATokens.Spacing.md) {
                PLAIconBadge(
                    systemName: bill.isTrial ? "hourglass" : "creditcard.fill",
                    color: tint,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    Text(bill.isTrial
                         ? "Trial berakhir \(PLAFormatters.shortDate(bill.effectiveDueOrTrialEndDate))"
                         : (overdue ? "Terlewat \(PLAFormatters.shortDate(bill.nextDueDateLocal))" : "Jatuh tempo \(PLAFormatters.shortDate(bill.nextDueDateLocal))"))
                        .font(.caption)
                        .foregroundStyle(overdue ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                }
            }
        } trailing: {
            HStack(spacing: PLATokens.Spacing.sm) {
                MoneyText(amount: bill.amount, masked: isFinanceMasked, style: .subheadline.weight(.bold))
                Button("Lunas") {
                    billToPay = bill
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(PLATokens.Colors.safe, in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, PLATokens.Spacing.sm)
    }
}
