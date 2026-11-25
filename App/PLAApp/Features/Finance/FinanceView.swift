import SwiftUI
import PLACore

enum FinanceSegment: Int, CaseIterable, Identifiable {
    case summary = 0
    case transactions = 1
    case bills = 2
    case accounts = 3
    case budgets = 4

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .summary: return "Ringkasan"
        case .transactions: return "Transaksi"
        case .bills: return "Tagihan"
        case .accounts: return "Akun"
        case .budgets: return "Anggaran"
        }
    }
}

/// Complete Finance tab: Ringkasan (F-11), Transaksi (F-08), Tagihan (F-10), Akun (F-07), Anggaran (F-09).
struct FinanceView: View {
    @Environment(AppStore.self) private var store

    @State private var segment: FinanceSegment = .summary

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        ForEach(FinanceSegment.allCases) { item in
                            Button(item.title) {
                                segment = item
                            }
                            .font(.subheadline.weight(segment == item ? .semibold : .regular))
                            .padding(.horizontal, PLATokens.Spacing.md)
                            .frame(minHeight: 36)
                            .background(segment == item ? PLATokens.Colors.accent : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(segment == item ? Color.white : Color.primary)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, PLATokens.Spacing.lg)
                    .padding(.vertical, PLATokens.Spacing.sm)
                }

