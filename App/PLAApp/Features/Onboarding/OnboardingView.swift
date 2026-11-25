import SwiftUI
import PLACore

/// 3-step skippable onboarding (PRD F-15 / AC-15.1 & AC-15.2).
struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var step: Int = 0
    @State private var cashText: String = ""
    @State private var bankText: String = ""
    @State private var budgetText: String = ""
    @State private var notificationRequested: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3.0)
                    .tint(PLATokens.Colors.accent)
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
            }
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
                    Button {
                        if step < 2 {
                            step += 1
                        } else {
                            finishOnboarding()
                        }
                    } label: {
                        Text(step < 2 ? "Lanjut" : "Mulai Gunakan PLA")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)

                    if step == 0 {
                        Button("Lewati Semua Pengaturan Awal") {
                            store.skipOnboarding()
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                Text("Semua data disimpan 100% lokal di iPhone Anda — tanpa akun, tanpa server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Saldo Awal (Opsional)") {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                Label("Tunai", systemImage: "banknote.fill")
                    .font(.subheadline.weight(.medium))
                TextField("Contoh: 250000 (kosongkan jika Rp0)", text: $cashText)
                    .keyboardType(.numberPad)
            }
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                Label("Bank", systemImage: "building.columns.fill")
                    .font(.subheadline.weight(.medium))
                TextField("Contoh: 2500000 (kosongkan jika Rp0)", text: $bankText)
                    .keyboardType(.numberPad)
            }
        } footer: {
            Text("Akun E-wallet dan rekening tambahan dapat ditambahkan kapan saja di tab Keuangan.")
        }
    }

    @ViewBuilder
    private var stepBudget: some View {
        Section {
            Text("Tetapkan batas belanja bulanan agar PLA dapat menghitung batas aman harian dan proyeksi akhir bulan secara otomatis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section("Batas Anggaran Total (Opsional)") {
            TextField("Contoh: 3000000", text: $budgetText)
                .keyboardType(.numberPad)
            if let parsed = parseOptionalPositiveAmount(budgetText) {
                Text("Batas bulanan: \(PLAFormatters.rupiah(parsed))")
                    .font(.footnote)
                    .foregroundStyle(PLATokens.Colors.accent)
            }
        } footer: {
            Text("Siklus default dimulai tanggal 1 setiap bulan. Anda dapat mengubah ke tanggal gajian (1–28) di Pengaturan.")
        }
    }

    @ViewBuilder
    private var stepNotifications: some View {
        Section {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                Label("Smart Reminder & Tagihan", systemImage: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(PLATokens.Colors.accent)
                Text("PLA membuat pengingat H-7, H-3, H-1, hingga Hari H secara otomatis berdasarkan prioritas tugas dan tanggal jatuh tempo tagihan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Jam tenang aktif pukul 22.00 – 07.00 sehingga notifikasi otomatis tidak mengganggu waktu istirahat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            .buttonStyle(.bordered)
            .disabled(notificationRequested)
        } footer: {
            Text("Anda tetap dapat menggunakan seluruh aplikasi walau menunda izin notifikasi.")
        }
    }

    private func parseOptionalPositiveAmount(_ raw: String) -> Int64? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if case .success(let money) = AmountParser.parse(raw) {
            return money.rupiah
        }
        return nil
    }

    private func finishOnboarding() {
        let cash = parseOptionalPositiveAmount(cashText) ?? 0
        let bank = parseOptionalPositiveAmount(bankText) ?? 0
        let budget = parseOptionalPositiveAmount(budgetText)
        store.completeOnboarding(cashBalance: cash, bankBalance: bank, monthlyBudget: budget)
    }
}
