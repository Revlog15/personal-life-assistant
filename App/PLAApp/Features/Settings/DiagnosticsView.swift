import SwiftUI
import UIKit
import PLACore

/// Diagnostics, Sideload Expiry, Tester Feedback Bundle, SC-07 Benchmark Seeder, and UI Component Preview Catalog (PRD F-14, R-08, §16.2).
struct DiagnosticsView: View {
    @Environment(AppStore.self) private var store
    @State private var copiedConfirmation = false
    @State private var showSeedConfirm = false
    @State private var appGroupProbeMessage: String?
    @State private var appGroupProbePassed: Bool?

    var body: some View {
        Form {
            // 1. Sideload Certificate Health (AC-14.1, V-16)
            Section {
                AdaptiveKeyValueRow {
                    Text("Status Sertifikat")
                } trailing: {
                    Text(store.sideloadInfo.summaryText(today: store.today))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(store.sideloadInfo.shouldShowBanner(on: store.today) ? PLATokens.Colors.warning : .primary)
                        .multilineTextAlignment(.trailing)
                }

                AdaptiveKeyValueRow {
                    Text("Sumber Bacaan")
                        .foregroundStyle(.secondary)
                } trailing: {
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.recordManualSideloadRefreshToday()
                } label: {
                    Label("Catat Refresh SideStore Hari Ini (+7 Hari)", systemImage: "arrow.clockwise.circle")
                }
            } header: {
                Text("Masa Berlaku Sideload (SideStore)")
            } footer: {
                Text("Jika embedded.mobileprovision tidak terbaca di perangkat, gunakan tombol di atas setelah refresh di SideStore untuk mengaktifkan pengingat H-2 & H-1.")
            }

            // 1b. App Group & Extension Health (PRD P-06, P-07 & V-07)
            Section {
                let ag = store.appGroupStatus
                AdaptiveKeyValueRow {
                    Text("App Group Aktif")
                } trailing: {
                    Text(ag.resolvedGroupId)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }

                AdaptiveKeyValueRow {
                    Text("Status Container (V-07)")
                } trailing: {
                    StatusBadge(
                        text: ag.isContainerAccessible ? "Tersedia (\(ag.resolutionSource))" : "Fallback Lokal",
                        icon: ag.isContainerAccessible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        color: ag.isContainerAccessible ? PLATokens.Colors.safe : PLATokens.Colors.warning
                    )
                }

                AdaptiveKeyValueRow {
                    Text("Sinkronisasi Widget Terakhir")
                } trailing: {
                    if let ts = ag.lastWidgetSyncAt {
                        Text(ts.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Belum tersinkron")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    let res = store.runAppGroupSelfTest()
                    appGroupProbePassed = res.ok
                    appGroupProbeMessage = res.detail
                } label: {
                    Label("Uji Tulis/Baca App Group (Verifikasi V-07)", systemImage: "externaldrive.badge.checkmark")
                }

                Button {
                    store.syncWidgetSnapshot()
                    store.showToast("Snapshot WidgetKit disinkronkan ulang")
                } label: {
                    Label("Sinkronkan Ulang Widget Sekarang", systemImage: "rectangle.3.group")
                }

                if let msg = appGroupProbeMessage {
                    Label(
                        msg,
                        systemImage: (appGroupProbePassed == true) ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle((appGroupProbePassed == true) ? PLATokens.Colors.safe : PLATokens.Colors.warning)
                }
            } header: {
                Text("App Group, Share Extension & WidgetKit (V-07)")
            } footer: {
                Text("Jika App Group tidak tersedia di Apple ID gratis, Share Extension tetap mengirim hasil OCR lewat tautan pla:// dan Shortcut Share Sheet (P-05) tetap berfungsi penuh.")
            }

            // 2. Runtime Performance & Notification Queue Telemetry (SC-05, SC-06, SC-07, V-11)
            Section("Telemetri Lokal (Performa & Notifikasi)") {
                AdaptiveKeyValueRow {
                    Text("Cold Start Terakhir")
                } trailing: {
                    Text(store.diagnostics.lastColdStartMs.map { String(format: "%.0f ms", $0) } ?? "-")
                        .monospacedDigit()
                }

                AdaptiveKeyValueRow {
                    Text("Antrean Notifikasi Pending")
                } trailing: {
                    Text("\(store.pendingNotificationCount) / 64")
                        .monospacedDigit()
                        .foregroundStyle(store.pendingNotificationCount <= 64 ? PLATokens.Colors.safe : PLATokens.Colors.danger)
                }

                AdaptiveKeyValueRow {
                    Text("Drift Soak Test Notifikasi")
                } trailing: {
                    let d = store.diagnostics.notificationDriftSummary
                    Text(d.count == 0 ? "Belum ada sampel" : "\(d.count) sampel (\(String(format: "%.0f%%", d.withinOneMinutePct)) ≤ ±1 mnt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AdaptiveKeyValueRow {
                    Text("BGAppRefreshTask Terakhir")
                } trailing: {
                    if let bg = store.diagnostics.lastBackgroundRefreshDate {
                        Text(bg.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Belum pernah jalan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                AdaptiveKeyValueRow {
                    Text("Jumlah Data Lokal")
                } trailing: {
                    Text("\(store.tasks.count) tugas • \(store.transactions.count) tx • \(store.bills.count) tagihan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.refreshSystemStatusAndSyncNotifications()
                    store.showToast("Antrean notifikasi disinkronkan ulang")
                } label: {
                    Label("Sinkronkan Ulang Antrean Notifikasi Sekarang", systemImage: "bell.badge")
                }
            }

            // 3. Tester Bug Report & Sanitized Diagnostic Bundle (AC-14.3, §16.2)
            Section {
                Button {
                    let report = store.diagnostics.buildSanitizedBundle(
                        pendingNotifications: store.pendingNotificationCount,
                        sideloadStatusText: store.sideloadInfo.summaryText(today: store.today),
                        databaseReady: store.store != nil
                    )
                    UIPasteboard.general.string = report
                    copiedConfirmation = true
                    store.showToast("Paket Diagnostik disalin ke clipboard")
                } label: {
                    Label(
                        copiedConfirmation ? "Paket Diagnostik Tersalin!" : "Salin Paket Diagnostik",
                        systemImage: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text("Template Laporan Bug (4 Baris):")
                        .font(.caption.weight(.semibold))
                    Text("1) Yang dilakukan: ...\n2) Yang diharapkan: ...\n3) Yang terjadi: ...\n4) Tempel Paket Diagnostik (+ screenshot bila UI)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Kirim Masukan & Lapor Bug")
            } footer: {
                Text("Paket Diagnostik bebas dari nominal uang, judul tugas, maupun catatan pribadi Anda.")
            }

            // 4. QA Tools & UI Component Catalog (SC-07 & R-08)
            Section("Alat QA & Pratinjau Komponen") {
                NavigationLink {
                    ComponentCatalogView()
                } label: {
                    Label("Katalog Komponen UI (Light/Dark & AX3)", systemImage: "square.grid.2x2")
                }

                Button("Tambah Data Uji Cold Start (2.000 tx + 500 tugas)") {
                    showSeedConfirm = true
                }
                .foregroundStyle(PLATokens.Colors.warning)
            }

            // 5. Recent Sanitized Logs
            Section("20 Log Teknis Terakhir") {
                let logs = store.diagnostics.recentEntries(limit: 20).reversed()
                if logs.isEmpty {
                    Text("Belum ada log teknis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(logs)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(entry.level)] \(entry.category)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(entry.level == "ERROR" ? PLATokens.Colors.danger : PLATokens.Colors.accent)
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
        .navigationTitle("Diagnostik")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Tambah Data Uji Benchmark?", isPresented: $showSeedConfirm) {
            Button("Tambahkan 2.000 Transaksi", role: .destructive) {
                store.seedBenchmarkDatasetForSC07()
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Gunakan ini hanya untuk menguji performa cold start (< 2 dtk) dan scroll di perangkat uji. Backup data asli Anda terlebih dahulu jika perlu.")
        }
    }

    private var sourceLabel: String {
        switch store.sideloadInfo.source {
        case .provisioningProfile: return "embedded.mobileprovision"
        case .manualFallback: return "Catatan manual (+7 hari)"
        case .unreadable: return "Tidak terbaca"
        }
    }
}

/// Internal Design System Component Preview Catalog for visual QA without Xcode Preview (PRD Risk R-08).
struct ComponentCatalogView: View {
    var body: some View {
        List {
            Section("Status Badges (Ikon + Teks)") {
                HStack(spacing: PLATokens.Spacing.sm) {
                    StatusBadge(text: "Aman", icon: PLATokens.icon(for: BudgetHealthStatus.safe), color: PLATokens.Colors.safe)
                    StatusBadge(text: "Waspada", icon: PLATokens.icon(for: BudgetHealthStatus.warning), color: PLATokens.Colors.warning)
                    StatusBadge(text: "Melebihi", icon: PLATokens.icon(for: BudgetHealthStatus.exceeded), color: PLATokens.Colors.danger)
                }
                HStack(spacing: PLATokens.Spacing.sm) {
                    StatusBadge(text: "Tinggi", icon: PLATokens.icon(for: TaskPriority.high), color: PLATokens.Colors.danger)
                    StatusBadge(text: "Sedang", icon: PLATokens.icon(for: TaskPriority.medium), color: PLATokens.Colors.warning)
                    StatusBadge(text: "Rendah", icon: PLATokens.icon(for: TaskPriority.low), color: .secondary)
                }
            }

            Section("Tipografi Rupiah & Dynamic Type AX3") {
                AdaptiveKeyValueRow {
                    Text("Total Kekayaan Cair")
                } trailing: {
                    MoneyText(amount: 12_750_000, style: .title3.weight(.bold))
                }
                AdaptiveKeyValueRow {
                    Text("Saldo Negatif")
                } trailing: {
                    MoneyText(amount: -150_000, color: PLATokens.Colors.danger)
                }
                AdaptiveKeyValueRow {
                    Text("Nominal Disamarkan")
                } trailing: {
                    MoneyText(amount: 0, masked: true)
                }
            }

            Section("Kartu Insight & Banner") {
                InsightCardView(
                    insight: FinancialInsight(
                        ruleCode: .budgetNearLimit,
                        periodKey: "2026-11",
                        severity: .high,
                        primaryAmount: 300_000,
                        secondaryAmount: 60_000,
                        percentage: 90,
                        dayCount: 5
                    ),
                    currentFeedback: 1,
                    onFeedback: { _ in },
                    onDismiss: {}
                )

                AlertBannerRow(
                    icon: "clock.badge.exclamationmark.fill",
                    tint: PLATokens.Colors.warning,
                    title: "Masa Berlaku Aplikasi Tinggal 2 Hari",
                    message: "Buka SideStore untuk memperpanjang PLA agar tidak kedaluwarsa.",
                    actionTitle: "Refresh",
                    action: {}
                )
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
        .navigationTitle("Katalog Komponen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