                switch segment {
                case .summary:
                    summaryList
                case .transactions:
                    transactionsList
                case .bills:
                    billsList
                case .accounts:
                    accountsList
                case .budgets:
                    budgetsList
                }
            }
            .navigationTitle("Keuangan")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.settings.financeLockEnabled {
                        Button {
                            store.authService.lockImmediately()
                        } label: {
                            Image(systemName: "lock.fill")
                                .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                        }
                        .accessibilityLabel("Kunci halaman Keuangan")
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
                        Divider()
                        Button { showAddBill = true } label: {
                            Label("Tambah Tagihan", systemImage: "calendar.badge.exclamationmark")
                        }
                        Button { showAddAccount = true } label: {
                            Label("Tambah Akun/Dompet", systemImage: "creditcard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                    }
                    .accessibilityLabel("Tambah catatan keuangan")
                }
            }
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
            // AC-10.3: Skip bill cycle confirmation
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

    // MARK: - 1. Ringkasan (F-11)

    private var summaryList: some View {
        let s = store.financialSummary
        return List {
            Section {
                AdaptiveKeyValueRow {
                    Text("Periode Aktif")
                        .foregroundStyle(.secondary)
                } trailing: {
                    Text(PLAFormatters.periodRange(s.period))
                        .font(.subheadline.weight(.medium))
                }
                AdaptiveKeyValueRow {
                    Text("Hari Berjalan")
                        .foregroundStyle(.secondary)
                } trailing: {
                    Text("Hari ke-\(s.period.currentDay) dari \(s.period.totalDays) (sisa \(s.period.remainingDaysInclusive) hari)")
                        .font(.subheadline)
                }
                AdaptiveKeyValueRow {
                    Text("Total Pemasukan")
                } trailing: {
                    MoneyText(amount: s.totalIncome, color: PLATokens.Colors.safe)
                }
                AdaptiveKeyValueRow {
                    Text("Total Pengeluaran")
                } trailing: {
                    MoneyText(amount: s.totalExpense, color: s.totalExpense > 0 ? .primary : .secondary)
                }
                AdaptiveKeyValueRow {
                    Text("Arus Kas Bersih")
                        .fontWeight(.semibold)
                } trailing: {
                    MoneyText(
                        amount: s.netCashFlow,
                        color: s.netCashFlow >= 0 ? PLATokens.Colors.safe : PLATokens.Colors.danger
                    )
                }
            } header: {
                Text("Arus Kas Periode")
            }

            // Budget & Safe Daily Limit + Forecast (AC-11.1..11.3)
            Section("Anggaran & Proyeksi") {
                if let totalBudget = s.totalBudget, let pct = s.percentUsed {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                        AdaptiveKeyValueRow {
                            Text("Anggaran Bulanan")
                                .font(.subheadline.weight(.medium))
                        } trailing: {
                            StatusBadge(
                                text: "\(PLATokens.label(for: s.budgetStatus)) • \(Int((pct * 100).rounded()))%",
                                icon: PLATokens.icon(for: s.budgetStatus),
                                color: PLATokens.color(for: s.budgetStatus)
                            )
                        }
                        ProgressView(value: min(pct, 1.0))
                            .tint(PLATokens.color(for: s.budgetStatus))
                        AdaptiveKeyValueRow {
                            Text("Terpakai \(PLAFormatters.rupiah(s.totalExpense))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text("Batas \(PLAFormatters.rupiah(totalBudget))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    AdaptiveKeyValueRow {
                        Text("Sisa Anggaran")
                    } trailing: {
                        MoneyText(amount: s.remainingBudget ?? 0, color: (s.remainingBudget ?? 0) < 0 ? PLATokens.Colors.danger : .primary)
                    }

                    if s.unpaidBillsDue > 0 {
                        AdaptiveKeyValueRow {
                            Text("Cadangan Tagihan Belum Lunas")
                                .foregroundStyle(.secondary)
                        } trailing: {
                            MoneyText(amount: s.unpaidBillsDue, style: .subheadline, color: PLATokens.Colors.warning)
                        }
                        AdaptiveKeyValueRow {
                            Text("Sisa Anggaran Bebas")
                        } trailing: {
                            MoneyText(amount: s.freeRemainingBudget ?? 0)
                        }
                    }

                    AdaptiveKeyValueRow {
                        Text("Batas Aman Harian")
                            .fontWeight(.semibold)
                    } trailing: {
                        MoneyText(amount: s.safeDailyLimit ?? 0, color: PLATokens.Colors.accent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                        Text("Anggaran bulanan belum diatur.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Atur Anggaran Bulanan") {
                            showTotalBudgetSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: PLATokens.minTouchTarget)
                    }
                }

                // Forecast with Cold Start guard (AC-11.3)
                if s.isForecastReady {
                    AdaptiveKeyValueRow {
                        Text("Proyeksi Akhir Periode")
                            .fontWeight(.medium)
                    } trailing: {
                        let over = (s.totalBudget != nil && s.forecastTotal > (s.totalBudget ?? 0))
                        MoneyText(amount: s.forecastTotal, color: over ? PLATokens.Colors.danger : .primary)
                    }
                    AdaptiveKeyValueRow {
                        Text("Rata-rata Harian Variabel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } trailing: {
                        MoneyText(amount: Int64(s.averageDailyVariableExpense.rounded()), style: .caption, color: .secondary)
                    }
                } else {
                    Label(
                        "Butuh minimal 5 hari & 5 transaksi pengeluaran untuk proyeksi bulanan (saat ini: hari ke-\(s.period.currentDay), \(s.expenseTransactionCount) transaksi).",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            // Top 3 Expense Categories (AC-11.1 & §10.1 cold start)
            Section("Top 3 Kategori Pengeluaran") {
                if s.expenseTransactionCount < 3 {
                    Text("Catat minimal 3 pengeluaran untuk melihat kategori terbesar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if s.topExpenseCategories.isEmpty {
                    Text("Belum ada pengeluaran pada periode ini.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(s.topExpenseCategories) { cat in
                        AdaptiveKeyValueRow {
                            Text(cat.categoryName)
                                .font(.body)
                        } trailing: {
                            MoneyText(amount: cat.totalSpent, style: .subheadline.weight(.semibold))
                        }
                    }
                }
            }

            // Insight Cards (AC-11.2, AC-11.4)
            if !store.activeInsights.isEmpty {
                Section("Peringatan & Saran Lokal") {
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
        }
        .listStyle(.insetGrouped)
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

    private var transactionsList: some View {
        let matched = filteredTransactions
        let visible = Array(matched.prefix(txVisibleLimit))

        return List {
            Section {
                TextField("Cari catatan, kategori, atau akun...", text: $txSearchText)
                    .textFieldStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        filterChip("Semua", active: txTypeFilter == nil) { txTypeFilter = nil }
                        filterChip("Pengeluaran", active: txTypeFilter == .expense) { txTypeFilter = .expense }
                        filterChip("Pemasukan", active: txTypeFilter == .income) { txTypeFilter = .income }
                        filterChip("Transfer", active: txTypeFilter == .transfer) { txTypeFilter = .transfer }
                    }
                }

                Picker("Akun", selection: $txAccountFilter) {
                    Text("Semua Akun").tag(UUID?.none)
                    ForEach(store.accounts) { acc in
                        Text(acc.name).tag(Optional(acc.id))
                    }
                }

                Picker("Kategori", selection: $txCategoryFilter) {
                    Text("Semua Kategori").tag(UUID?.none)
                    ForEach(store.categories.filter { $0.scope != .task }) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }

                AdaptiveKeyValueRow {
                    Text("\(matched.count) transaksi cocok")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } trailing: {
                    MoneyText(
                        amount: filteredSubtotal,
                        style: .footnote.weight(.semibold),
                        color: filteredSubtotal >= 0 ? PLATokens.Colors.safe : PLATokens.Colors.danger
                    )
                }
            }

            if visible.isEmpty {
                Section {
                    PLAEmptyStateView(
                        title: "Tidak Ada Transaksi",
                        message: "Catat pemasukan atau pengeluaran baru untuk mulai memantau arus kas.",
                        systemImage: "tray",
                        actionTitle: "Catat Pengeluaran",
                        action: { showAddExpense = true }
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Daftar Transaksi") {
                    ForEach(visible) { tx in
                        transactionRow(tx)
                    }
                    if matched.count > txVisibleLimit {
                        Button("Muat Lebih Banyak (\(matched.count - txVisibleLimit) tersisa)") {
                            txVisibleLimit += 50
                        }
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.medium))
            .padding(.horizontal, PLATokens.Spacing.md)
            .frame(minHeight: 34)
            .background(active ? PLATokens.Colors.accent : Color(uiColor: .tertiarySystemFill))
            .foregroundStyle(active ? Color.white : Color.primary)
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }

    private func transactionRow(_ tx: PLATransaction) -> some View {
        let isFuture = tx.dateLocal > store.today
        return Button {
            if tx.type != .transfer {
                editingTransaction = tx
            }
        } label: {
            AdaptiveKeyValueRow {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        Text(tx.type == .transfer
                             ? "Transfer: \(store.accountName(for: tx.accountId)) → \(store.accountName(for: tx.destinationAccountId))"
                             : store.categoryName(for: tx.categoryId))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if isFuture {
                            StatusBadge(text: "Mendatang", icon: "clock", color: PLATokens.Colors.info)
                        }
                    }

                    HStack(spacing: PLATokens.Spacing.sm) {
                        Text(PLAFormatters.shortDate(tx.dateLocal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if tx.type != .transfer {
                            Text("• \(store.accountName(for: tx.accountId))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if tx.billId != nil {
                            Label("Tagihan", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(PLATokens.Colors.accent)
                        }
                    }

                    if let note = tx.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } trailing: {
                let prefix = tx.type == .income ? "+" : (tx.type == .expense ? "-" : "")
                let color: Color = tx.type == .income ? PLATokens.Colors.safe : (tx.type == .transfer ? PLATokens.Colors.info : .primary)
                Text("\(prefix)\(PLAFormatters.rupiah(tx.amount))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteTransaction(id: tx.id)
            } label: {
                Label("Hapus", systemImage: "trash")
            }
        }
    }

    // MARK: - 3. Tagihan (F-10)

    private var billsList: some View {
        let overdue = store.activeBills.filter { $0.isOverdue(on: store.today) }
        let upcoming = store.activeBills.filter { !$0.isOverdue(on: store.today) }

        return List {
            if store.activeBills.isEmpty {
                Section {
                    PLAEmptyStateView(
                        title: "Belum Ada Tagihan",
                        message: "Catat tagihan kos, listrik, internet, atau langganan rutin agar pengingat jatuh tempo dan pencatatan lunas otomatis berjalan.",
                        systemImage: "calendar.badge.exclamationmark",
                        actionTitle: "Tambah Tagihan",
                        action: { showAddBill = true }
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                if !overdue.isEmpty {
                    Section {
                        ForEach(overdue) { bill in
                            billRow(bill, overdue: true)
                        }
                    } header: {
                        Label("Jatuh Tempo Terlewat", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }

                if !upcoming.isEmpty {
                    Section("Akan Datang") {
                        ForEach(upcoming) { bill in
                            billRow(bill, overdue: false)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func billRow(_ bill: Bill, overdue: Bool) -> some View {
        let rule = store.recurrenceRule(for: bill.recurrenceRuleId)
        return VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            AdaptiveKeyValueRow {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        Text(bill.name)
                            .font(.body.weight(.semibold))
                        if overdue {
                            StatusBadge(text: "Jatuh Tempo Terlewat", icon: "exclamationmark.triangle.fill", color: PLATokens.Colors.danger)
                        }
                    }
                    Text("Jatuh tempo: \(PLAFormatters.shortDate(bill.nextDueDateLocal))")
                        .font(.caption)
                        .foregroundStyle(overdue ? PLATokens.Colors.danger : .secondary)
                    HStack(spacing: PLATokens.Spacing.sm) {
                        if let rule {
                            Label(PLAFormatters.recurrenceLabel(rule), systemImage: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("• \(store.accountName(for: bill.defaultAccountId))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if bill.isVariableAmount {
                            Text("• Estimasi")
                                .font(.caption2)
                                .foregroundStyle(PLATokens.Colors.info)
                        }
                    }
                }
            } trailing: {
                MoneyText(amount: bill.amount, style: .headline)
            }

            HStack(spacing: PLATokens.Spacing.sm) {
                Button {
                    billToPay = bill
                } label: {
                    Label("Tandai Lunas", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)

                Button("Lewati") {
                    billToSkip = bill
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteBill(id: bill.id)
            } label: {
                Label("Hapus", systemImage: "trash")
            }
            Button {
                editingBill = bill
            } label: {
                Label("Sunting", systemImage: "pencil")
            }
            .tint(PLATokens.Colors.info)
        }
    }

    // MARK: - 4. Akun (F-07)

    private var accountsList: some View {
        let balances = store.accountBalances
        return List {
            Section {
                AdaptiveKeyValueRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Kekayaan Cair")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(store.activeAccounts.count) akun aktif")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    MoneyText(
                        amount: store.totalLiquidWealth,
                        style: .title3.weight(.bold),
                        color: store.totalLiquidWealth < 0 ? PLATokens.Colors.danger : .primary
                    )
                }

                Button {
                    showTransfer = true
                } label: {
                    Label("Transfer Antar Akun", systemImage: "arrow.left.arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .disabled(store.activeAccounts.count < 2)
            }

            Section("Akun Aktif") {
                if store.activeAccounts.isEmpty {
                    PLAEmptyStateView(
                        title: "Belum Ada Akun",
                        message: "Tambahkan dompet Tunai, Bank, atau E-wallet.",
                        systemImage: "wallet.pass",
                        actionTitle: "Tambah Akun",
                        action: { showAddAccount = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.activeAccounts) { acc in
                        let bal = balances[acc.id] ?? acc.initialBalance
                        accountRow(acc, balance: bal)
                    }
                }
            }

            if !store.archivedAccounts.isEmpty {
                Section {
                    DisclosureGroup("Akun Diarsipkan (\(store.archivedAccounts.count))", isExpanded: $showArchivedAccounts) {
                        ForEach(store.archivedAccounts) { acc in
                            let bal = balances[acc.id] ?? acc.initialBalance
                            accountRow(acc, balance: bal)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func accountRow(_ acc: Account, balance: Int64) -> some View {
        Button {
            editingAccount = acc
        } label: {
            AdaptiveKeyValueRow {
                HStack(spacing: PLATokens.Spacing.md) {
                    Image(systemName: acc.iconName)
                        .font(.title3)
                        .foregroundStyle(PLATokens.color(forToken: acc.colorToken))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: PLATokens.Spacing.xs) {
                            Text(acc.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if acc.isDefault {
                                Text("Utama")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PLATokens.Colors.accent.opacity(0.16), in: Capsule())
                                    .foregroundStyle(PLATokens.Colors.accent)
                            }
                        }
                        Text(PLAFormatters.accountTypeLabel(acc.type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        style: .subheadline.weight(.semibold),
                        color: balance < 0 ? PLATokens.Colors.danger : .primary
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !acc.isArchived {
                Button(role: .destructive) {
                    store.deleteOrArchiveAccount(acc)
                } label: {
                    Label("Hapus / Arsipkan", systemImage: "archivebox")
                }
            }
        }
    }

    // MARK: - 5. Anggaran (F-09)

    private var budgetsList: some View {
        let s = store.financialSummary
        return List {
            Section {
                AdaptiveKeyValueRow {
                    Text("Periode Aktif")
                        .foregroundStyle(.secondary)
                } trailing: {
                    Text(PLAFormatters.periodRange(s.period))
                        .font(.subheadline.weight(.medium))
                }

                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    AdaptiveKeyValueRow {
                        Text("Anggaran Total Bulanan")
                            .font(.headline)
                    } trailing: {
                        StatusBadge(
                            text: PLATokens.label(for: s.budgetStatus),
                            icon: PLATokens.icon(for: s.budgetStatus),
                            color: PLATokens.color(for: s.budgetStatus)
                        )
                    }

                    if let totalBudget = s.totalBudget, let pct = s.percentUsed {
                        ProgressView(value: min(pct, 1.0))
                            .tint(PLATokens.color(for: s.budgetStatus))
                        AdaptiveKeyValueRow {
                            Text("Terpakai: \(PLAFormatters.rupiah(s.totalExpense)) (\(Int((pct * 100).rounded()))%)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text("Sisa: \(PLAFormatters.rupiah(s.remainingBudget ?? 0))")
                                .font(.caption.weight(.medium))
                        }
                        Text("Batas total: \(PLAFormatters.rupiah(totalBudget))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Belum diatur. Tetapkan batas total untuk mengaktifkan indikator keamanan belanja.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(s.totalBudget == nil ? "Tetapkan Anggaran Total" : "Ubah Anggaran Total") {
                        showTotalBudgetSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: PLATokens.minTouchTarget)
                }
                .padding(.vertical, PLATokens.Spacing.xs)
            } header: {
                Text("Anggaran Total")
            } footer: {
                Text("Transfer antar akun tidak dihitung ke dalam realisasi anggaran. Tanggal mulai siklus dapat diubah di Pengaturan.")
            }

            Section("Anggaran Per Kategori (Opsional)") {
                ForEach(store.expenseCategories) { cat in
                    let catSum = s.categorySummaries.first { $0.id == cat.id }
                    Button {
                        categoryForBudget = cat
                    } label: {
                        VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                            AdaptiveKeyValueRow {
                                Label(cat.name, systemImage: cat.iconName)
                                    .foregroundStyle(.primary)
                            } trailing: {
                                if let b = catSum?.budgetAmount, let pct = catSum?.percentageOfBudget {
                                    StatusBadge(
                                        text: "\(PLATokens.label(for: catSum?.status ?? .safe)) • \(Int((pct * 100).rounded()))%",
                                        icon: PLATokens.icon(for: catSum?.status ?? .safe),
                                        color: PLATokens.color(for: catSum?.status ?? .safe)
                                    )
                                } else {
                                    Text("Atur")
                                        .font(.caption)
                                        .foregroundStyle(PLATokens.Colors.accent)
                                }
                            }

                            if let b = catSum?.budgetAmount, let pct = catSum?.percentageOfBudget {
                                ProgressView(value: min(pct, 1.0))
                                    .tint(PLATokens.color(for: catSum?.status ?? .safe))
                                AdaptiveKeyValueRow {
                                    Text("Terpakai \(PLAFormatters.rupiah(catSum?.totalSpent ?? 0))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } trailing: {
                                    Text("Batas \(PLAFormatters.rupiah(b))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
