# Personal Life Assistant (PLA)

Asisten pribadi iOS (**minimum iOS 17.0**) yang menggabungkan **tugas & pengingat otomatis**, **tagihan berulang**, dan **keuangan pribadi** dengan analisis deterministik (rule-based) **100% lokal di perangkat** — tanpa akun, tanpa server, tanpa AI API eksternal.

Dibangun dari Windows tanpa Mac lokal: logika inti diuji lewat `PLACore` (Swift Package murni), persistensi di `PLAData` (GRDB SQLite), dan paket `.ipa` unsigned dikompilasi otomatis oleh GitHub Actions (`macos-15` + XcodeGen) untuk distribusi via **SideStore**.

## Arsitektur Modul

| Modul | Peran | Dependensi | Pengujian |
|---|---|---|---|
| `Packages/PLACore` | Domain models, `Money`, `AmountParser`, `LocalDate`/`LocalDateTime`, `RecurrenceEngine`, `ReminderPlanner`, `NotificationQueuePlanner` (64 slot), `BudgetCalculator`, `Forecaster`, `InsightEngine`, `RescheduleSuggester`, `CategorySuggester`, SHA-256 + Backup JSON/CSV codec, Repository & `Clock` protocols | Swift stdlib + Foundation (lintas platform) | Windows / Linux CI (`core-tests.yml`) / macOS CI (`≥ 85%` coverage) |
| `Packages/PLAData` | Persistensi GRDB SQLite (`v1_initial_mvp`), backup pra-migrasi otomatis, `FileProtectionType.completeUntilFirstUserAuthentication`, repositories & seed data | `PLACore`, `GRDB.swift` (6.x, MIT) | macOS CI (`ios-build.yml`) |
| `App/PLAApp` | UI SwiftUI iOS 17 (`@Observable`), Design System (Light/Dark + Dynamic Type AX3 + VoiceOver), 4 tab (Beranda, Tugas, Keuangan, Pengaturan), Face ID + passcode fallback + privacy blur, rolling 64-slot `UNUserNotificationCenter` + `BGAppRefreshTask`, sideload expiry reader, 4 suara kustom `.caf`, Diagnostik | `PLACore`, `PLAData` | Archive `.ipa` unsigned di macOS CI + uji perangkat iPhone |

## Fitur MVP (F-01 s.d. F-15)

- **Beranda (F-01):** Banner peringatan, tugas terlambat, agenda hari ini, tagihan ≤ 7 hari, ringkasan keuangan (bisa disamarkan saat terkunci), maks. 3 kartu insight, tambah cepat `+`.
- **Tugas & Pengingat (F-02 s.d. F-06):** Buat tugas ≤ 3 tap, Smart Reminder otomatis (H-7/H-3/H-1/Hari H/2 jam sebelum sesuai prioritas), tugas berulang (Harian/Mingguan/Bulanan dengan anchor tgl 29–31 & kabisat/Tahunan), antrean rolling 64 notifikasi + suara kustom `.caf` + aksi notifikasi + ringkasan pagi + jam tenang, reschedule cepat dengan saran hari paling longgar.
- **Keuangan & Tagihan (F-07 s.d. F-12):** Dompet (Cash/Bank/E-wallet) + transfer bebas distorsi anggaran (dengan biaya admin opsional), catat transaksi ≤ 4 tap + saran kategori dari histori, anggaran bulanan total & per kategori dengan tanggal siklus fleksibel (1–28), tagihan berulang (Tandai Lunas ≤ 2 tap / nominal variabel / lewati siklus), proyeksi akhir bulan & batas aman harian dengan proteksi cold start, kunci Face ID + fallback passcode + blur App Switcher.
- **Backup, Diagnostik & Onboarding (F-13 s.d. F-15):** Ekspor/pulihkan JSON ber-checksum SHA-256 (skema v2 kompatibel mundur v1) & ekspor CSV UTF-8 BOM via iOS Files, pembaca masa berlaku sertifikat `embedded.mobileprovision` + pengingat H-2/H-1, paket diagnostik aman bebas data pribadi, katalog preview komponen UI, onboarding 3 langkah yang dapat dilewati.

## Fitur Pasca-MVP (Fase 5–7, Tanpa App Extension / 1 App ID)

- **Quick Add Bahasa Natural (P-01):** Ketik *"rapat besok jam 3 sore #kerja !tinggi"* dengan pratinjau chip real-time sebelum simpan (diuji pada 100 frasa Bahasa Indonesia, SC-P2).
- **Siri Shortcuts / App Intents (P-02):** `AddTaskIntent`, `LogExpenseIntent`, dan `ScanReceiptIntent` langsung di target utama (`0` App ID tambahan).
- **Target Tabungan (P-03) & Simulasi "Bagaimana Jika" (P-04):** Migrasi SQLite `v2_savings_goal` + hitung setoran bulanan & simulasi dampak rencana pembelian tanpa mengubah saldo.
- **OCR Struk/Bukti Transfer Offline (P-05):** `Apple Vision` (`VNRecognizeTextRequest`) + parser struk Indonesia (BCA, Mandiri, GoPay, OVO, DANA, QRIS, retail) lewat PhotosPicker atau Shortcut Share Sheet; foto langsung dihapus pasca-ekstraksi.
- **Smart Rescheduling Lanjutan (P-08) & Personal Intelligence (P-09):** Skor beban harian `(Tinggi×3 + Sedang×2 + Rendah×1)` + integrasi `EventKit` read-only opsional, serta usulan jam produktif (`R-PER-01`) dan pencegahan keterlambatan kategori (`R-PER-02`) dengan konfirmasi pengguna.
- **Recurring "Dari Tanggal Selesai" (P-10) & Peringatan Akhir Masa Trial (P-11):** Migrasi SQLite `v3` untuk siklus relatif pasca-selesai dan pengingat tegas H-3 & H-1 sebelum trial langganan terdebit.

## Dokumentasi

- [PRD v0.2](docs/PRD_v0.2.md)
- [Panduan Instalasi Tester (SideStore + Shortcuts)](docs/INSTALL_TESTER.md)
- SideStore Source URL: `https://raw.githubusercontent.com/Revlog15/personal-life-assistant/main/apps.json`
