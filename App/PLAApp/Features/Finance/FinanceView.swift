import SwiftUI
import PLACore

enum FinanceSegment: Int, CaseIterable, Identifiable {
    case summary = 0
    case transactions = 1
    case bills = 2
    case wallet = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .summary: return "Ringkasan"
        case .transactions: return "Transaksi"
        case .bills: return "Tagihan"
        case .wallet: return "Dompet"
        }
    }
}

/// Finance tab (PRD §7.2, F-07..F-11, P-03, P-04): 4 full-width Liquid Glass tabs (Ringkasan, Transaksi, Tagihan, Dompet),
/// distilled hierarchy without redundant cards, and flat grouped rows with hairline separators.
struct FinanceView: View {
    @Environment(AppStore.self) private var store

    @State private var segment: FinanceSegment = .summary
    @State private var chartRange: SpendingChartRange = .cycle
    @State private var showCategoryBudgets = false

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.section) {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                        headerBar
                        PLAGlassSegmentBar(
                            options: FinanceSegment.allCases,
                            selection: $segment,
                            title: \.title
                        )
                    }

                    switch segment {
                    case .summary:
                        summaryContent
                    case .transactions:
                        transactionsContent
                    case .bills:
                        billsContent
                    case .wallet:
                        walletContent
                    }
                }
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.top, PLATokens.Spacing.sm)
                .padding(.bottom, PLATokens.floatingDockClearance)
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

    // MARK: - Top Header

    private var headerBar: some View {
        PLAScreenHeader("Keuangan") {
            HStack(spacing: PLATokens.Spacing.sm) {
                if store.settings.financeLockEnabled {
                    PLALiquidGlassIconButton(
                        systemImage: "lock.fill",
                        accessibilityLabel: "Kunci halaman Keuangan"
                    ) {
                        store.authService.lockImmediately()
                    }
                }

                Menu {
                    Section("Catat") {
                        Button { showAddExpense = true } label: {
                            Label("Pengeluaran", systemImage: "arrow.up.right.circle")
                        }
                        Button { showAddIncome = true } label: {
                            Label("Pemasukan", systemImage: "arrow.down.left.circle")
                        }
                        Button { showTransfer = true } label: {
                            Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle")
                        }
                        Button { showOCRScanSheet = true } label: {
                            Label("Scan Struk (OCR)", systemImage: "doc.text.viewfinder")
                        }
                    }
                    Section("Kelola") {
                        Button { showWhatIfSheet = true } label: {
                            Label("Simulasi Beli (What-If)", systemImage: "slider.horizontal.3")
                        }
                        Button { showAddBill = true } label: {
                            Label("Tagihan / Trial Baru", systemImage: "calendar.badge.exclamationmark")
                        }
                        Button { showAddAccount = true } label: {
                            Label("Akun / Dompet Baru", systemImage: "creditcard")
                        }
                        Button { showAddSavingsGoal = true } label: {
                            Label("Target Tabungan Baru", systemImage: "target")
                        }
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
    }

    // MARK: - 1. Ringkasan (Distilled to 3 Calm Blocks: Hero Chart + Budget/Forecast + Top Categories)

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

        // Block 1: Obsidian Spending Trend Hero (integrates Pemasukan & Arus Kas cleanly)
        PLAChartHeroCard(
            title: "Tren Pengeluaran",
            subtitle: "\(PLAFormatters.periodRange(s.period)) • Hari \(s.period.currentDay)/\(s.period.totalDays)",
            totalAmount: chartRange == .cycle ? s.recordedExpense : rangeTotal,
            points: points,
            selectedRange: $chartRange,
            status: s.budgetStatus,
            footerLeftLabel: "Pemasukan",
            footerLeftValue: PLAFormatters.compactRupiah(s.totalIncome),
            footerRightLabel: "Arus Kas Bersih",
            footerRightValue: PLAFormatters.compactRupiah(s.netCashFlow)
        )

        // Block 2: Unified Budget, Safe Daily Limit, Forecast & Collapsible Category Budgets
        budgetAndForecastCard(s)

        // Block 3: Top 3 Categories (Macro-style horizontal breakdown bars)
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(title: "Kategori Terbesar")
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
                                subtitle: "\(pctInt)% dari belanja harian",
                                progress: cat.percentageOfVariable,
                                barColor: PLATokens.Colors.primaryBlue
                            )
                        }
                    }
                }
            }
        }

        // Optional Insights (shown only when triggered)
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

    private func budgetAndForecastCard(_ s: FinancialPeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Anggaran Bulanan",
                actionTitle: s.totalBudget == nil ? "Atur" : "Ubah",
                action: { showTotalBudgetSheet = true }
            )

            PLACard(padding: PLATokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                    if let totalBudget = s.totalBudget, let pct = s.percentUsed {
                        PLABreakdownBarRow(
                            title: "Terpakai \(Int((pct * 100).rounded()))%",
                            valueText: PLAFormatters.rupiah(s.totalExpense),
                            subtitle: "Batas \(PLAFormatters.rupiah(totalBudget))",
                            progress: pct,
                            barColor: PLATokens.color(for: s.budgetStatus)
                        )

                        PLAInsetDivider()

                        summaryLine(
                            label: "Sisa Anggaran",
                            value: PLAFormatters.rupiah(s.remainingBudget ?? 0),
                            valueColor: (s.remainingBudget ?? 0) < 0 ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                        )
                        if s.openingSpent > 0 {
                            summaryLine(
                                label: "Terpakai Sebelum Mulai",
                                value: PLAFormatters.rupiah(s.openingSpent),
                                valueColor: PLATokens.Colors.textSecondary
                            )
                        }
                        summaryLine(
                            label: "Batas Aman/Hari (\(s.period.remainingDaysInclusive) hari)",
                            value: PLAFormatters.rupiah(s.safeDailyLimit ?? 0),
                            valueColor: PLATokens.Colors.accent
                        )
                        if s.unpaidBillsDue > 0 {
                            summaryLine(
                                label: "Tagihan Belum Lunas",
                                value: PLAFormatters.rupiah(s.unpaidBillsDue),
                                valueColor: PLATokens.Colors.warning
                            )
                        }
                        if s.isForecastReady {
                            summaryLine(
                                label: "Proyeksi Akhir Periode",
                                value: PLAFormatters.rupiah(s.forecastTotal),
                                valueColor: s.forecastTotal > totalBudget ? PLATokens.Colors.danger : PLATokens.Colors.textPrimary
                            )
                        } else {
                            Text("Proyeksi aktif setelah minimal 5 hari dan 5 pengeluaran (saat ini: hari ke-\(s.period.currentDay), \(s.expenseTransactionCount) transaksi).")
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                        }
                    } else {
                        Text("Tetapkan batas anggaran bulanan untuk menghitung batas aman harian dan proyeksi belanja.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                        PLAPrimaryPillButton(title: "Atur Anggaran Bulanan") {
                            showTotalBudgetSheet = true
                        }
                    }

                    PLAInsetDivider()

                    // Collapsible Category Budgets (keeps F-09 100% accessible without a 5th tab)
                    DisclosureGroup(isExpanded: $showCategoryBudgets) {
                        VStack(spacing: PLATokens.Spacing.md) {
                            ForEach(store.expenseCategories) { cat in
                                let catSum = s.categorySummaries.first { $0.id == cat.id }
                                Button {
                                    categoryForBudget = cat
                                } label: {
                                    if let b = catSum?.budgetAmount, let pct = catSum?.percentageOfBudget {
                                        PLABreakdownBarRow(
                                            title: cat.name,
                                            valueText: PLAFormatters.rupiah(catSum?.totalSpent ?? 0),
                                            subtitle: "Batas \(PLAFormatters.rupiah(b)) • \(Int((pct * 100).rounded()))%",
                                            progress: pct,
                                            barColor: PLATokens.color(for: catSum?.status ?? .safe)
                                        )
                                    } else {
                                        HStack {
                                            Text(cat.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(PLATokens.Colors.textPrimary)
                                            Spacer()
                                            Text("Atur batas")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(PLATokens.Colors.accent)
                                        }
                                        .frame(minHeight: 36)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, PLATokens.Spacing.md)
                    } label: {
                        Text("Anggaran Per Kategori")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                    }
                    .tint(PLATokens.Colors.accent)
                }
            }
        }
    }

    private func summaryLine(label: String, value: String, valueColor: Color = PLATokens.Colors.textPrimary) -> some View {
        AdaptiveKeyValueRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PLATokens.Colors.textSecondary)
        } trailing: {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
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

        VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
            // Clean minimalist search capsule
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
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bersihkan pencarian")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(PLATokens.Colors.surface, in: Capsule())

            // Compact filter chips + pickers row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PLATokens.Spacing.xs) {
                    filterChip("Semua", active: txTypeFilter == nil) { txTypeFilter = nil }
                    filterChip("Pengeluaran", active: txTypeFilter == .expense) { txTypeFilter = .expense }
                    filterChip("Pemasukan", active: txTypeFilter == .income) { txTypeFilter = .income }
                    filterChip("Transfer", active: txTypeFilter == .transfer) { txTypeFilter = .transfer }

                    Menu {
                        Button("Semua Akun") { txAccountFilter = nil }
                        ForEach(store.accounts) { acc in
                            Button(acc.name) { txAccountFilter = acc.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(txAccountFilter.map { store.accountName(for: $0) } ?? "Akun")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(txAccountFilter == nil ? PLATokens.Colors.textPrimary : Color.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            Capsule().fill(txAccountFilter == nil ? PLATokens.Colors.surface : PLATokens.Colors.primaryBlue)
                        )
                    }

                    Menu {
                        Button("Semua Kategori") { txCategoryFilter = nil }
                        ForEach(store.categories.filter { $0.scope != .task }) { cat in
                            Button(cat.name) { txCategoryFilter = cat.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(txCategoryFilter.map { store.categoryName(for: $0) } ?? "Kategori")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(txCategoryFilter == nil ? PLATokens.Colors.textPrimary : Color.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            Capsule().fill(txCategoryFilter == nil ? PLATokens.Colors.surface : PLATokens.Colors.primaryBlue)
                        )
                    }
                }
            }

            AdaptiveKeyValueRow {
                Text("\(matched.count) transaksi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textSecondary)
            } trailing: {
                MoneyText(
                    amount: filteredSubtotal,
                    style: .footnote.weight(.bold),
                    color: filteredSubtotal >= 0 ? PLATokens.Colors.safe : PLATokens.Colors.danger
                )
            }
            .padding(.horizontal, 4)

            if visible.isEmpty {
                PLAEmptyStateView(
                    title: "Tidak Ada Transaksi",
                    message: "Catat pemasukan atau pengeluaran baru untuk mulai memantau arus kas.",
                    systemImage: "tray",
                    actionTitle: "Catat Pengeluaran",
                    action: { showAddExpense = true }
                )
            } else {
                PLAGroupList {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, tx in
                        transactionRow(tx)
                        if idx < visible.count - 1 {
                            PLAInsetDivider(leadingInset: 48)
                        }
                    }
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
            .frame(minHeight: 36)
            .background(
                Capsule()
                    .fill(active ? PLATokens.Colors.primaryBlue : PLATokens.Colors.surface)
            )
            .foregroundStyle(active ? Color.white : PLATokens.Colors.textPrimary)
            .buttonStyle(.plain)
    }

    private func transactionRow(_ tx: PLATransaction) -> some View {
        let isFuture = tx.dateLocal > store.today
        let cat = store.categories.first { $0.id == tx.categoryId }
        let badgeColor: Color = tx.type == .income ? PLATokens.Colors.safe : (tx.type == .expense ? PLATokens.Colors.danger : PLATokens.Colors.accent)
        let badgeIcon: String = tx.type == .transfer
            ? "arrow.left.arrow.right"
            : (cat?.iconName ?? (tx.type == .income ? "arrow.down.left" : "tag.fill"))

        return Button {
            if tx.type != .transfer {
                editingTransaction = tx
            }
        } label: {
            AdaptiveKeyValueRow {
                HStack(spacing: PLATokens.Spacing.md) {
                    PLAIconBadge(systemName: badgeIcon, color: badgeColor, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.type == .transfer
                             ? "Transfer: \(store.accountName(for: tx.accountId)) -> \(store.accountName(for: tx.destinationAccountId))"
                             : store.categoryName(for: tx.categoryId))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                            .multilineTextAlignment(.leading)

                        Text(transactionSubtitle(tx, isFuture: isFuture))
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            } trailing: {
                let prefix = tx.type == .income ? "+" : (tx.type == .expense ? "-" : "")
                Text("\(prefix)\(PLAFormatters.rupiah(tx.amount))")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(badgeColor)
            }
            .padding(.vertical, PLATokens.Spacing.sm)
        }
        .buttonStyle(.plain)
        .contextMenu {
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
        }
    }

    private func transactionSubtitle(_ tx: PLATransaction, isFuture: Bool) -> String {
        var parts: [String] = [PLAFormatters.shortDate(tx.dateLocal)]
        if tx.type != .transfer {
            parts.append(store.accountName(for: tx.accountId))
        }
        if isFuture {
            parts.append("Mendatang")
        }
        if let note = tx.note, !note.isEmpty {
            parts.append(note)
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - 3. Tagihan (F-10)

    @ViewBuilder
    private var billsContent: some View {
        let overdue = store.activeBills.filter { $0.isOverdue(on: store.today) }
        let upcoming = store.activeBills.filter { !$0.isOverdue(on: store.today) }

        if store.activeBills.isEmpty {
            PLAEmptyStateView(
                title: "Belum Ada Tagihan",
                message: "Catat tagihan kos, listrik, internet, atau langganan rutin agar pengingat dan pencatatan lunas otomatis berjalan.",
                systemImage: "calendar.badge.exclamationmark",
                actionTitle: "Tambah Tagihan",
                action: { showAddBill = true }
            )
        } else {
            if !overdue.isEmpty {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    PLASectionHeader(title: "Terlewat (\(overdue.count))")
                    PLAGroupList {
                        ForEach(Array(overdue.enumerated()), id: \.element.id) { idx, bill in
                            billRow(bill, overdue: true)
                            if idx < overdue.count - 1 {
                                PLAInsetDivider()
                            }
                        }
                    }
                }
            }

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    PLASectionHeader(title: "Akan Datang (\(upcoming.count))")
                    PLAGroupList {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { idx, bill in
                            billRow(bill, overdue: false)
                            if idx < upcoming.count - 1 {
                                PLAInsetDivider()
                            }
                        }
                    }
                }
            }

            PLAPrimaryPillButton(title: "Tambah Tagihan / Trial", systemImage: "plus") {
                showAddBill = true
            }
        }
    }

    private func billRow(_ bill: Bill, overdue: Bool) -> some View {
        let rule = store.recurrenceRule(for: bill.recurrenceRuleId)
        let tint = bill.isTrial ? PLATokens.Colors.warning : (overdue ? PLATokens.Colors.danger : PLATokens.Colors.accent)

        return VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
            AdaptiveKeyValueRow {
                HStack(spacing: PLATokens.Spacing.md) {
                    PLAIconBadge(systemName: bill.isTrial ? "hourglass" : "creditcard.fill", color: tint, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                        Text(bill.isTrial
                             ? "Trial berakhir \(PLAFormatters.shortDate(bill.effectiveDueOrTrialEndDate))"
                             : "Jatuh tempo \(PLAFormatters.shortDate(bill.nextDueDateLocal))")
                            .font(.caption)
                            .foregroundStyle(overdue ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                        Text([rule.map { PLAFormatters.recurrenceLabel($0) }, store.accountName(for: bill.defaultAccountId)]
                            .compactMap { $0 }
                            .joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } trailing: {
                MoneyText(amount: bill.amount, style: .subheadline.weight(.bold))
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
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, PLATokens.Spacing.md)
        .contextMenu {
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
        }
    }

    // MARK: - 4. Dompet (Akun + Target Tabungan)

    @ViewBuilder
    private var walletContent: some View {
        let balances = store.accountBalances

        // Total Liquidity Hero
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
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.activeAccounts.count < 2)
                .opacity(store.activeAccounts.count < 2 ? 0.55 : 1)
            }
        }

        // Active Accounts (Single Grouped Surface)
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
                PLAGroupList {
                    ForEach(Array(store.activeAccounts.enumerated()), id: \.element.id) { idx, acc in
                        let bal = balances[acc.id] ?? acc.initialBalance
                        accountRow(acc, balance: bal)
                        if idx < store.activeAccounts.count - 1 {
                            PLAInsetDivider(leadingInset: 48)
                        }
                    }
                }
            }
        }

        if !store.archivedAccounts.isEmpty {
            PLACard(padding: PLATokens.Spacing.lg) {
                DisclosureGroup("Akun Diarsipkan (\(store.archivedAccounts.count))", isExpanded: $showArchivedAccounts) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.archivedAccounts.enumerated()), id: \.element.id) { idx, acc in
                            let bal = balances[acc.id] ?? acc.initialBalance
                            accountRow(acc, balance: bal)
                            if idx < store.archivedAccounts.count - 1 {
                                PLAInsetDivider(leadingInset: 48)
                            }
                        }
                    }
                    .padding(.top, PLATokens.Spacing.sm)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
            }
        }

        // Savings Goals (P-03) integrated cleanly below Accounts
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: "Target Tabungan",
                actionTitle: "Tambah",
                action: { showAddSavingsGoal = true }
            )

            if store.activeSavingsGoals.isEmpty {
                PLACard(padding: PLATokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                        Text("Belum ada target tabungan.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                        Text("Buat target seperti Dana Darurat atau Laptop Baru untuk menghitung setoran bulanan otomatis.")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } else {
                PLAGroupList {
                    ForEach(Array(store.activeSavingsGoals.enumerated()), id: \.element.id) { idx, goal in
                        savingsGoalRow(goal)
                        if idx < store.activeSavingsGoals.count - 1 {
                            PLAInsetDivider()
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ acc: Account, balance: Int64) -> some View {
        Button {
            editingAccount = acc
        } label: {
            AdaptiveKeyValueRow {
                HStack(spacing: PLATokens.Spacing.md) {
                    PLAIconBadge(systemName: acc.iconName, color: PLATokens.Colors.accent, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: PLATokens.Spacing.xs) {
                            Text(acc.name)
                                .font(.subheadline.weight(.semibold))
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
            .padding(.vertical, PLATokens.Spacing.sm)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingAccount = acc
            } label: {
                Label("Sunting", systemImage: "pencil")
            }
            if !acc.isArchived {
                Button(role: .destructive) {
                    store.deleteOrArchiveAccount(acc)
                } label: {
                    Label("Hapus / Arsipkan", systemImage: "archivebox")
                }
            }
        }
    }

    private func savingsGoalRow(_ goal: SavingsGoal) -> some View {
        let prog = SavingsGoalCalculator.evaluate(goal: goal, today: store.today)
        let goalTint = prog.paceStatus == .achieved ? PLATokens.Colors.safe : PLATokens.Colors.primaryBlue

        return VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLABreakdownBarRow(
                title: goal.name,
                valueText: prog.paceStatus == .achieved ? "Tercapai" : "\(Int((prog.percentComplete * 100).rounded()))%",
                subtitle: "\(PLAFormatters.rupiah(goal.currentAmount)) dari \(PLAFormatters.rupiah(goal.targetAmount))",
                progress: prog.percentComplete,
                barColor: goalTint
            )

            if let monthly = prog.requiredMonthlyDeposit, monthly > 0 {
                Text("Butuh setor \(PLAFormatters.rupiah(monthly))/bulan agar tercapai tepat waktu.")
                    .font(.caption)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
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
                .buttonStyle(.plain)
                .disabled(goal.currentAmount <= 0)
                .opacity(goal.currentAmount <= 0 ? 0.45 : 1)
            }
        }
        .padding(.vertical, PLATokens.Spacing.md)
        .contextMenu {
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
        }
    }
}

private struct SavingsAllocateRequest: Identifiable {
    let id = UUID()
    let goal: SavingsGoal
    let isWithdraw: Bool
}
