# Checklist QA Perangkat Fisik & Verifikasi PRD v0.2

Dokumen ini merangkum seluruh kriteria keberhasilan (`SC-01..SC-16`, `SC-P1..SC-P3`), daftar verifikasi lapangan (`V-01..V-22`), protokol soak test notifikasi, uji korpus OCR nyata, checklist sesi Mac opsional, serta evaluasi tester minggu ke-1 & ke-3 dari [PRD_v0.2.md](PRD_v0.2.md).

---

## 1. Status Otomatis yang Sudah Lulus di CI (Windows / Linux / macOS)

| Kode | Kriteria | Status CI | Bukti Terakhir |
|---|---|---|---|
| **SC-04** | Akurasi anggaran, saldo, forecast & coverage `PLACore ≥ 85%` | **LULUS (CI)** | Unit test `PLACore` (81+ tes), coverage ≥ 95% |
| **SC-06** | Batas keras ≤ 64 notifikasi lokal (`NotificationQueuePlanner`) | **LULUS (CI)** | Uji 200 kandidat + pengaman slot ke-55 |
| **SC-09 (DB)** | Migrasi SQLite v1 → v3 + fixture statis + backup pra-migrasi | **LULUS (CI)** | `MigrationV1ToV3Tests` + `Fixtures/pla_v1_initial_mvp.sqlite` |
| **SC-14 (Codec)** | Round-trip JSON SHA-256 & CSV UTF-8 BOM | **LULUS (CI)** | `BackupAndCSVTests` + uji impor backup v1 lama |
| **SC-15** | 0 panggilan jaringan (`URLSession` / `Network`) | **LULUS (Statis)** | 0 temuan di seluruh kode Swift `PLACore`, `PLAData`, `PLAApp`, & Extensions |
| **SC-P2** | Akurasi parsing NLP Bahasa Indonesia ≥ 90% (100 frasa) | **LULUS (CI)** | `NaturalLanguageParserTests` (100 frasa uji) |
| **SC-P1 (Parser)** | Akurasi parser teks OCR pada 50 transkrip struk Indonesia | **LULUS (CI)** | `ReceiptOCRParserTests` (BCA, Mandiri, GoPay, OVO, DANA, Retail) |
| **V-04 / V-13 / V-15** | Runner `macos-15` Xcode 16.4, paritas Darwin vs Linux, GRDB 6.29.3 | **LULUS (CI)** | Workflow `core-tests.yml` & `ios-build.yml` hijau |
| **NFR Ukuran IPA** | Paket `.ipa` < 15 MB + 4 `.caf` (≤ 30 dtk) + 2 `.appex` | **LULUS (CI)** | Terverifikasi otomatis di `Package Unsigned .ipa & Verify Bundle` |

---

## 2. Checklist Verifikasi Perangkat Fisik (iPhone iOS 17+ & SideStore)

Isi kolom **Hasil** (`[x]` / `[ ]`) dan **Catatan** saat menguji di iPhone fisik.

### A. Sideload, Signing & App Extensions (`V-05..V-10`, `V-16`, `V-18..V-22`)
- [ ] **`V-18` Setup Windows:** iTunes (non-Store) + `iloader` + `LocalDevVPN` berhasil memasang SideStore & pairing file.
- [ ] **`V-20` Source SideStore:** URL `apps.json` terbaca rapi di tab Sources SideStore dan menampilkan versi `2.1.0`.
- [ ] **`V-05` Signing Unsigned/Ad-Hoc IPA:** `PLAApp-2.1.0.ipa` berhasil di-sign ulang dan dibuka tanpa crash di SideStore.
- [ ] **`V-06` Kuota App ID:** Saat memilih *Keep App Extensions*, cek tab *App IDs* di SideStore (terpakai 3 App ID: `PLAApp`, `PLAShareExtension`, `PLAWidgetExtension`); refresh ulang 2× memakai ulang App ID yang sama.
- [ ] **`V-07` App Group di Akun Gratis:** Buka `Pengaturan > Diagnostik` → tap **Uji Tulis/Baca App Group (Verifikasi V-07)** → status `LULUS V-07`, dan Widget Home/Lock Screen menampilkan data nyata dari PLA.
  - *Jika V-07 gagal:* pastikan fallback `pla://ocr-draft` pada Share Extension tetap membuka layar Review Transaksi, atau uji jalur Shortcut `P-05` (*Remove App Extensions*).
