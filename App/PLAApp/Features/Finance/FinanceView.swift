import SwiftUI
import PLACore

enum FinanceSegment: Int, CaseIterable, Identifiable {
    case summary = 0
    case transactions = 1
    case bills = 2
    case accounts = 3
    case budgets = 4
    case savings = 5

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .summary: return "Ringkasan"
        case .transactions: return "Transaksi"
        case .bills: return "Tagihan"
        case .accounts: return "Akun"
        case .budgets: return "Anggaran"
        case .savings: return "Tabungan"
        }
    }
}

/// Finance tab (PRD §7.2, F-07..F-11, P-03, P-04): White & Blue ScrollView architecture with obsidian chart hero,
/// 2x2 real-metric grid, horizontal category/budget/savings breakdown bars, and full offline management.
struct FinanceView: View {
    @Environment(AppStore.self) private var store

    @State private var segment: FinanceSegment = .summary
    @State private var chartRange: SpendingChartRange = .cycle

    // Transaction filters (AC-08.4)
    @State private var txTypeFilter: TransactionType? = nil
    @State private var txAccountFilter: UUID? = nil
    @State private var txCategoryFilter: UUID? = nil
    @State private var txSearchText: String = ""
    @State private var txVisibleLimit: Int = 50

    // Sheets
    @State private var showAddExpense = false
    @State private var showAddIncome = false
    @State private var showTransfer = false
    @State private var editingTransaction: PLATransaction?
    @State private var showAddBill = false
    @State private var editingBill: Bill?
    @State private var billToPay: Bill?
    @State private var billToSkip: Bill?
    @State private var showAddAccount = false
    @State private var editingAccount: Account?
    @State private var showTotalBudgetSheet = false
    @State private var categoryForBudget: PLACategory?
    @State private var showArchivedAccounts = false
    @State private var showWhatIfSheet = false
    @State private var showOCRScanSheet = false
    @State private var showAddSavingsGoal = false
    @State private var editingSavingsGoal: SavingsGoal?
    @State private var allocateSavingsTarget: SavingsAllocateRequest?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, PLATokens.Spacing.lg)
                    .padding(.top, PLATokens.Spacing.sm)
                    .padding(.bottom, PLATokens.Spacing.sm)

                segmentBar
                    .padding(.bottom, PLATokens.Spacing.sm)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.lg) {
                        switch segment {
                        case .summary:
                            summaryContent
                        case .transactions:
                            transactionsContent
                        case .bills:
                            billsContent
                        case .accounts:
                            accountsContent
                        case .budgets:
                            budgetsContent
                        case .savings:
                            savingsContent
                        }
                    }
                    .padding(.horizontal, PLATokens.Spacing.lg)
                    .padding(.top, PLATokens.Spacing.xs)
                    .padding(.bottom, PLATokens.floatingDockClearance)
                }
            }
            .background(PLATokens.Colors.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddExpense) {
                TransactionFormSheet(initialType: .expense).environment(store)
            }
            .sheet(isPresented: $showAddIncome) {
                TransactionFormSheet(initialType: .income).environment(store)
            }
            .sheet(item: $editingTransaction) { tx in
                TransactionFormSheet(initialType: tx.type, editingTransaction: tx).environment(store)
            }
            .sheet(isPresented: $showTransfer) {
                TransferFormSheet().environment(store)
            }
            .sheet(isPresented: $showAddBill) {
                BillFormSheet().environment(store)
            }
            .sheet(item: $editingBill) { bill in
                BillFormSheet(editingBill: bill).environment(store)
            }
            .sheet(item: $billToPay) { bill in
                PayBillSheet(bill: bill).environment(store)
            }
            .sheet(isPresented: $showAddAccount) {
                AccountFormSheet().environment(store)
            }
            .sheet(item: $editingAccount) { acc in
                AccountFormSheet(editingAccount: acc).environment(store)
            }
            .sheet(isPresented: $showTotalBudgetSheet) {
                BudgetFormSheet(category: nil, currentAmount: store.financialSummary.totalBudget).environment(store)
            }
            .sheet(item: $categoryForBudget) { cat in
                let existing = store.financialSummary.categorySummaries.first { $0.id == cat.id }?.budgetAmount
                BudgetFormSheet(category: cat, currentAmount: existing).environment(store)
            }
            .sheet(isPresented: $showWhatIfSheet) {
                WhatIfSimulatorSheet().environment(store)
            }
            .sheet(isPresented: $showOCRScanSheet) {
                ReceiptOCRReviewSheet().environment(store)
            }
            .sheet(isPresented: $showAddSavingsGoal) {
                SavingsGoalFormSheet().environment(store)
            }
            .sheet(item: $editingSavingsGoal) { goal in
                SavingsGoalFormSheet(editingGoal: goal).environment(store)
            }
            .sheet(item: $allocateSavingsTarget) { req in
                SavingsAllocateSheet(goal: req.goal, isWithdraw: req.isWithdraw).environment(store)
            }
            .confirmationDialog(
                "Lewati Siklus Tagihan?",
                isPresented: Binding(
                    get: { billToSkip != nil },
                    set: { if !$0 { billToSkip = nil } }
                ),
                presenting: billToSkip
            ) { bill in
                Button("Lewati Siklus Ini") {
                    store.skipBillCycle(bill)
                    billToSkip = nil
                }
                Button("Batal", role: .cancel) {
                    billToSkip = nil
                }
            } message: { bill in
                Text("Tidak ada transaksi pengeluaran yang dibuat. Jatuh tempo \"\(bill.name)\" akan dimajukan ke siklus berikutnya.")
            }
        }
    }

    // MARK: - Top Header & Segment Switcher

    private var headerBar: some View {
        HStack(spacing: PLATokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PLAFormatters.periodRange(store.activePeriod))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                Text("Keuangan")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
            }

            Spacer()

            if store.settings.financeLockEnabled {
                PLALiquidGlassIconButton(
                    systemImage: "lock.fill",
                    accessibilityLabel: "Kunci halaman Keuangan"
                ) {
                    store.authService.lockImmediately()
                }
            }

            Menu {
                Button { showAddExpense = true } label: {
                    Label("Catat Pengeluaran", systemImage: "arrow.up.right.circle")
                }
                Button { showAddIncome = true } label: {
                    Label("Catat Pemasukan", systemImage: "arrow.down.left.circle")
                }
                Button { showTransfer = true } label: {
                    Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle")
                }
                Button { showOCRScanSheet = true } label: {
                    Label("Scan Struk / Transfer (OCR)", systemImage: "doc.text.viewfinder")
                }
                Divider()
                Button { showWhatIfSheet = true } label: {
                    Label("Simulasi Beli (What-If)", systemImage: "slider.horizontal.below.square.filled.and.square")
                }
                Button { showAddSavingsGoal = true } label: {
                    Label("Tambah Target Tabungan", systemImage: "target")
                }
                Button { showAddBill = true } label: {
                    Label("Tambah Tagihan / Trial", systemImage: "calendar.badge.exclamationmark")
                }
                Button { showAddAccount = true } label: {
                    Label("Tambah Akun/Dompet", systemImage: "creditcard")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                    .background(PLATokens.Colors.primaryBlue, in: Circle())
            }
            .accessibilityLabel("Tambah catatan keuangan")
        }
    }

    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PLATokens.Spacing.sm) {
                ForEach(FinanceSegment.allCases) { item in
                    let active = segment == item
                    Button(item.title) {
                        segment = item
                    }
                    .font(.subheadline.weight(active ? .bold : .medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(
                        Capsule()
                            .fill(active ? PLATokens.Colors.primaryBlue : PLATokens.Colors.surface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(active ? Color.clear : PLATokens.Colors.border, lineWidth: 1)
                    )
                    .foregroundStyle(active ? Color.white : PLATokens.Colors.textPrimary)
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.horizontal, PLATokens.Spacing.lg)
        }
    }

    // MARK: - 1. Ringkasan (F-11)

    @ViewBuilder
    private var summaryContent: some View {
        let s = store.financialSummary
        let points: [PLADailyMetricPoint] = {
            switch chartRange {
            case .sevenDays: return store.dailyExpenseSeries(days: 7)
            case .fourteenDays: return store.dailyExpenseSeries(days: 14)
            case .cycle: return store.cycleDailyExpenseSeries()
            }
        }()
        let rangeTotal = points.reduce(Int64(0)) { $0 + $1.amount }

        // 1a. Obsidian Telemetry Chart Hero
        PLAChartHeroCard(
            title: "Tren Pengeluaran",
            subtitle: "Hari ke-\(s.period.currentDay) dari \(s.period.totalDays), ketuk titik untuk rincian",
            totalAmount: chartRange == .cycle ? s.totalExpense : rangeTotal,
            points: points,
            selectedRange: $chartRange,
            status: s.budgetStatus
        )

        // 1b. Cash Flow Strip Card
        PLACard(padding: PLATokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                AdaptiveKeyValueRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arus Kas Bersih")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                        MoneyText(
                            amount: s.netCashFlow,
                            style: .title3.weight(.bold),
                            color: s.netCashFlow < 0 ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                        )
                    }
                } trailing: {
                    StatusBadge(
                        text: PLATokens.label(for: s.budgetStatus),
                        icon: PLATokens.icon(for: s.budgetStatus),
                        color: PLATokens.color(for: s.budgetStatus)
                    )
                }

                Divider()

                HStack(spacing: PLATokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Pemasukan", systemImage: "arrow.down.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.safe)
                        MoneyText(amount: s.totalIncome, style: .subheadline.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("Pengeluaran", systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.danger)
                        MoneyText(amount: s.totalExpense, style: .subheadline.weight(.bold))
                    }
                }
            }
        }

        // 1c. Quick Tools Row: Scan OCR + Simulasi Beli
        HStack(spacing: PLATokens.Spacing.sm) {
            Button {
                showOCRScanSheet = true
            } label: {
                PLACard(padding: PLATokens.Spacing.md, cornerRadius: 16) {
                    HStack(spacing: PLATokens.Spacing.sm) {
                        PLAIconBadge(systemName: "doc.text.viewfinder", color: PLATokens.Colors.accent, size: 34)
                        Text("Scan Struk OCR")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                showWhatIfSheet = true
            } label: {
                PLACard(padding: PLATokens.Spacing.md, cornerRadius: 16) {
                    HStack(spacing: PLATokens.Spacing.sm) {
                        PLAIconBadge(systemName: "slider.horizontal.3", color: PLATokens.Colors.accent, size: 34)
                        Text("Simulasi Beli")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        // 1d. Budget & Forecast 2x2 Metrics + Progress Card
        summaryBudgetAndForecastBlock(s)

        // 1e. Top 3 Expense Categories (Macro-Style Horizontal Breakdown Bars)
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(title: "Top 3 Kategori Pengeluaran")
            PLACard(padding: PLATokens.Spacing.lg) {
                if s.expenseTransactionCount < 3 {
                    Text("Catat minimal 3 pengeluaran untuk melihat kategori terbesar.")
                        .font(.subheadline)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                } else if s.topExpenseCategories.isEmpty {
                    Text("Belum ada pengeluaran pada periode ini.")
                        .font(.subheadline)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                } else {
                    VStack(spacing: PLATokens.Spacing.md) {
                        ForEach(s.topExpenseCategories) { cat in
                            let pctInt = Int((cat.percentageOfVariable * 100).rounded())
                            PLABreakdownBarRow(
                                title: cat.categoryName,
                                valueText: PLAFormatters.rupiah(cat.totalSpent),
                                subtitle: "\(pctInt)% dari pengeluaran variabel",
                                progress: cat.percentageOfVariable,
                                barColor: PLATokens.Colors.primaryBlue
                            )
                        }
                    }
                }
            }
        }

        // 1f. Local Financial Insights
        if !store.activeInsights.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Peringatan & Saran Lokal")
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
    private func summaryBudgetAndForecastBlock(_ s: FinancialPeriodSummary) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: PLATokens.Spacing.md),
            GridItem(.flexible(), spacing: PLATokens.Spacing.md)
        ]

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Anggaran & Proyeksi",
                actionTitle: s.totalBudget == nil ? "Atur" : "Ubah",
                action: { showTotalBudgetSheet = true }
            )

            if let totalBudget = s.totalBudget, let pct = s.percentUsed {
                PLACard(padding: PLATokens.Spacing.lg) {
                    PLABreakdownBarRow(
                        title: "Anggaran Bulanan (\(Int((pct * 100).rounded()))%)",
                        valueText: PLAFormatters.rupiah(s.totalExpense),
                        subtitle: "Batas \(PLAFormatters.rupiah(totalBudget))",
                        progress: pct,
                        barColor: PLATokens.color(for: s.budgetStatus)
                    )
                }

                LazyVGrid(columns: columns, spacing: PLATokens.Spacing.md) {
                    PLAMetricTile(
                        title: "Sisa Anggaran",
                        value: PLAFormatters.compactRupiah(s.remainingBudget ?? 0),
                        subtitle: s.unpaidBillsDue > 0 ? "Bebas: \(PLAFormatters.compactRupiah(s.freeRemainingBudget ?? 0))" : "Periode aktif",
                        systemImage: "banknote",
                        valueColor: (s.remainingBudget ?? 0) < 0 ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                    )

                    PLAMetricTile(
                        title: "Batas Aman/Hari",
                        value: PLAFormatters.compactRupiah(s.safeDailyLimit ?? 0),
                        subtitle: "\(s.period.remainingDaysInclusive) hari tersisa",
                        systemImage: "shield.checkered",
                        valueColor: PLATokens.Colors.accent
                    )

                    PLAMetricTile(
                        title: "Proyeksi Akhir",
                        value: s.isForecastReady ? PLAFormatters.compactRupiah(s.forecastTotal) : "Menunggu data",
                        subtitle: s.isForecastReady
                            ? "Rata-rata \(PLAFormatters.compactRupiah(Int64(s.averageDailyVariableExpense.rounded())))/hr"
                            : "Butuh 5 hari & 5 trx",
                        systemImage: "chart.line.uptrend.xyaxis",
                        valueColor: (s.isForecastReady && s.forecastTotal > totalBudget) ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                    )

                    PLAMetricTile(
                        title: "Cadangan Tagihan",
                        value: PLAFormatters.compactRupiah(s.unpaidBillsDue),
                        subtitle: s.unpaidBillsDue > 0 ? "Belum lunas siklus ini" : "Semua tagihan lunas",
                        systemImage: "calendar.badge.clock",
                        valueColor: s.unpaidBillsDue > 0 ? PLATokens.Colors.warning : PLATokens.Colors.safe,
                        iconTint: s.unpaidBillsDue > 0 ? PLATokens.Colors.warning : PLATokens.Colors.safe
                    )
                }
            } else {
                PLACard(padding: PLATokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                        Text("Anggaran bulanan belum diatur. Tetapkan batas total untuk melihat sisa harian aman dan proyeksi akhir periode.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                        PLAPrimaryPillButton(title: "Atur Anggaran Bulanan") {
                            showTotalBudgetSheet = true
                        }
                    }
                }
            }

            if !s.isForecastReady {
                PLACard(padding: PLATokens.Spacing.md) {
                    Label(
                        "Butuh minimal 5 hari dan 5 transaksi pengeluaran untuk proyeksi bulanan (saat ini: hari ke-\(s.period.currentDay), \(s.expenseTransactionCount) transaksi).",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - 2. Transaksi (F-08, AC-08.4)

    private var filteredTransactions: [PLATransaction] {
        let query = txSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.transactions.filter { tx in
            if let t = txTypeFilter, tx.type != t { return false }
            if let acc = txAccountFilter, tx.accountId != acc && tx.destinationAccountId != acc { return false }
            if let cat = txCategoryFilter, tx.categoryId != cat { return false }
            if !query.isEmpty {
                let noteMatch = tx.note?.lowercased().contains(query) ?? false
                let catMatch = store.categoryName(for: tx.categoryId).lowercased().contains(query)
                let accMatch = store.accountName(for: tx.accountId).lowercased().contains(query)
                if !noteMatch && !catMatch && !accMatch { return false }
            }
            return true
        }
    }

    private var filteredSubtotal: Int64 {
        filteredTransactions.reduce(Int64(0)) { acc, tx in
            switch tx.type {
            case .income: return acc + tx.amount
            case .expense: return acc - tx.amount
            case .transfer: return acc
            }
        }
    }

    @ViewBuilder
    private var transactionsContent: some View {
        let matched = filteredTransactions
        let visible = Array(matched.prefix(txVisibleLimit))

        PLACard(padding: PLATokens.Spacing.md) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                    TextField("Cari catatan, kategori, atau akun...", text: $txSearchText)
                        .font(.subheadline)
                    if !txSearchText.isEmpty {
                        Button {
                            txSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bersihkan pencarian")
                    }
                }
                .padding(.horizontal, PLATokens.Spacing.md)
                .frame(minHeight: 42)
                .background(PLATokens.Colors.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PLATokens.Colors.border, lineWidth: 1)
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        filterChip("Semua", active: txTypeFilter == nil) { txTypeFilter = nil }
                        filterChip("Pengeluaran", active: txTypeFilter == .expense) { txTypeFilter = .expense }
                        filterChip("Pemasukan", active: txTypeFilter == .income) { txTypeFilter = .income }
                        filterChip("Transfer", active: txTypeFilter == .transfer) { txTypeFilter = .transfer }
                    }
                }

                HStack(spacing: PLATokens.Spacing.sm) {
                    Menu {
                        Button("Semua Akun") { txAccountFilter = nil }
                        ForEach(store.accounts) { acc in
                            Button(acc.name) { txAccountFilter = acc.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(txAccountFilter.map { store.accountName(for: $0) } ?? "Semua Akun")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(PLATokens.Colors.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Menu {
                        Button("Semua Kategori") { txCategoryFilter = nil }
                        ForEach(store.categories.filter { $0.scope != .task }) { cat in
                            Button(cat.name) { txCategoryFilter = cat.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(txCategoryFilter.map { store.categoryName(for: $0) } ?? "Semua Kategori")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(PLATokens.Colors.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Divider()

                AdaptiveKeyValueRow {
                    Text("\(matched.count) transaksi cocok")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                } trailing: {
                    MoneyText(
                        amount: filteredSubtotal,
                        style: .footnote.weight(.bold),
                        color: filteredSubtotal >= 0 ? PLATokens.Colors.safe : PLATokens.Colors.danger
                    )
                }
            }
        }

        if visible.isEmpty {
            PLAEmptyStateView(
                title: "Tidak Ada Transaksi",
                message: "Catat pemasukan atau pengeluaran baru untuk mulai memantau arus kas.",
                systemImage: "tray",
                actionTitle: "Catat Pengeluaran",
                action: { showAddExpense = true }
            )
        } else {
            VStack(spacing: PLATokens.Spacing.sm) {
                ForEach(visible) { tx in
                    transactionCard(tx)
                }
                if matched.count > txVisibleLimit {
                    Button("Muat Lebih Banyak (\(matched.count - txVisibleLimit) tersisa)") {
                        txVisibleLimit += 50
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                }
            }
        }
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                Capsule()
                    .fill(active ? PLATokens.Colors.primaryBlue : PLATokens.Colors.elevatedSurface)
            )
            .foregroundStyle(active ? Color.white : PLATokens.Colors.textPrimary)
            .buttonStyle(.plain)
    }

    private func transactionCard(_ tx: PLATransaction) -> some View {
        let isFuture = tx.dateLocal > store.today
        let cat = store.categories.first { $0.id == tx.categoryId }
        let badgeColor: Color = tx.type == .income ? PLATokens.Colors.safe : (tx.type == .expense ? PLATokens.Colors.danger : PLATokens.Colors.accent)
        let badgeIcon: String = tx.type == .transfer
            ? "arrow.left.arrow.right"
            : (cat?.iconName ?? (tx.type == .income ? "arrow.down.left" : "tag.fill"))

        return PLACard(padding: PLATokens.Spacing.md, cornerRadius: 18) {
            HStack(alignment: .center, spacing: PLATokens.Spacing.md) {
                Button {
                    if tx.type != .transfer {
                        editingTransaction = tx
                    }
                } label: {
                    AdaptiveKeyValueRow {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: badgeIcon, color: badgeColor, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: PLATokens.Spacing.xs) {
                                    Text(tx.type == .transfer
                                         ? "Transfer: \(store.accountName(for: tx.accountId)) -> \(store.accountName(for: tx.destinationAccountId))"
                                         : store.categoryName(for: tx.categoryId))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PLATokens.Colors.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    if isFuture {
                                        StatusBadge(text: "Mendatang", icon: "clock", color: PLATokens.Colors.accent)
                                    }
                                }

                                HStack(spacing: PLATokens.Spacing.xs) {
                                    Text(PLAFormatters.shortDate(tx.dateLocal))
                                        .font(.caption)
                                        .foregroundStyle(PLATokens.Colors.textSecondary)
                                    if tx.type != .transfer {
                                        Text("• \(store.accountName(for: tx.accountId))")
                                            .font(.caption)
                                            .foregroundStyle(PLATokens.Colors.textSecondary)
                                    }
                                    if tx.billId != nil {
                                        Label("Tagihan", systemImage: "checkmark.seal.fill")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(PLATokens.Colors.accent)
                                    }
                                }

                                if let note = tx.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(PLATokens.Colors.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    } trailing: {
                        let prefix = tx.type == .income ? "+" : (tx.type == .expense ? "-" : "")
                        Text("\(prefix)\(PLAFormatters.rupiah(tx.amount))")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(badgeColor)
                    }
                }
                .buttonStyle(.plain)

                Menu {
                    if tx.type != .transfer {
                        Button {
                            editingTransaction = tx
                        } label: {
                            Label("Sunting", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) {
                        store.deleteTransaction(id: tx.id)
                    } label: {
                        Label("Hapus", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel("Opsi transaksi")
            }
        }
    }

    // MARK: - 3. Tagihan (F-10)

    @ViewBuilder
    private var billsContent: some View {
        let overdue = store.activeBills.filter { $0.isOverdue(on: store.today) }
        let upcoming = store.activeBills.filter { !$0.isOverdue(on: store.today) }

        if store.activeBills.isEmpty {
            PLAEmptyStateView(
                title: "Belum Ada Tagihan",
                message: "Catat tagihan kos, listrik, internet, atau langganan rutin agar pengingat jatuh tempo dan pencatatan lunas otomatis berjalan.",
                systemImage: "calendar.badge.exclamationmark",
                actionTitle: "Tambah Tagihan",
                action: { showAddBill = true }
            )
        } else {
            if !overdue.isEmpty {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    PLASectionHeader(title: "Jatuh Tempo Terlewat (\(overdue.count))")
                    ForEach(overdue) { bill in
                        billCard(bill, overdue: true)
                    }
                }
            }

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    PLASectionHeader(title: "Akan Datang (\(upcoming.count))")
                    ForEach(upcoming) { bill in
                        billCard(bill, overdue: false)
                    }
                }
            }

            PLAPrimaryPillButton(title: "Tambah Tagihan / Trial", systemImage: "plus") {
                showAddBill = true
            }
        }
    }

    private func billCard(_ bill: Bill, overdue: Bool) -> some View {
        let rule = store.recurrenceRule(for: bill.recurrenceRuleId)
        let tint = bill.isTrial ? PLATokens.Colors.warning : (overdue ? PLATokens.Colors.danger : PLATokens.Colors.accent)

        return PLACard(padding: PLATokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                    AdaptiveKeyValueRow {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: bill.isTrial ? "hourglass" : "creditcard.fill", color: tint, size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: PLATokens.Spacing.xs) {
                                    Text(bill.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(PLATokens.Colors.textPrimary)
                                    if bill.isTrial {
                                        StatusBadge(text: "Trial", icon: "hourglass", color: PLATokens.Colors.warning)
                                    } else if overdue {
                                        StatusBadge(text: "Terlewat", icon: "exclamationmark.triangle.fill", color: PLATokens.Colors.danger)
                                    }
                                }
                                Text(bill.isTrial
                                     ? "Trial berakhir: \(PLAFormatters.shortDate(bill.effectiveDueOrTrialEndDate))"
                                     : "Jatuh tempo: \(PLAFormatters.shortDate(bill.nextDueDateLocal))")
                                    .font(.caption)
                                    .foregroundStyle(overdue ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                                HStack(spacing: PLATokens.Spacing.xs) {
                                    if let rule {
                                        Label(PLAFormatters.recurrenceLabel(rule), systemImage: "repeat")
                                            .font(.caption2)
                                            .foregroundStyle(PLATokens.Colors.textSecondary)
                                    }
                                    Text("• \(store.accountName(for: bill.defaultAccountId))")
                                        .font(.caption2)
                                        .foregroundStyle(PLATokens.Colors.textSecondary)
                                }
                            }
                        }
                    } trailing: {
                        MoneyText(amount: bill.amount, style: .subheadline.weight(.bold))
                    }

                    Menu {
                        Button {
                            editingBill = bill
                        } label: {
                            Label("Sunting", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.deleteBill(id: bill.id)
                        } label: {
                            Label("Hapus", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Opsi tagihan \(bill.name)")
                }

                HStack(spacing: PLATokens.Spacing.sm) {
                    Button {
                        billToPay = bill
                    } label: {
                        Label("Tandai Lunas", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                            .background(PLATokens.Colors.safe, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("Lewati") {
                        billToSkip = bill
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: PLATokens.minTouchTarget)
                    .background(PLATokens.Colors.elevatedSurface, in: Capsule())
                    .overlay(Capsule().stroke(PLATokens.Colors.border, lineWidth: 1))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 4. Akun (F-07)

    @ViewBuilder
    private var accountsContent: some View {
        let balances = store.accountBalances

        PLAHeroCard(gradient: PLATokens.heroGradient) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Total Kekayaan Cair")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.84))
                        MoneyText(
                            amount: store.totalLiquidWealth,
                            style: .system(.title2, design: .rounded).weight(.bold),
                            color: Color.white
                        )
                    }
                    Spacer()
                    StatusBadge(
                        text: "\(store.activeAccounts.count) Akun",
                        icon: "wallet.pass.fill",
                        color: .white,
                        onDarkSurface: true
                    )
                }

                Button {
                    showTransfer = true
                } label: {
                    Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PLATokens.Colors.obsidianCard)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.activeAccounts.count < 2)
                .opacity(store.activeAccounts.count < 2 ? 0.55 : 1)
            }
        }

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Akun Aktif",
                actionTitle: "Tambah",
                action: { showAddAccount = true }
            )

            if store.activeAccounts.isEmpty {
                PLAEmptyStateView(
                    title: "Belum Ada Akun",
                    message: "Tambahkan dompet Tunai, Bank, atau E-wallet.",
                    systemImage: "wallet.pass",
                    actionTitle: "Tambah Akun",
                    action: { showAddAccount = true }
                )
            } else {
                ForEach(store.activeAccounts) { acc in
                    let bal = balances[acc.id] ?? acc.initialBalance
                    accountCard(acc, balance: bal)
                }
            }
        }

        if !store.archivedAccounts.isEmpty {
            PLACard(padding: PLATokens.Spacing.md) {
                DisclosureGroup("Akun Diarsipkan (\(store.archivedAccounts.count))", isExpanded: $showArchivedAccounts) {
                    VStack(spacing: PLATokens.Spacing.sm) {
                        ForEach(store.archivedAccounts) { acc in
                            let bal = balances[acc.id] ?? acc.initialBalance
                            accountCard(acc, balance: bal)
                        }
                    }
                    .padding(.top, PLATokens.Spacing.sm)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
            }
        }
    }

    private func accountCard(_ acc: Account, balance: Int64) -> some View {
        PLACard(padding: PLATokens.Spacing.md, cornerRadius: 18) {
            HStack(spacing: PLATokens.Spacing.sm) {
                Button {
                    editingAccount = acc
                } label: {
                    AdaptiveKeyValueRow {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: acc.iconName, color: PLATokens.Colors.accent, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: PLATokens.Spacing.xs) {
                                    Text(acc.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(PLATokens.Colors.textPrimary)
                                    if acc.isDefault {
                                        Text("Utama")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(PLATokens.Colors.softBlueTint, in: Capsule())
                                            .foregroundStyle(PLATokens.Colors.softBlueText)
                                    }
                                }
                                Text(PLAFormatters.accountTypeLabel(acc.type))
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.textSecondary)
                            }
                        }
                    } trailing: {
                        HStack(spacing: PLATokens.Spacing.xs) {
                            if balance < 0 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.danger)
                                    .accessibilityLabel("Saldo negatif")
                            }
                            MoneyText(
                                amount: balance,
                                style: .subheadline.weight(.bold),
                                color: balance < 0 ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                            )
                        }
                    }
                }
                .buttonStyle(.plain)

                if !acc.isArchived {
                    Menu {
                        Button {
                            editingAccount = acc
                        } label: {
                            Label("Sunting", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.deleteOrArchiveAccount(acc)
                        } label: {
                            Label("Hapus / Arsipkan", systemImage: "archivebox")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(width: 32, height: 36)
                    }
                    .accessibilityLabel("Opsi akun \(acc.name)")
                }
            }
        }
    }

    // MARK: - 5. Anggaran (F-09)

    @ViewBuilder
    private var budgetsContent: some View {
        let s = store.financialSummary

        PLACard(padding: PLATokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                AdaptiveKeyValueRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anggaran Total Bulanan")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                        Text(PLAFormatters.periodRange(s.period))
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                } trailing: {
                    StatusBadge(
                        text: PLATokens.label(for: s.budgetStatus),
                        icon: PLATokens.icon(for: s.budgetStatus),
                        color: PLATokens.color(for: s.budgetStatus)
                    )
                }

                if let totalBudget = s.totalBudget, let pct = s.percentUsed {
                    PLABreakdownBarRow(
                        title: "Terpakai (\(Int((pct * 100).rounded()))%)",
                        valueText: PLAFormatters.rupiah(s.totalExpense),
                        subtitle: "Batas \(PLAFormatters.rupiah(totalBudget)) • Sisa \(PLAFormatters.rupiah(s.remainingBudget ?? 0))",
                        progress: pct,
                        barColor: PLATokens.color(for: s.budgetStatus)
                    )
                } else {
                    Text("Belum diatur. Tetapkan batas total untuk mengaktifkan indikator keamanan belanja.")
                        .font(.subheadline)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                }

                PLAPrimaryPillButton(title: s.totalBudget == nil ? "Tetapkan Anggaran Total" : "Ubah Anggaran Total") {
                    showTotalBudgetSheet = true
                }

                Text("Transfer antar akun tidak dihitung ke dalam realisasi anggaran. Tanggal mulai siklus dapat diubah di Pengaturan.")
                    .font(.caption)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
            }
        }

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(title: "Anggaran Per Kategori")
            PLACard(padding: PLATokens.Spacing.lg) {
                VStack(spacing: PLATokens.Spacing.md) {
                    ForEach(store.expenseCategories) { cat in
                        let catSum = s.categorySummaries.first { $0.id == cat.id }
                        Button {
                            categoryForBudget = cat
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let b = catSum?.budgetAmount, let pct = catSum?.percentageOfBudget {
                                    PLABreakdownBarRow(
                                        title: cat.name,
                                        valueText: "\(PLAFormatters.rupiah(catSum?.totalSpent ?? 0))",
                                        subtitle: "Batas \(PLAFormatters.rupiah(b)) • \(Int((pct * 100).rounded()))%",
                                        progress: pct,
                                        barColor: PLATokens.color(for: catSum?.status ?? .safe)
                                    )
                                } else {
                                    HStack {
                                        PLAIconBadge(systemName: cat.iconName, color: PLATokens.Colors.accent, size: 32, iconFont: .caption.weight(.bold))
                                        Text(cat.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(PLATokens.Colors.textPrimary)
                                        Spacer()
                                        Text("Atur")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(PLATokens.Colors.accent)
                                    }
                                    .frame(minHeight: PLATokens.minTouchTarget)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        if cat.id != store.expenseCategories.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 6. Target Tabungan (P-03)

    @ViewBuilder
    private var savingsContent: some View {
        let totalSaved = store.activeSavingsGoals.reduce(Int64(0)) { $0 + $1.currentAmount }
        let totalTarget = store.activeSavingsGoals.reduce(Int64(0)) { $0 + $1.targetAmount }

        if !store.activeSavingsGoals.isEmpty {
            PLAHeroCard(gradient: PLATokens.heroGradient) {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    Text("Total Tabungan Terkumpul")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                    MoneyText(
                        amount: totalSaved,
                        style: .system(.title2, design: .rounded).weight(.bold),
                        color: Color.white
                    )
                    if totalTarget > 0 {
                        ProgressView(value: min(Double(totalSaved) / Double(totalTarget), 1.0))
                            .tint(Color.white)
                            .background(Color.white.opacity(0.24), in: Capsule())
                        Text("Dari total target \(PLAFormatters.rupiah(totalTarget))")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.84))
                    }
                }
            }
        }

        if store.activeSavingsGoals.isEmpty {
            PLAEmptyStateView(
                title: "Belum Ada Target Tabungan",
                message: "Buat target tabungan seperti Dana Darurat atau Laptop Baru untuk menghitung setoran bulanan secara otomatis.",
                systemImage: "target",
                tint: PLATokens.Colors.accent,
                actionTitle: "Tambah Target Tabungan",
                action: { showAddSavingsGoal = true }
            )
        } else {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(
                    title: "Target Tabungan Aktif",
                    actionTitle: "Tambah",
                    action: { showAddSavingsGoal = true }
                )

                ForEach(store.activeSavingsGoals) { goal in
                    savingsGoalCard(goal)
                }
            }
        }
    }

    private func savingsGoalCard(_ goal: SavingsGoal) -> some View {
        let prog = SavingsGoalCalculator.evaluate(goal: goal, today: store.today)
        let goalTint = prog.paceStatus == .achieved ? PLATokens.Colors.safe : PLATokens.Colors.primaryBlue

        return PLACard(padding: PLATokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                    PLABreakdownBarRow(
                        title: goal.name,
                        valueText: prog.paceStatus == .achieved ? "Tercapai" : "\(Int((prog.percentComplete * 100).rounded()))%",
                        subtitle: goal.targetDateLocal.map { "Target \(PLAFormatters.shortDate($0))" },
                        progress: prog.percentComplete,
                        barColor: goalTint
                    )

                    Menu {
                        Button {
                            editingSavingsGoal = goal
                        } label: {
                            Label("Sunting", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.deleteSavingsGoal(id: goal.id)
                        } label: {
                            Label("Hapus", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Opsi target tabungan \(goal.name)")
                }

                AdaptiveKeyValueRow {
                    Text("Terkumpul: \(PLAFormatters.rupiah(goal.currentAmount))")
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                } trailing: {
                    Text("Target: \(PLAFormatters.rupiah(goal.targetAmount))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                }

                if let monthly = prog.requiredMonthlyDeposit, monthly > 0 {
                    Text("Butuh setor \(PLAFormatters.rupiah(monthly))/bulan agar tercapai tepat waktu.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PLATokens.Colors.accent)
                }

                HStack(spacing: PLATokens.Spacing.sm) {
                    Button {
                        allocateSavingsTarget = SavingsAllocateRequest(goal: goal, isWithdraw: false)
                    } label: {
                        Label("Setor", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                            .background(PLATokens.Colors.primaryBlue, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("Tarik") {
                        allocateSavingsTarget = SavingsAllocateRequest(goal: goal, isWithdraw: true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: PLATokens.minTouchTarget)
                    .background(PLATokens.Colors.elevatedSurface, in: Capsule())
                    .overlay(Capsule().stroke(PLATokens.Colors.border, lineWidth: 1))
                    .buttonStyle(.plain)
                    .disabled(goal.currentAmount <= 0)
                    .opacity(goal.currentAmount <= 0 ? 0.45 : 1)
                }
            }
        }
    }
}

private struct SavingsAllocateRequest: Identifiable {
    let id = UUID()
    let goal: SavingsGoal
    let isWithdraw: Bool
}
