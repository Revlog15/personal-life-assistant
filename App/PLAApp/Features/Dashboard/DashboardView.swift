import SwiftUI
import PLACore

/// Dashboard (Beranda) with committed Emerald-Teal Hero Pulse, 4-domain Quick Action Strip, and ordered PRD AC-01.1..01.4 blocks.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectedTab: AppTab
    let onQuickAdd: (QuickAddSheetKind) -> Void

    @State private var taskToReschedule: PLATask?
    @State private var billToPay: Bill?

    var body: some View {
        NavigationStack {
            List {
                // 0. Daily Pulse Hero Banner (Emerald-Teal brand identity + Finance quick overview)
                Section {
                    dailyPulseHero
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // 0b. 4-Domain Quick Action Strip (1-tap vibrant actions)
                Section {
                    quickActionStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }

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
                            HStack(spacing: PLATokens.Spacing.md) {
                                PLAIconBadge(systemName: "sparkles", color: PLATokens.Colors.accent, size: 42, iconFont: .title3.weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mulai Hari Lebih Teratur")
                                        .font(.headline)
                                    Text("Tambahkan tugas pertama atau catat pengeluaran hari ini.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: PLATokens.Spacing.sm) {
                                    Button("Buat Tugas Pertama") { onQuickAdd(.task) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(PLATokens.Colors.indigo)
                                        .frame(minHeight: PLATokens.minTouchTarget)
                                    Button("Catat Transaksi") { onQuickAdd(.expense) }
                                        .buttonStyle(.bordered)
                                        .tint(PLATokens.Colors.coral)
                                        .frame(minHeight: PLATokens.minTouchTarget)
                                }
                                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                                    Button("Buat Tugas Pertama") { onQuickAdd(.task) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(PLATokens.Colors.indigo)
                                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                                    Button("Catat Transaksi") { onQuickAdd(.expense) }
                                        .buttonStyle(.bordered)
                                        .tint(PLATokens.Colors.coral)
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
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.danger)
                        }
                    } header: {
                        Label("Terlambat (\(store.overdueTasks.count))", systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }

                // 3. Today's Tasks (Hari Ini)
                Section {
                    if store.todayTasks.isEmpty {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "checkmark.seal.fill", color: PLATokens.Colors.safe, size: 36)
                            Text("Tidak ada tugas jatuh tempo hari ini.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Tambah") { onQuickAdd(.task) }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PLATokens.Colors.indigo)
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
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.indigo)
                        }
                    }
                } header: {
                    Label("Hari Ini • \(PLAFormatters.shortDate(store.today))", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.indigo)
                }

                // 4. Bills due in 7 days (Tagihan 7 Hari)
                Section {
                    if store.upcomingBills7Days.isEmpty {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "calendar.badge.checkmark", color: PLATokens.Colors.rose, size: 36)
                            Text("Tidak ada tagihan jatuh tempo 7 hari ke depan.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(store.upcomingBills7Days) { bill in
                            dashboardBillRow(bill)
                        }
                    }
                } header: {
                    Label("Tagihan 7 Hari Ke Depan", systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.rose)
                }

                // 5. Local Insights (max 3 cards — AC-01.1 & AC-11.4)
                if !store.activeInsights.isEmpty {
                    Section {
                        ForEach(store.activeInsights) { insight in
                            InsightCardView(
                                insight: insight,
                                currentFeedback: store.feedbackForInsight(insight),
                                onFeedback: { useful in store.rateInsight(insight, useful: useful) },
                                onDismiss: { store.dismissInsight(insight) }
                            )
                        }
                    } header: {
                        Label("Insight Keuangan", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.amberHeader)
                    }
                }

                // 6. Personal Intelligence Suggestions (P-09: R-PER-01 & R-PER-02, opt-in)
                if !store.personalSuggestions.isEmpty {
                    Section {
                        ForEach(store.personalSuggestions) { suggestion in
                            PersonalSuggestionRow(
                                suggestion: suggestion,
                                onAccept: { store.acceptPersonalSuggestion(suggestion) },
                                onDismiss: { store.dismissPersonalSuggestion(suggestion) }
                            )
                        }
                    } header: {
                        Label("Saran Kebiasaan Lokal", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.violet)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PLATokens.Colors.canvas)
            .navigationTitle("Beranda")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { onQuickAdd(.task) } label: {
                            Label("Tugas", systemImage: "checklist")
                        }
                        Button { onQuickAdd(.expense) } label: {
                            Label("Pengeluaran", systemImage: "arrow.up.right.circle")
                        }
                        Button { onQuickAdd(.income) } label: {
                            Label("Pemasukan", systemImage: "arrow.down.left.circle")
                        }
                        Button { onQuickAdd(.transfer) } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right.circle")
                        }
                        Divider()
                        Button { onQuickAdd(.scanReceipt) } label: {
                            Label("Scan Struk (OCR)", systemImage: "doc.text.viewfinder")
                        }
                        Button { onQuickAdd(.whatIf) } label: {
                            Label("Simulasi Beli (What-If)", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(PLATokens.Colors.accent)
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

    // MARK: - Daily Pulse Hero Card

    private var dailyPulseHero: some View {
        let summary = store.financialSummary
        let greeting = PLAFormatters.greeting(for: store.currentDateTime.hour)

        return PLAHeroCard(gradient: PLATokens.heroGradient) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(greeting)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.white)
                        Text(PLAFormatters.fullDate(store.today))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.84))
                    }
                    Spacer()
                    if !isFinanceMasked || store.settings.showBudgetStatusWhenLocked {
                        StatusBadge(
                            text: PLATokens.label(for: summary.budgetStatus),
                            icon: PLATokens.icon(for: summary.budgetStatus),
                            color: PLATokens.color(for: summary.budgetStatus),
                            onDarkSurface: true
                        )
                    }
                }

                // Today's quick pulse pills
                HStack(spacing: PLATokens.Spacing.sm) {
                    heroStatPill(
                        icon: "checklist",
                        text: "\(store.todayTasks.count + store.overdueTasks.count) Tugas"
                    )
                    heroStatPill(
                        icon: "creditcard.fill",
                        text: "\(store.upcomingBills7Days.count) Tagihan"
                    )
                    Spacer()
                }

                Divider().overlay(Color.white.opacity(0.22))

                // Finance summary inside hero (masked with Face ID CTA when locked — AC-01.2)
                if isFinanceMasked {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pengeluaran Periode Ini")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.80))
                            Text(PLAFormatters.maskedRupiah())
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                        }
                        Spacer()
                        Button {
                            _Concurrency.Task {
                                _ = await store.authService.unlockFinance()
                            }
                        } label: {
                            Label("Buka", systemImage: "faceid")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PLATokens.Colors.heroStart)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                        AdaptiveKeyValueRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pengeluaran Periode")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.white.opacity(0.80))
                                MoneyText(
                                    amount: summary.totalExpense,
                                    style: .title2.weight(.bold),
                                    color: Color.white
                                )
                            }
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Batas Aman/Hari")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.white.opacity(0.80))
                                if let daily = summary.safeDailyLimit {
                                    MoneyText(
                                        amount: daily,
                                        style: .headline.weight(.bold),
                                        color: Color.white
                                    )
                                } else {
                                    Text("Belum diatur")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.white.opacity(0.88))
                                }
                            }
                        }

                        if let pct = summary.percentUsed {
                            ProgressView(value: min(pct, 1.0))
                                .tint(Color.white)
                                .background(Color.white.opacity(0.24), in: Capsule())
                        }

                        Button {
                            selectedTab = .finance
                        } label: {
                            HStack(spacing: 4) {
                                Text("Detail Keuangan")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(Color.white.opacity(0.92))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func heroStatPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18), in: Capsule())
    }

    // MARK: - 4-Domain Quick Action Strip

    private var quickActionStrip: some View {
        HStack(spacing: PLATokens.Spacing.sm) {
            PLAQuickActionPill(
                title: "Tugas",
                systemImage: "checklist",
                color: PLATokens.Colors.indigo
            ) { onQuickAdd(.task) }

            PLAQuickActionPill(
                title: "Catat",
                systemImage: "arrow.up.right.circle.fill",
                color: PLATokens.Colors.coral
            ) { onQuickAdd(.expense) }

            PLAQuickActionPill(
                title: "Scan OCR",
                systemImage: "doc.text.viewfinder",
                color: PLATokens.Colors.accent
            ) { onQuickAdd(.scanReceipt) }

            PLAQuickActionPill(
                title: "Simulasi",
                systemImage: "wand.and.stars",
                color: PLATokens.Colors.violet
            ) { onQuickAdd(.whatIf) }
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
                        .font(.body.weight(.semibold))
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let due = task.dueDateLocal {
                        Text(PLAFormatters.relativeDayLabel(due, today: store.today))
                            .font(.caption.weight(.medium))
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
                .buttonStyle(.borderedProminent)
                .tint(PLATokens.Colors.indigo)
                .controlSize(.small)
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }

    private func dashboardTodayTaskRow(_ task: PLATask) -> some View {
        let cat = store.categories.first { $0.id == task.categoryId }
        let catColor = cat.map { PLATokens.color(forToken: $0.colorToken) } ?? PLATokens.Colors.indigo

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
                    .font(.body.weight(.medium))
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: PLATokens.Spacing.sm) {
                    if let mins = task.dueTimeMinutes {
                        Label(PLAFormatters.time24(mins), systemImage: "clock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PLATokens.Colors.info)
                    }
                    if let cat {
                        Text(cat.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(catColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(catColor.opacity(0.14), in: Capsule())
                    }
                    if task.recurrenceRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.accent)
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
        let tint = bill.isTrial ? PLATokens.Colors.warning : (overdue ? PLATokens.Colors.danger : PLATokens.Colors.rose)

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
                            .font(.body.weight(.semibold))
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
                        .foregroundStyle(overdue ? PLATokens.Colors.danger : .secondary)
                }
            }
        } trailing: {
            HStack(spacing: PLATokens.Spacing.sm) {
                MoneyText(amount: bill.amount, masked: isFinanceMasked, style: .subheadline.weight(.bold))
                Button("Lunas") {
                    billToPay = bill
                }
                .buttonStyle(.borderedProminent)
                .tint(PLATokens.Colors.safe)
                .controlSize(.small)
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }
}

private extension PLATokens.Colors {
    static var amberHeader: Color { warning }
}