- [ ] **`V-08` Shortcuts Auto-Refresh:** Otomasi jam 03.00 (`LocalDevVPN` → `Refresh All Apps`) berhasil memperpanjang sisa hari ke 7 hari selama 3 hari berturut-turut saat layar terkunci.
- [ ] **`V-09` Ganti Apple ID:** Konfirmasi Bundle ID di SideStore memakai suffix Team ID (pengingat backup JSON wajib tampil di Pengaturan & panduan).
- [ ] **`V-16` Baca Masa Berlaku Sertifikat:** `Pengaturan > Diagnostik` menampilkan tanggal kedaluwarsa dari `embedded.mobileprovision` (bukan "Tidak terbaca"). Jika tidak terbaca, uji tombol fallback manual `+7 Hari`.
- [ ] **`V-10` / `V-12` Notifikasi & Suara `.caf`:** Kirim uji notifikasi tugas biasa (`pla_default.caf`), prioritas tinggi (`pla_urgent.caf`), tagihan (`pla_bill.caf`), dan ringkasan pagi (`pla_digest.caf`) — cek bunyi di mode Normal, Silent switch, dan Focus Mode (setelah masuk *Allowed Apps*).
- [ ] **`V-11` & `V-17` Background Refresh Saat Layar Terkunci:** Amati timestamp `BGAppRefreshTask Terakhir` di layar Diagnostik selama 7 hari; pastikan 0 error `SQLITE_CANTOPEN` pada log teknis.
- [ ] **`V-19` & `V-22` Pairing & Expiry:** Catat kondisi yang membuat pairing file invalid (jika ada); uji perilaku notifikasi H-2 & H-1 sebelum masa berlaku 7 hari habis.

### B. Kecepatan Alur & Fungsional Inti (`SC-01..SC-03`, `SC-08..SC-09`, `SC-13..SC-14`, `SC-P3`)
- [ ] **`SC-01` Buat Tugas (Stopwatch, median 5×):** `≤ 3 tap` dan `≤ 10 detik` (tidak termasuk ketik judul); cek juga toast **Urungkan (5 dtk)** saat centang selesai.
- [ ] **`SC-02` Catat Pengeluaran (Stopwatch, median 5×):** `≤ 4 tap` dan `≤ 10 detik`; cek chip saran kategori otomatis setelah 2 transaksi dengan catatan sama; cek transfer antar akun tidak memengaruhi anggaran.
- [ ] **`SC-03` Tandai Tagihan Lunas:** `≤ 2 tap` dari tab Tagihan atau long-press action notifikasi; pastikan nominal variabel bisa diedit & jadwal maju ke siklus berikutnya.
- [ ] **`SC-08` 100% Offline (Mode Pesawat):** Aktifkan Mode Pesawat penuh → uji seluruh 4 tab, tambah tugas NLP, catat transaksi, simulasi What-If, target tabungan, OCR foto dari galeri, dan backup lokal ke Files.
- [ ] **`SC-09` Upgrade Tanpa Kehilangan Data:** Pasang `v1.0.0` (atau `v2.0.0`), isi data nyata (akun, transaksi, tugas, tagihan), lalu update ke `v2.1.0` via SideStore → pastikan 0 data hilang & total saldo identik 100%.
- [ ] **`SC-13` Aksesibilitas (VoiceOver & Dynamic Type AX3):**
  - Naikkan ukuran teks iOS ke **AX3** (*Settings > Accessibility > Display & Text Size > Larger Text*) → cek 4 tab + `Diagnostik > Katalog Komponen UI` (Light & Dark Mode): tidak ada teks terpotong/tumpang tindih.
  - Nyalakan **VoiceOver** → pastikan tombol ikon punya label Bahasa Indonesia & seluruh alur utama dapat dioperasikan.
- [ ] **`SC-14` Round-Trip Backup JSON & Ekspor CSV:** Ekspor JSON → impor kembali ke instalasi bersih (atau setelah reset uji) → jumlah tugas/transaksi/tagihan/tabungan & total saldo identik. Ekspor CSV → buka di Microsoft Excel Windows → huruf & koma terbaca rapi (UTF-8 BOM).
- [ ] **Keamanan Face ID (`F-12`):** Aktifkan Kunci Keuangan → cek tab Keuangan meminta Face ID, gagal 2× fallback ke Passcode perangkat, nominal di Beranda & Widget tersamarkan (`Rp••••••`), dan App Switcher menampilkan layar privasi blur.
- [ ] **`SC-P3` Siri & Shortcuts (`≤ 5 dtk`):** Jalankan `AddTaskIntent` & `LogExpenseIntent` lewat Siri/Shortcuts tanpa membuka app; pastikan data muncul otomatis saat PLA dibuka.
- [ ] **P-06 Share Extension & P-08 EventKit & P-10/P-11:**
  - Share screenshot bukti transfer dari Photos/bank → pilih **Catat ke Life Assistant** → konfirmasi layar Review Transaksi terbuka dengan data terisi.
  - Nyalakan izin Kalender read-only di Pengaturan → buka Reschedule tugas terlambat → pastikan jumlah agenda kalender ikut dihitung.
  - Buat tugas berulang mode *"Dari tanggal selesai"* dan tagihan *Masa Trial* → pastikan badge trial & pengingat H-3/H-1 muncul.

