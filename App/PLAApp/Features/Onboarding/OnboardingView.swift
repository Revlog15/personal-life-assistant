import SwiftUI
import PLACore

/// 3-step skippable onboarding (PRD F-15 / AC-15.1 & AC-15.2) in cohesive White & Blue with dot-formatted Rupiah inputs,
/// payday cycle selector, and optional mid-cycle remaining budget adjustment.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var step: Int = 0
    @State private var cashText: String = ""
    @State private var bankText: String = ""
    @State private var cycleStartDay: Int = 1
    @State private var budgetText: String = ""
    @State private var remainingCycleText: String = ""
    @State private var notificationRequested: Bool = false

    private var previewPeriod: BudgetPeriod {
        BudgetPeriod.current(for: store.today, cycleStartDay: cycleStartDay)
    }

    private var parsedMonthlyBudget: Int64? {
        parseOptionalAmount(budgetText, allowZero: false)
    }

    private var parsedRemainingCycle: Int64? {
        parseOptionalAmount(remainingCycleText, allowZero: true)
    }

    private var remainingExceedsMonthly: Bool {
        guard let monthly = parsedMonthlyBudget, let rem = parsedRemainingCycle else { return false }
        return rem > monthly
    }

    private var canAdvanceFromCurrentStep: Bool {
        if step == 1 && remainingExceedsMonthly {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3.0)
                    .tint(PLATokens.Colors.primaryBlue)
                    .padding(.horizontal, PLATokens.Spacing.lg)
                    .padding(.top, PLATokens.Spacing.sm)

                Form {
                    if step == 0 {
                        stepAccounts
                    } else if step == 1 {
                        stepBudget
                    } else {
                        stepNotifications
                    }
                }
                .scrollContentBackground(.hidden)
                .background(PLATokens.Colors.canvas)
            }
            .background(PLATokens.Colors.canvas)
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lewati") {
                        if step < 2 {
                            step += 1
                        } else {
                            finishOnboarding()
                        }
                    }
                    .frame(minHeight: PLATokens.minTouchTarget)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: PLATokens.Spacing.sm) {
                    PLAPrimaryPillButton(
                        title: step < 2 ? "Lanjut" : "Mulai Gunakan PLA",
                        isDisabled: !canAdvanceFromCurrentStep
                    ) {
                        if step < 2 {
                            step += 1
                        } else {
                            finishOnboarding()
                        }
                    }

                    if step == 0 {
                        Button("Lewati Semua Pengaturan Awal") {
                            store.skipOnboarding()
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .frame(minHeight: PLATokens.minTouchTarget)
                    }
                }
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.vertical, PLATokens.Spacing.md)
                .background(.bar)
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Akun Awal"
        case 1: return "Anggaran Bulanan"
        default: return "Pengingat Otomatis"
        }
    }

    @ViewBuilder
    private var stepAccounts: some View {
        Section {
            PLAHeroCard(gradient: PLATokens.heroGradient) {
                HStack(spacing: PLATokens.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 48, height: 48)
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("100% Privat & Offline")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Text("Semua data disimpan lokal di iPhone Anda, tanpa akun dan tanpa server.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.86))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    PLAIconBadge(systemName: "banknote.fill", color: PLATokens.Colors.accent, size: 28, iconFont: .caption.weight(.bold))
                    Text("Tunai")
                        .font(.subheadline.weight(.semibold))
                }
                RupiahTextField(
                    placeholder: "Contoh: 250.000",
                    text: $cashText,
                    font: .body.weight(.semibold),
                    accentColor: PLATokens.Colors.accent
                )
            }
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    PLAIconBadge(systemName: "building.columns.fill", color: PLATokens.Colors.accent, size: 28, iconFont: .caption.weight(.bold))
                    Text("Bank")
                        .font(.subheadline.weight(.semibold))
                }
                RupiahTextField(
                    placeholder: "Contoh: 2.500.000",
                    text: $bankText,
                    font: .body.weight(.semibold),
                    accentColor: PLATokens.Colors.accent
                )
            }
        } header: {
            Text("Saldo Riil Saat Ini (Opsional)")
        } footer: {
            Text("Masukkan saldo yang ada di tangan dan rekening hari ini. Akun E-wallet dapat ditambahkan kapan saja di tab Keuangan.")
        }
    }

    @ViewBuilder
    private var stepBudget: some View {
        Section {
            PLAHeroCard(gradient: PLATokens.heroGradient) {
                HStack(spacing: PLATokens.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 48, height: 48)
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kontrol Belanja Otomatis")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Text("PLA menghitung batas aman harian dan proyeksi akhir siklus secara deterministik.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.86))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            Stepper("Tanggal Gajian / Siklus: Tanggal \(cycleStartDay)", value: $cycleStartDay, in: 1...28)
            Text("Siklus aktif: \(PLAFormatters.periodRange(previewPeriod)) • Hari ke-\(previewPeriod.currentDay)/\(previewPeriod.totalDays)")
                .font(.caption)
                .foregroundStyle(PLATokens.Colors.textSecondary)
        } header: {
            Text("Tanggal Mulai Siklus")
        }

        Section {
            RupiahTextField(
                placeholder: "Contoh: 1.500.000",
                text: $budgetText,
                font: .title3.weight(.bold),
                accentColor: PLATokens.Colors.accent
            )
            if let parsed = parsedMonthlyBudget {
                Text("Batas bulanan normal: \(PLAFormatters.rupiah(parsed))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.accent)
            }
        } header: {
            Text("Anggaran Bulanan Normal (Opsional)")
        }

        if let monthly = parsedMonthlyBudget {
            Section {
                RupiahTextField(
                    placeholder: "Kosongkan jika masih utuh",
                    text: $remainingCycleText,
                    allowZero: true,
                    font: .body.weight(.bold),
                    accentColor: PLATokens.Colors.accent
                )

                if remainingExceedsMonthly {
                    Text("Sisa anggaran siklus ini tidak boleh melebihi batas bulanan normal (\(PLAFormatters.rupiah(monthly))).")
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.danger)
                } else if let rem = parsedRemainingCycle {
                    let alreadySpent = BudgetCalculator.openingSpent(
                        monthlyBudget: monthly,
                        remainingForCurrentCycle: rem,
                        recordedExpense: 0
                    )
                    let daily = rem > 0 ? rem / Int64(max(previewPeriod.remainingDaysInclusive, 1)) : 0
                    Text("Sudah terpakai \(PLAFormatters.rupiah(alreadySpent)) • Batas aman \(PLAFormatters.rupiah(daily))/hari untuk \(previewPeriod.remainingDaysInclusive) hari tersisa. Siklus depan otomatis kembali penuh \(PLAFormatters.rupiah(monthly)).")
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.accent)
                }
            } header: {
                Text("Sisa Anggaran Siklus Ini (Opsional)")
            } footer: {
                Text("Misal gajian tanggal \(cycleStartDay) tetapi baru mulai mencatat hari ini: cukup ketik sisa anggaran yang masih tersedia. Saldo dompet awal tidak ikut terpotong.")
            }
        }
    }

    @ViewBuilder
    private var stepNotifications: some View {
        Section {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(spacing: PLATokens.Spacing.md) {
                    PLAIconBadge(systemName: "bell.badge.fill", color: PLATokens.Colors.accent, size: 46, iconFont: .title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Reminder & Tagihan")
                            .font(.headline)
                        Text("Pengingat H-7, H-3, H-1 hingga Hari H otomatis.")
                            .font(.footnote)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
                Text("Jam tenang aktif pukul 22.00 - 07.00 sehingga notifikasi otomatis tidak mengganggu waktu istirahat.")
                    .font(.footnote)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
            }
            .padding(.vertical, PLATokens.Spacing.xs)
        }

        Section {
            Button {
                _Concurrency.Task {
                    await store.requestNotificationPermission()
                    notificationRequested = true
                }
            } label: {
                Label(
                    notificationRequested ? "Izin Notifikasi Diminta" : "Aktifkan Notifikasi Pengingat",
                    systemImage: notificationRequested ? "checkmark.circle.fill" : "bell.fill"
                )
                .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(notificationRequested ? PLATokens.Colors.safe : PLATokens.Colors.primaryBlue)
            .disabled(notificationRequested)
        } footer: {
            Text("Anda tetap dapat menggunakan seluruh aplikasi walau menunda izin notifikasi.")
        }
    }

    private func parseOptionalAmount(_ raw: String, allowZero: Bool) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if allowZero && trimmed == "0" { return 0 }
        if case .success(let money) = AmountParser.parse(trimmed) {
            return money.rupiah
        }
        return nil
    }

    private func finishOnboarding() {
        let cash = parseOptionalAmount(cashText, allowZero: false) ?? 0
        let bank = parseOptionalAmount(bankText, allowZero: false) ?? 0
        let budget = parsedMonthlyBudget
        let remaining = (budget != nil && !remainingExceedsMonthly) ? parsedRemainingCycle : nil
        store.completeOnboarding(
            cashBalance: cash,
            bankBalance: bank,
            monthlyBudget: budget,
            budgetCycleStartDay: cycleStartDay,
            remainingBudgetForCurrentCycle: remaining
        )
    }
}
