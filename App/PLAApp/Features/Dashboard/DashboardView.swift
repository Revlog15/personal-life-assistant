import SwiftUI
import PLACore

/// Dashboard (Beranda) strictly ordered per PRD AC-01.1..01.4.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectedTab: AppTab
    let onQuickAdd: (QuickAddSheetKind) -> Void

    @State private var taskToReschedule: PLATask?
    @State private var billToPay: Bill?

    var body: some View {
        NavigationStack {
            List {
                // 1. Alert banners (Sideload <= 2 days AC-14.2, Notification denied AC-05.4, DB recovery)
                if hasAnyBanner {
                    Section {
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
                            AlertBannerRow(
                                icon: "clock.badge.exclamationmark.fill",
                                tint: PLATokens.Colors.warning,
                                title: days <= 0 ? "Sertifikat Sideload Kedaluwarsa" : "Masa Berlaku Aplikasi Tinggal \(days) Hari",
                                message: "Buka SideStore bersama LocalDevVPN untuk memperpanjang PLA agar data tetap dapat diakses.",
                                actionTitle: "Lihat Detail",
                                action: { selectedTab = .settings }
                            )
                        }
                        if store.notificationAuthStatus == .denied {
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

                // First-run empty guide (AC-01.3)
                if store.isCompletelyEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                            Label("Selamat datang di Life Assistant", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(PLATokens.Colors.accent)
                            Text("Mulai dengan menambahkan tugas pertama atau mencatat pengeluaran hari ini. Pengingat dan proyeksi akan berjalan otomatis di perangkat Anda.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: PLATokens.Spacing.sm) {
                                    Button("Buat Tugas Pertama") { onQuickAdd(.task) }
                                        .buttonStyle(.borderedProminent)
                                        .frame(minHeight: PLATokens.minTouchTarget)
                                    Button("Catat Transaksi") { onQuickAdd(.expense) }
                                        .buttonStyle(.bordered)
                                        .frame(minHeight: PLATokens.minTouchTarget)
                                }
                                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                                    Button("Buat Tugas Pertama") { onQuickAdd(.task) }
                                        .buttonStyle(.borderedProminent)
                                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                                    Button("Catat Transaksi") { onQuickAdd(.expense) }
                                        .buttonStyle(.bordered)
                                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                                }
                            }
                        }
                        .padding(.vertical, PLATokens.Spacing.xs)
                    }
                }

                // 2. Overdue Tasks (Terlambat) — AC-01.1 & AC-06.1
                if !store.overdueTasks.isEmpty {
                    Section {
                        ForEach(store.overdueTasks.prefix(5)) { task in
                            dashboardOverdueTaskRow(task)
                        }
                        if store.overdueTasks.count > 5 {
                            Button("Lihat semua \(store.overdueTasks.count) tugas terlambat") {
                                selectedTab = .tasks
                            }
                            .font(.footnote.weight(.medium))
                        }
                    } header: {
                        Label("Terlambat (\(store.overdueTasks.count))", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }

                // 3. Today's Tasks (Hari Ini)
                Section {
                    if store.todayTasks.isEmpty {
                        HStack {
                            Text("Tidak ada tugas jatuh tempo hari ini.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Tambah") { onQuickAdd(.task) }
                                .font(.footnote.weight(.semibold))
                                .frame(minHeight: PLATokens.minTouchTarget)
                        }
                    } else {
                        ForEach(store.todayTasks.prefix(6)) { task in
                            dashboardTodayTaskRow(task)
                        }
                        if store.todayTasks.count > 6 {
                            Button("Lihat semua tugas hari ini") {
                                selectedTab = .tasks
                            }
                            .font(.footnote.weight(.medium))
                        }
                    }
                } header: {
                    Text("Hari Ini • \(PLAFormatters.shortDate(store.today))")
                }

                // 4. Bills due in 7 days (Tagihan 7 Hari)
                Section("Tagihan 7 Hari Ke Depan") {
                    if store.upcomingBills7Days.isEmpty {
                        Text("Tidak ada tagihan jatuh tempo dalam 7 hari ke depan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.upcomingBills7Days) { bill in
                            dashboardBillRow(bill)
                        }
                    }
                }

                // 5. Finance Summary Card (masked when Finance is locked — AC-01.2)
                Section("Ringkasan Keuangan") {
                    dashboardFinanceCard
                }

                // 6. Local Insights (max 3 cards — AC-01.1 & AC-11.4)
                if !store.activeInsights.isEmpty {
                    Section("Insight") {
                        ForEach(store.activeInsights) { insight in
                            InsightCardView(
                                insight: insight,
                                currentFeedback: store.feedbackForInsight(insight),
                                onFeedback: { useful in store.rateInsight(insight, useful: useful) },
                                onDismiss: { store.dismissInsight(insight) }
                            )
                        }
                    }
                }

                // 7. Personal Intelligence Suggestions (P-09: R-PER-01 & R-PER-02, opt-in)
                if !store.personalSuggestions.isEmpty {
                    Section("Saran Kebiasaan Lokal") {
                        ForEach(store.personalSuggestions) { suggestion in
                            PersonalSuggestionRow(
                                suggestion: suggestion,
                                onAccept: { store.acceptPersonalSuggestion(suggestion) },
                                onDismiss: { store.dismissPersonalSuggestion(suggestion) }
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Beranda")
            .toolbar {
                // AC-01.4 + P-05: Quick-add `+` Menu
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            onQuickAdd(.task)
                        } label: {
                            Label("Tugas", systemImage: "checklist")
                        }
                        Button {
                            onQuickAdd(.expense)
                        } label: {
                            Label("Pengeluaran", systemImage: "arrow.up.right.circle")
                        }
                        Button {
                            onQuickAdd(.income)
                        } label: {
                            Label("Pemasukan", systemImage: "arrow.down.left.circle")
                        }
                        Button {
                            onQuickAdd(.transfer)
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right.circle")
                        }
                        Divider()
                        Button {
                            onQuickAdd(.scanReceipt)
                        } label: {
                            Label("Scan Struk (OCR)", systemImage: "doc.text.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                    }
                    .accessibilityLabel("Tambah cepat")
                }
            }
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

    private var hasAnyBanner: Bool {
        store.databaseErrorMessage != nil ||
        store.sideloadInfo.shouldShowBanner(on: store.today) ||
        store.notificationAuthStatus == .denied
    }

    private var isFinanceMasked: Bool {
        store.settings.financeLockEnabled && !store.authService.isFinanceUnlocked
    }

    private func dashboardOverdueTaskRow(_ task: PLATask) -> some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
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
                        .font(.body.weight(.medium))
                    if let due = task.dueDateLocal {
                        Text(PLAFormatters.relativeDayLabel(due, today: store.today))
                            .font(.caption)
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
                }
                .buttonStyle(.bordered)
                .tint(PLATokens.Colors.accent)
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }

    private func dashboardTodayTaskRow(_ task: PLATask) -> some View {
        HStack(spacing: PLATokens.Spacing.sm) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                HStack(spacing: PLATokens.Spacing.sm) {
                    if let mins = task.dueTimeMinutes {
                        Label(PLAFormatters.time24(mins), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if task.recurrenceRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        return AdaptiveKeyValueRow {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PLATokens.Spacing.xs) {
                    Text(bill.name)
                        .font(.body.weight(.medium))
                    if bill.isTrial {
                        StatusBadge(
                            text: "Trial",
                            icon: "hourglass",
                            color: PLATokens.Colors.warning
                        )
                    } else if overdue {
                        StatusBadge(
                            text: "Terlewat",
                            icon: "exclamationmark.triangle.fill",
                            color: PLATokens.Colors.danger
                        )
                    }
                }
                Text(bill.isTrial
                     ? "Trial berakhir \(PLAFormatters.shortDate(bill.effectiveDueOrTrialEndDate))"
                     : "Jatuh tempo \(PLAFormatters.shortDate(bill.nextDueDateLocal))")
                    .font(.caption)
                    .foregroundStyle(overdue ? PLATokens.Colors.danger : .secondary)
            }
        } trailing: {
            HStack(spacing: PLATokens.Spacing.sm) {
                MoneyText(amount: bill.amount, masked: isFinanceMasked, style: .subheadline.weight(.semibold))
                Button("Lunas") {
                    billToPay = bill
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }

    @ViewBuilder
    private var dashboardFinanceCard: some View {
        let summary = store.financialSummary
        VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
            AdaptiveKeyValueRow {
                Text("Periode \(PLAFormatters.periodRange(summary.period))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } trailing: {
                if !isFinanceMasked || store.settings.showBudgetStatusWhenLocked {
                    StatusBadge(
                        text: PLATokens.label(for: summary.budgetStatus),
                        icon: PLATokens.icon(for: summary.budgetStatus),
                        color: PLATokens.color(for: summary.budgetStatus)
                    )
                }
            }

            if isFinanceMasked {
                AdaptiveKeyValueRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pengeluaran Periode Ini")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MoneyText(amount: summary.totalExpense, masked: true, style: .title3.weight(.bold))
                    }
                } trailing: {
                    Button {
                        _Concurrency.Task {
                            _ = await store.authService.unlockFinance()
                        }
                    } label: {
                        Label("Buka", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: PLATokens.minTouchTarget)
                }
            } else {
                AdaptiveKeyValueRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pengeluaran")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MoneyText(amount: summary.totalExpense, style: .title3.weight(.bold))
                    }
                } trailing: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Batas Aman/Hari")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let daily = summary.safeDailyLimit {
                            MoneyText(amount: daily, style: .subheadline.weight(.semibold), color: PLATokens.Colors.accent)
                        } else {
                            Text("Belum diatur")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let pct = summary.percentUsed {
                    ProgressView(value: min(pct, 1.0))
                        .tint(PLATokens.color(for: summary.budgetStatus))
                }

                Button("Lihat Detail Keuangan") {
                    selectedTab = .finance
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }
}