---

## 3. Protokol Uji Khusus

### A. Benchmark Cold Start & Scroll (`SC-07`)
1. Cadangkan data asli via Backup JSON terlebih dahulu (atau gunakan perangkat uji bersih).
2. Buka `Pengaturan > Diagnostik` → tap **Tambah Data Uji Cold Start (2.000 tx + 500 tugas)**.
3. Tutup paksa (*force-quit*) Life Assistant dari App Switcher.
4. Buka kembali aplikasi sebanyak **5 kali**, catat angka `Cold Start Terakhir` di `Pengaturan > Diagnostik` setiap kali buka:
   - Run 1: `____ ms` | Run 2: `____ ms` | Run 3: `____ ms` | Run 4: `____ ms` | Run 5: `____ ms`
   - **Target lulus:** p90 **< 2.000 ms** (`< 2 detik`), scroll daftar transaksi tetap mulus 60 fps.

### B. Soak Test Notifikasi 3 Hari (`SC-05`)
1. Jadwalkan ≥ 100 pengingat tersebar selama 3 hari (termasuk > 64 kandidat aktif sekaligus, jadwal malam melewati jam tenang 22.00–07.00, tugas prioritas Tinggi/Sedang/Rendah, dan tagihan).
2. Biarkan iPhone berjalan normal (termasuk kondisi layar terkunci).
3. Setelah 3 hari, buka `Pengaturan > Diagnostik` → catat metrik **Drift Soak Test Notifikasi**:
   - Jumlah sampel: `____` | Persentase dalam `±60 detik`: `____%` (**Target: ≥ 99%**)
   - Pending maksimal tercatat: `____ / 64` (**Target: selalu ≤ 64**)

### C. Korpus Uji 50 Gambar OCR Nyata (`SC-P1`)
Siapkan 50 screenshot/foto nyata dari minimal 5 aplikasi (**10 BCA**, **10 Mandiri**, **10 GoPay**, **10 OVO**, **10 DANA/QRIS/struk kertas**):
- Nominal terbaca benar: `____ / 50` (**Target: ≥ 95% / ≥ 48**)
- Tanggal terbaca benar: `____ / 50` (**Target: ≥ 90% / ≥ 45**)
- Merchant terbaca benar: `____ / 50` (**Target: ≥ 80% / ≥ 40**)
- Rata-rata waktu proses per gambar: `____ dtk` (**Target: ≤ 2 detik**)
- Verifikasi privasi (§13.4): tidak ada file gambar tersimpan di direktori temp/Documents setelah OCR selesai.

---

## 4. Checklist Sesi Mac Opsional (Maks. 2 Jam, Jika Ada Mac Xcode ≥ 15 — §5.5 & `V-01`/`V-02`)
- [ ] Cek model Mac & Xcode (`V-01`) serta dukungan debug iOS perangkat (`V-02`).
- [ ] Install build tag terbaru via Xcode langsung ke iPhone.
- [ ] **Instruments — App Launch:** rekam 3× cold start dengan 2.000 transaksi.
- [ ] **Instruments — Time Profiler:** ukur frame rate saat scroll 5.000 transaksi.
- [ ] **Instruments — Allocations & Leaks:** cek puncak memori (`< 100 MB`) & 0 leak setelah 10 menit pemakaian.
- [ ] **Accessibility Inspector:** audit 4 tab utama (kontras WCAG AA, label VoiceOver, ukuran target sentuh ≥ 44×44 pt).

---

## 5. Evaluasi 3–5 Teman Tester (`SC-10`, `SC-11`, `SC-12`, `SC-16` — §16.2)

Kirim 5 pertanyaan singkat ini di grup WhatsApp/Telegram tester pada akhir **Minggu ke-1** dan **Minggu ke-3**:
1. Berapa hari dalam seminggu terakhir kamu membuka dan memakai Life Assistant? *(Target SC-12: developer ≥ 5 hari/minggu selama 4 minggu; ≥ 50% tester aktif di minggu ke-3)*
2. Apakah pernah mengalami kendala SideStore / auto-refresh / sertifikat expired? *(Target SC-11: 0 expired selama 4 minggu)*
3. Fitur mana yang paling sering kamu pakai (Tugas, Smart Reminder, Keuangan, Tagihan, OCR Struk, Widget, atau Siri)?
4. Dari kartu Insight keuangan/kebiasaan yang muncul, kira-kira berapa persen yang terasa membantu (👍 vs 👎)? *(Target SC-16: ≥ 70% berguna)*
5. Sebutkan 1 hal yang paling mengganggu atau terasa lambat, lalu sertakan **Paket Diagnostik** jika sempat terjadi crash (`Target SC-10: ≤ 1 crash/minggu`).
