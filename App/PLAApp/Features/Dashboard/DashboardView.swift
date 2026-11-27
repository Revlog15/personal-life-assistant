import SwiftUI
import PLACore

/// Dashboard (Beranda): White & Blue architectural layout anchored by an obsidian spending trend card,
/// collapsible 7-day task completion rings, 2x2 real-metric grid, and actionable daily sections (PRD AC-01.1..01.4).
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
                LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.lg) {
                    headerBar
                    telemetryHeroSection
                    quickActionStrip
                    alertBannersSection
                    firstRunGuideSection
                    weeklyActivityOverviewCard
                    metricsGridSection
                    overdueTasksSection
                    todayTasksSection
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

    // MARK: - Top Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: PLATokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PLAFormatters.fullDate(store.today))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                Text(PLAFormatters.greeting(for: store.currentDateTime.hour))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
            }

            Spacer(minLength: PLATokens.Spacing.sm)

            PLALiquidGlassIconButton(
                systemImage: store.appearanceMode.iconName,
                accessibilityLabel: "Ganti tema tampilan (\(store.appearanceMode.label))"
            ) {
                store.cycleAppearanceMode()
            }

            Menu {
                Button { onQuickAdd(.task) } label: {
                    Label("Tugas Baru", systemImage: "checklist")
                }
                Button { onQuickAdd(.expense) } label: {
                    Label("Catat Pengeluaran", systemImage: "arrow.up.right.circle")
                }
                Button { onQuickAdd(.income) } label: {
                    Label("Catat Pemasukan", systemImage: "arrow.down.left.circle")
                }
                Button { onQuickAdd(.transfer) } label: {
                    Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle")
                }
                Divider()
                Button { onQuickAdd(.scanReceipt) } label: {
                    Label("Scan Struk (OCR)", systemImage: "doc.text.viewfinder")
                }
                Button { onQuickAdd(.whatIf) } label: {
                    Label("Simulasi Beli (What-If)", systemImage: "slider.horizontal.below.square.filled.and.square")
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

    // MARK: - Focal Point: Dark Obsidian Spending Trend Card

    private var telemetryHeroSection: some View {
        let summary = store.financialSummary
        let points: [PLADailyMetricPoint]
        let subtitle: String
        switch chartRange {
        case .sevenDays:
            points = store.dailyExpenseSeries(days: 7)
            subtitle = "7 hari terakhir, ketuk titik untuk detail"
        case .fourteenDays:
            points = store.dailyExpenseSeries(days: 14)
            subtitle = "14 hari terakhir, ketuk titik untuk detail"
        case .cycle:
            points = store.cycleDailyExpenseSeries()
            subtitle = "Siklus \(PLAFormatters.periodRange(summary.period))"
        }
        let rangeTotal = points.reduce(Int64(0)) { $0 + $1.amount }

        return PLAChartHeroCard(
            title: "Pengeluaran Harian",
            subtitle: subtitle,
            totalAmount: chartRange == .cycle ? summary.totalExpense : rangeTotal,
            points: points,
            selectedRange: $chartRange,
            status: summary.budgetStatus,
            showStatusBadge: !isFinanceMasked || store.settings.showBudgetStatusWhenLocked,
            isMasked: isFinanceMasked,
            onUnlock: {
                _Concurrency.Task {
                    _ = await store.authService.unlockFinance()
                }
            }
        )
    }

    // MARK: - Compact 4-Action Quick Strip

    private var quickActionStrip: some View {
        HStack(spacing: PLATokens.Spacing.sm) {
            quickActionButton(title: "Tugas", icon: "plus.circle.fill") {
                onQuickAdd(.task)
            }
            quickActionButton(title: "Catat", icon: "arrow.up.right.circle.fill") {
                onQuickAdd(.expense)
            }
            quickActionButton(title: "Scan OCR", icon: "doc.text.viewfinder") {
                onQuickAdd(.scanReceipt)
            }
            quickActionButton(title: "Simulasi", icon: "slider.horizontal.3") {
                onQuickAdd(.whatIf)
            }
        }
    }

    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PLATokens.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PLATokens.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collapsible 7-Day Task Ring Card (Reference Overview Anchor)

    private var weeklyActivityOverviewCard: some View {
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
                            withAnimation(.easeInOut(duration: 0.22)) {
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
                                .frame(width: 32, height: 32)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRingsExpanded ? "Tutup progres tugas 7 hari" : "Buka progres tugas 7 hari")

                    if isRingsExpanded {
                        VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
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
                        }
                        .padding(PLATokens.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PLATokens.Colors.elevatedSurface)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2x2 Crisp Metric Grid (Real Local Numbers Only)

    private var metricsGridSection: some View {
        let summary = store.financialSummary
        let activeCount = store.todayTasks.count + store.overdueTasks.count
        let billsTotal = store.upcomingBills7Days.reduce(Int64(0)) { $0 + $1.amount }
        let columns = [
            GridItem(.flexible(), spacing: PLATokens.Spacing.md),
            GridItem(.flexible(), spacing: PLATokens.Spacing.md)
        ]

        return LazyVGrid(columns: columns, spacing: PLATokens.Spacing.md) {
            Button {
                selectedTab = .finance
            } label: {
                PLAMetricTile(
                    title: "Pengeluaran Siklus",
                    value: isFinanceMasked ? PLAFormatters.maskedRupiah() : PLAFormatters.compactRupiah(summary.totalExpense),
                    subtitle: "Hari ke-\(summary.period.currentDay) dari \(summary.period.totalDays)",
                    systemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .finance
            } label: {
                let dailyValue: String = {
                    if isFinanceMasked { return PLAFormatters.maskedRupiah() }
                    if let daily = summary.safeDailyLimit {
                        return PLAFormatters.compactRupiah(daily)
                    }
                    return "Belum diatur"
                }()
                PLAMetricTile(
                    title: "Batas Aman/Hari",
                    value: dailyValue,
                    subtitle: summary.totalBudget == nil ? "Ketuk untuk atur" : PLATokens.label(for: summary.budgetStatus),
                    systemImage: "shield.checkered",
                    valueColor: summary.totalBudget == nil ? PLATokens.Colors.textSecondary : PLATokens.color(for: summary.budgetStatus),
                    iconTint: PLATokens.color(for: summary.budgetStatus)
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .tasks
            } label: {
                PLAMetricTile(
                    title: "Tugas Hari Ini",
                    value: "\(activeCount) tugas",
                    subtitle: store.overdueTasks.isEmpty ? "Tidak ada terlambat" : "\(store.overdueTasks.count) terlambat",
                    systemImage: "checklist",
                    valueColor: store.overdueTasks.isEmpty ? PLATokens.Colors.textPrimary : PLATokens.Colors.danger,
                    iconTint: store.overdueTasks.isEmpty ? PLATokens.Colors.accent : PLATokens.Colors.danger
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .finance
            } label: {
                PLAMetricTile(
                    title: "Tagihan 7 Hari",
                    value: "\(store.upcomingBills7Days.count) tagihan",
                    subtitle: isFinanceMasked
                        ? "Terkunci"
                        : (billsTotal > 0 ? PLAFormatters.compactRupiah(billsTotal) : "Aman, tidak ada tagihan"),
                    systemImage: "calendar.badge.clock"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Alerts & Empty Guide

    @ViewBuilder
    private var alertBannersSection: some View {
        if hasAnyBanner {
            VStack(spacing: PLATokens.Spacing.md) {
                if let dbError = store.databaseErrorMessage {
                    PLACard {
                        AlertBannerRow(
                            icon: "externaldrive.badge.exclamationmark",
                            tint: PLATokens.Colors.danger,
                            title: "Masalah Database",
                            message: dbError
                        )
                    }
                }
                if store.sideloadInfo.shouldShowBanner(on: store.today),
                   let days = store.sideloadInfo.daysRemaining(from: store.today) {
                    PLACard {
                        AlertBannerRow(
                            icon: "clock.badge.exclamationmark.fill",
                            tint: PLATokens.Colors.warning,
                            title: days <= 0 ? "Sertifikat Sideload Kedaluwarsa" : "Masa Berlaku Aplikasi Tinggal \(days) Hari",
                            message: "Buka SideStore bersama LocalDevVPN untuk memperpanjang PLA agar data tetap dapat diakses.",
                            actionTitle: "Lihat Detail",
                            action: { selectedTab = .settings }
                        )
                    }
                }
                if store.notificationAuthStatus == .denied {
                    PLACard {
                        AlertBannerRow(
                            icon: "bell.slash.fill",
                            tint: PLATokens.Colors.warning,
                            title: "Notifikasi Nonaktif",
                            message: "Jadwal pengingat tetap tersimpan, tetapi iOS tidak dapat menampilkannya sampai izin diaktifkan.",
                            actionTitle: "Buka Settings iOS",
                            action: { store.notificationAdapter.openSystemSettings() }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var firstRunGuideSection: some View {
        if store.isCompletelyEmpty {
            PLACard {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                    HStack(spacing: PLATokens.Spacing.md) {
                        PLAIconBadge(systemName: "checklist", color: PLATokens.Colors.accent, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mulai Catatan Pertama")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(PLATokens.Colors.textPrimary)
                            Text("Tambahkan tugas hari ini atau catat pengeluaran agar grafik dan pengingat mulai bekerja.")
                                .font(.footnote)
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: PLATokens.Spacing.sm) {
                            PLAPrimaryPillButton(title: "Buat Tugas Pertama") {
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
                        VStack(spacing: PLATokens.Spacing.sm) {
                            PLAPrimaryPillButton(title: "Buat Tugas Pertama") {
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
    }

    // MARK: - Overdue & Today Tasks

    @ViewBuilder
    private var overdueTasksSection: some View {
        if !store.overdueTasks.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(
                    title: "Terlambat (\(store.overdueTasks.count))",
                    actionTitle: store.overdueTasks.count > 5 ? "Semua" : nil,
                    action: store.overdueTasks.count > 5 ? { selectedTab = .tasks } : nil
                )

                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.overdueTasks.prefix(5)) { task in
                        PLACard(padding: PLATokens.Spacing.md) {
                            dashboardOverdueTaskRow(task)
                        }
                    }
                }
            }
        }
    }

    private var todayTasksSection: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Agenda Hari Ini",
                subtitle: PLAFormatters.shortDate(store.today),
                actionTitle: "Tambah",
                action: { onQuickAdd(.task) }
            )

            if store.todayTasks.isEmpty {
                PLACard(padding: PLATokens.Spacing.md) {
                    HStack(spacing: PLATokens.Spacing.md) {
                        PLAIconBadge(systemName: "checkmark.seal.fill", color: PLATokens.Colors.safe, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidak ada tugas jatuh tempo hari ini")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PLATokens.Colors.textPrimary)
                            Text("Ketuk Tambah jika ada kegiatan yang ingin dijadwalkan.")
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.todayTasks.prefix(6)) { task in
                        PLACard(padding: PLATokens.Spacing.md) {
                            dashboardTodayTaskRow(task)
                        }
                    }
                    if store.todayTasks.count > 6 {
                        Button("Lihat semua \(store.todayTasks.count) tugas hari ini") {
                            selectedTab = .tasks
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.accent)
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                }
            }
        }
    }

    // MARK: - Upcoming 7-Day Bills

    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Tagihan 7 Hari Ke Depan",
                actionTitle: "Keuangan",
                action: { selectedTab = .finance }
            )

            if store.upcomingBills7Days.isEmpty {
                PLACard(padding: PLATokens.Spacing.md) {
                    HStack(spacing: PLATokens.Spacing.md) {
                        PLAIconBadge(systemName: "calendar.badge.checkmark", color: PLATokens.Colors.accent, size: 36)
                        Text("Tidak ada tagihan jatuh tempo dalam 7 hari ke depan.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } else {
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.upcomingBills7Days) { bill in
                        PLACard(padding: PLATokens.Spacing.md) {
                            dashboardBillRow(bill)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insights & Personal Suggestions

    @ViewBuilder
    private var insightsSection: some View {
        if !store.activeInsights.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Insight Keuangan")
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.activeInsights) { insight in
                        PLACard(padding: PLATokens.Spacing.md) {
                            InsightCardView(
                                insight: insight,
                                currentFeedback: store.feedbackForInsight(insight),
                                onFeedback: { useful in store.rateInsight(insight, useful: useful) },
                                onDismiss: { store.dismissInsight(insight) }
                            )
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
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.personalSuggestions) { suggestion in
                        PLACard(padding: PLATokens.Spacing.md) {
                            PersonalSuggestionRow(
                                suggestion: suggestion,
                                onAccept: { store.acceptPersonalSuggestion(suggestion) },
                                onDismiss: { store.dismissPersonalSuggestion(suggestion) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row Builders

    private var hasAnyBanner: Bool {
        store.databaseErrorMessage != nil ||
        store.sideloadInfo.shouldShowBanner(on: store.today) ||
        store.notificationAuthStatus == .denied
    }

    private var isFinanceMasked: Bool {
        store.settings.financeLockEnabled && !store.authService.isFinanceUnlocked
    }

    private func dashboardOverdueTaskRow(_ task: PLATask) -> some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .center, spacing: PLATokens.Spacing.sm) {
                Button {
                    store.completeTask(task)
                } label: {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(PLATokens.color(for: task.priority))
                        .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Selesaikan tugas \(task.title)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    if let due = task.dueDateLocal {
                        Text(PLAFormatters.relativeDayLabel(due, today: store.today))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }
                Spacer(minLength: PLATokens.Spacing.xs)
            }

            HStack {
                Spacer()
                Button {
                    taskToReschedule = task
                } label: {
                    Label("Jadwalkan Ulang", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.accent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(PLATokens.Colors.softBlueTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dashboardTodayTaskRow(_ task: PLATask) -> some View {
        let cat = store.categories.first { $0.id == task.categoryId }

        return HStack(spacing: PLATokens.Spacing.sm) {
            Button {
                store.completeTask(task)
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(PLATokens.color(for: task.priority))
                    .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tandai selesai \(task.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: PLATokens.Spacing.sm) {
                    if let mins = task.dueTimeMinutes {
                        Label(PLAFormatters.time24(mins), systemImage: "clock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.accent)
                    }
                    if let cat {
                        Text(cat.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.softBlueText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(PLATokens.Colors.softBlueTint, in: Capsule())
                    }
                    if task.recurrenceRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .accessibilityLabel("Tugas berulang")
                    }
                }
            }
            Spacer()
            if task.priority == .high {
                StatusBadge(text: "Tinggi", icon: PLATokens.icon(for: TaskPriority.high), color: PLATokens.Colors.danger)
            }
        }
    }

    private func dashboardBillRow(_ bill: Bill) -> some View {
        let overdue = bill.isOverdue(on: store.today)
        let tint = bill.isTrial ? PLATokens.Colors.warning : (overdue ? PLATokens.Colors.danger : PLATokens.Colors.accent)

        return AdaptiveKeyValueRow {
            HStack(spacing: PLATokens.Spacing.md) {
                PLAIconBadge(
                    systemName: bill.isTrial ? "hourglass" : "creditcard.fill",
                    color: tint,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        Text(bill.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                        if bill.isTrial {
                            StatusBadge(text: "Trial", icon: "hourglass", color: PLATokens.Colors.warning)
                        } else if overdue {
                            StatusBadge(text: "Terlewat", icon: "exclamationmark.triangle.fill", color: PLATokens.Colors.danger)
                        }
                    }
                    Text(bill.isTrial
                         ? "Trial berakhir \(PLAFormatters.shortDate(bill.effectiveDueOrTrialEndDate))"
                         : "Jatuh tempo \(PLAFormatters.shortDate(bill.nextDueDateLocal))")
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
    }
}
