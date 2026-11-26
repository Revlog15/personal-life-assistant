import XCTest
@testable import PLACore

/// Verifies P-01 & SC-P2: >= 90% accuracy across 100 Indonesian natural-language quick-add phrases.
final class NaturalLanguageParserTests: XCTestCase {
    // Reference Thursday 2026-11-26 (weekdayISO = 4)
    private let today = LocalDate(year: 2026, month: 11, day: 26)!
    private let catKerja = PLACategory(name: "Kerja", scope: .task)
    private let catPribadi = PLACategory(name: "Pribadi", scope: .task)
    private let catBelajar = PLACategory(name: "Belajar", scope: .task)
    private let catUmum = PLACategory(name: "Umum", scope: .task)

    private var cats: [PLACategory] { [catUmum, catKerja, catPribadi, catBelajar] }

    func testPRDExamplePhraseExactMatch() {
        // PRD §18 P-01 example: "rapat besok jam 3 sore #kerja !tinggi"
        let parsed = NaturalLanguageTaskParser.parse("rapat besok jam 3 sore #kerja !tinggi", today: today, categories: cats)
        XCTAssertEqual(parsed.title, "rapat")
        XCTAssertEqual(parsed.dueDate, LocalDate(year: 2026, month: 11, day: 27))
        XCTAssertEqual(parsed.dueTimeMinutes, 15 * 60)
        XCTAssertEqual(parsed.priority, .high)
        XCTAssertTrue(parsed.priorityExplicitlySet)
        XCTAssertEqual(parsed.matchedCategoryId, catKerja.id)
        XCTAssertEqual(parsed.rawCategoryTag, "kerja")
    }

    func testEmptyInputHandledGracefully() {
        let parsed = NaturalLanguageTaskParser.parse("   ", today: today, categories: cats)
        XCTAssertEqual(parsed.title, "")
        XCTAssertNil(parsed.dueDate)
        XCTAssertNil(parsed.dueTimeMinutes)
    }

    func testOneHundredIndonesianQuickAddPhrasesMeetSCP2Target() {
        struct PhraseCase {
            let input: String
            let expectedTitle: String
            let expectedDate: LocalDate?
            let expectedTime: Int?
            let expectedPriority: TaskPriority
        }

        let d = today // 2026-11-26 Thu
        let cases: [PhraseCase] = [
            // 1-20: Relative days + time + period
            .init(input: "rapat besok jam 3 sore #kerja !tinggi", expectedTitle: "rapat", expectedDate: d.addingDays(1), expectedTime: 15 * 60, expectedPriority: .high),
            .init(input: "bayar kos besok jam 9 pagi !tinggi", expectedTitle: "bayar kos", expectedDate: d.addingDays(1), expectedTime: 9 * 60, expectedPriority: .high),
            .init(input: "kirim laporan hari ini jam 5 sore #kerja", expectedTitle: "kirim laporan", expectedDate: d, expectedTime: 17 * 60, expectedPriority: .medium),
            .init(input: "olahraga lusa jam 6 pagi #pribadi !rendah", expectedTitle: "olahraga", expectedDate: d.addingDays(2), expectedTime: 6 * 60, expectedPriority: .low),
            .init(input: "makan malam bersama hari ini jam 7 malam", expectedTitle: "makan malam bersama", expectedDate: d, expectedTime: 19 * 60, expectedPriority: .medium),
            .init(input: "standup besok pukul 09.30 #kerja", expectedTitle: "standup", expectedDate: d.addingDays(1), expectedTime: 9 * 60 + 30, expectedPriority: .medium),
            .init(input: "review PR hari ini 14:00 #kerja !urgent", expectedTitle: "review PR", expectedDate: d, expectedTime: 14 * 60, expectedPriority: .high),
            .init(input: "baca buku malam ini #belajar !santai", expectedTitle: "baca buku", expectedDate: d, expectedTime: 20 * 60, expectedPriority: .low),
            .init(input: "jogging pagi ini #pribadi", expectedTitle: "jogging", expectedDate: d, expectedTime: 9 * 60, expectedPriority: .medium),
            .init(input: "beli kopi sore ini", expectedTitle: "beli kopi", expectedDate: d, expectedTime: 16 * 60, expectedPriority: .medium),
            .init(input: "presentasi siang ini !penting", expectedTitle: "presentasi", expectedDate: d, expectedTime: 13 * 60, expectedPriority: .high),
            .init(input: "cek email besok pagi #kerja", expectedTitle: "cek email", expectedDate: d.addingDays(1), expectedTime: 9 * 60, expectedPriority: .medium),
            .init(input: "telpon ibu besok malam #pribadi", expectedTitle: "telpon ibu", expectedDate: d.addingDays(1), expectedTime: 20 * 60, expectedPriority: .medium),
            .init(input: "cuci motor lusa sore", expectedTitle: "cuci motor", expectedDate: d.addingDays(2), expectedTime: 16 * 60, expectedPriority: .medium),
            .init(input: "servis laptop 3 hari lagi #kerja", expectedTitle: "servis laptop", expectedDate: d.addingDays(3), expectedTime: nil, expectedPriority: .medium),
            .init(input: "kontrol dokter 5 hari lagi jam 10 pagi !tinggi", expectedTitle: "kontrol dokter", expectedDate: d.addingDays(5), expectedTime: 10 * 60, expectedPriority: .high),
            .init(input: "bayar pajak 10 hari lagi", expectedTitle: "bayar pajak", expectedDate: d.addingDays(10), expectedTime: nil, expectedPriority: .medium),
            .init(input: "bersihkan kamar akhir pekan #pribadi", expectedTitle: "bersihkan kamar", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: nil, expectedPriority: .medium),
            .init(input: "nonton film weekend jam 8 malam", expectedTitle: "nonton film", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: 20 * 60, expectedPriority: .medium),
            .init(input: "evaluasi sprint minggu depan #kerja", expectedTitle: "evaluasi sprint", expectedDate: d.addingDays(7), expectedTime: nil, expectedPriority: .medium),

            // 21-40: Weekdays (Senin..Minggu, depan, ini)
            .init(input: "rapat klien Senin depan jam 10 pagi #kerja", expectedTitle: "rapat klien", expectedDate: LocalDate(year: 2026, month: 11, day: 30), expectedTime: 10 * 60, expectedPriority: .medium),
            .init(input: "kumpul tugas Selasa depan jam 13.00 #belajar !tinggi", expectedTitle: "kumpul tugas", expectedDate: LocalDate(year: 2026, month: 12, day: 1), expectedTime: 13 * 60, expectedPriority: .high),
            .init(input: "latihan basket Rabu depan jam 5 sore", expectedTitle: "latihan basket", expectedDate: LocalDate(year: 2026, month: 12, day: 2), expectedTime: 17 * 60, expectedPriority: .medium),
            .init(input: "demo produk Kamis depan pukul 14.30 #kerja !tinggi", expectedTitle: "demo produk", expectedDate: LocalDate(year: 2026, month: 12, day: 3), expectedTime: 14 * 60 + 30, expectedPriority: .high),
            .init(input: "jumatan Jumat jam 11.30", expectedTitle: "jumatan", expectedDate: LocalDate(year: 2026, month: 11, day: 27), expectedTime: 11 * 60 + 30, expectedPriority: .medium),
            .init(input: "belanja bulanan Sabtu jam 9 pagi #pribadi", expectedTitle: "belanja bulanan", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: 9 * 60, expectedPriority: .medium),
            .init(input: "lari pagi Minggu jam 6.30", expectedTitle: "lari pagi", expectedDate: LocalDate(year: 2026, month: 11, day: 29), expectedTime: 6 * 60 + 30, expectedPriority: .medium),
            .init(input: "rapat tim Senin jam 08:30 #kerja", expectedTitle: "rapat tim", expectedDate: LocalDate(year: 2026, month: 11, day: 30), expectedTime: 8 * 60 + 30, expectedPriority: .medium),
            .init(input: "les bahasa Selasa jam 7 malam #belajar", expectedTitle: "les bahasa", expectedDate: LocalDate(year: 2026, month: 12, day: 1), expectedTime: 19 * 60, expectedPriority: .medium),
            .init(input: "periksa gigi Rabu jam 2 siang", expectedTitle: "periksa gigi", expectedDate: LocalDate(year: 2026, month: 12, day: 2), expectedTime: 14 * 60, expectedPriority: .medium),
            .init(input: "arisan keluarga Ahad jam 10 pagi", expectedTitle: "arisan keluarga", expectedDate: LocalDate(year: 2026, month: 11, day: 29), expectedTime: 10 * 60, expectedPriority: .medium),
            .init(input: "bayar listrik Jumat ini jam 9 pagi !tinggi", expectedTitle: "bayar listrik", expectedDate: LocalDate(year: 2026, month: 11, day: 27), expectedTime: 9 * 60, expectedPriority: .high),
            .init(input: "bikin slides Sabtu depan jam 1 siang", expectedTitle: "bikin slides", expectedDate: LocalDate(year: 2026, month: 12, day: 5), expectedTime: 13 * 60, expectedPriority: .medium),
            .init(input: "kirim paket hari Senin jam 11 pagi", expectedTitle: "kirim paket", expectedDate: LocalDate(year: 2026, month: 11, day: 30), expectedTime: 11 * 60, expectedPriority: .medium),
            .init(input: "meeting vendor hari Rabu pukul 15.00 #kerja", expectedTitle: "meeting vendor", expectedDate: LocalDate(year: 2026, month: 12, day: 2), expectedTime: 15 * 60, expectedPriority: .medium),
            .init(input: "sync tim 2 minggu lagi #kerja", expectedTitle: "sync tim", expectedDate: d.addingDays(14), expectedTime: nil, expectedPriority: .medium),
            .init(input: "audit bulanan pekan depan #kerja", expectedTitle: "audit bulanan", expectedDate: d.addingDays(7), expectedTime: nil, expectedPriority: .medium),
            .init(input: "belajar swift Jumat malam #belajar", expectedTitle: "belajar swift", expectedDate: LocalDate(year: 2026, month: 11, day: 27), expectedTime: 20 * 60, expectedPriority: .medium),
            .init(input: "rapikan berkas Sabtu sore", expectedTitle: "rapikan berkas", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: 16 * 60, expectedPriority: .medium),
            .init(input: "persiapan kuliah Minggu malam #belajar", expectedTitle: "persiapan kuliah", expectedDate: LocalDate(year: 2026, month: 11, day: 29), expectedTime: 20 * 60, expectedPriority: .medium),

            // 41-65: Explicit dates (DD MMM, DD/MM, tgl N)
            .init(input: "bayar internet 15 Des jam 9 pagi !tinggi", expectedTitle: "bayar internet", expectedDate: LocalDate(year: 2026, month: 12, day: 15), expectedTime: 9 * 60, expectedPriority: .high),
            .init(input: "ujian akhir 20 Desember jam 8 pagi #belajar !tinggi", expectedTitle: "ujian akhir", expectedDate: LocalDate(year: 2026, month: 12, day: 20), expectedTime: 8 * 60, expectedPriority: .high),
            .init(input: "liburan keluarga 25 Des", expectedTitle: "liburan keluarga", expectedDate: LocalDate(year: 2026, month: 12, day: 25), expectedTime: nil, expectedPriority: .medium),
            .init(input: "perpanjang SIM 10 Jan 2027 jam 08.00", expectedTitle: "perpanjang SIM", expectedDate: LocalDate(year: 2027, month: 1, day: 10), expectedTime: 8 * 60, expectedPriority: .medium),
            .init(input: "bayar STNK 5 Februari 2027 !tinggi", expectedTitle: "bayar STNK", expectedDate: LocalDate(year: 2027, month: 2, day: 5), expectedTime: nil, expectedPriority: .high),
            .init(input: "lapor SPT 15 Maret 2027 #pribadi", expectedTitle: "lapor SPT", expectedDate: LocalDate(year: 2027, month: 3, day: 15), expectedTime: nil, expectedPriority: .medium),
            .init(input: "beli tiket 01/12/2026 jam 10.00", expectedTitle: "beli tiket", expectedDate: LocalDate(year: 2026, month: 12, day: 1), expectedTime: 10 * 60, expectedPriority: .medium),
            .init(input: "kirim faktur 30/11 #kerja", expectedTitle: "kirim faktur", expectedDate: LocalDate(year: 2026, month: 11, day: 30), expectedTime: nil, expectedPriority: .medium),
            .init(input: "tagihan kartu kredit 18-12-2026 !tinggi", expectedTitle: "tagihan kartu kredit", expectedDate: LocalDate(year: 2026, month: 12, day: 18), expectedTime: nil, expectedPriority: .high),
            .init(input: "bayar BPJS tgl 10 !tinggi", expectedTitle: "bayar BPJS", expectedDate: LocalDate(year: 2026, month: 12, day: 10), expectedTime: nil, expectedPriority: .high),
            .init(input: "cek saldo tgl 28 jam 9 pagi", expectedTitle: "cek saldo", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: 9 * 60, expectedPriority: .medium),
            .init(input: "gajian cek slip tanggal 28", expectedTitle: "gajian cek slip", expectedDate: LocalDate(year: 2026, month: 11, day: 28), expectedTime: nil, expectedPriority: .medium),
            .init(input: "submit proposal tgl 5 Des jam 4 sore #kerja", expectedTitle: "submit proposal", expectedDate: LocalDate(year: 2026, month: 12, day: 5), expectedTime: 16 * 60, expectedPriority: .medium),
            .init(input: "ulang tahun teman 12 Des jam 7 malam", expectedTitle: "ulang tahun teman", expectedDate: LocalDate(year: 2026, month: 12, day: 12), expectedTime: 19 * 60, expectedPriority: .medium),
            .init(input: "cek garansi 14 Apr 2027", expectedTitle: "cek garansi", expectedDate: LocalDate(year: 2027, month: 4, day: 14), expectedTime: nil, expectedPriority: .medium),
            .init(input: "medical checkup 20 Mei 2027 jam 7 pagi", expectedTitle: "medical checkup", expectedDate: LocalDate(year: 2027, month: 5, day: 20), expectedTime: 7 * 60, expectedPriority: .medium),
            .init(input: "seminar teknologi 3 Jun 2027 pukul 09.00 #belajar", expectedTitle: "seminar teknologi", expectedDate: LocalDate(year: 2027, month: 6, day: 3), expectedTime: 9 * 60, expectedPriority: .medium),
            .init(input: "perpanjang domain 19 Jul 2027 !tinggi", expectedTitle: "perpanjang domain", expectedDate: LocalDate(year: 2027, month: 7, day: 19), expectedTime: nil, expectedPriority: .high),
            .init(input: "upacara 17 Agu 2027 jam 7 pagi", expectedTitle: "upacara", expectedDate: LocalDate(year: 2027, month: 8, day: 17), expectedTime: 7 * 60, expectedPriority: .medium),
            .init(input: "evaluasi Q3 30 Sep 2027 #kerja", expectedTitle: "evaluasi Q3", expectedDate: LocalDate(year: 2027, month: 9, day: 30), expectedTime: nil, expectedPriority: .medium),
            .init(input: "pameran desain 12 Okt 2027", expectedTitle: "pameran desain", expectedDate: LocalDate(year: 2027, month: 10, day: 12), expectedTime: nil, expectedPriority: .medium),
            .init(input: "renovasi rumah 1 Nov 2027", expectedTitle: "renovasi rumah", expectedDate: LocalDate(year: 2027, month: 11, day: 1), expectedTime: nil, expectedPriority: .medium),
            .init(input: "servis AC 29/11/2026 jam 10 pagi", expectedTitle: "servis AC", expectedDate: LocalDate(year: 2026, month: 11, day: 29), expectedTime: 10 * 60, expectedPriority: .medium),
            .init(input: "rapat tahunan 31/12/2026 14:00 #kerja", expectedTitle: "rapat tahunan", expectedDate: LocalDate(year: 2026, month: 12, day: 31), expectedTime: 14 * 60, expectedPriority: .medium),
            .init(input: "bayar iuran 02-12-2026", expectedTitle: "bayar iuran", expectedDate: LocalDate(year: 2026, month: 12, day: 2), expectedTime: nil, expectedPriority: .medium),

            // 66-85: Time-only (defaults to today) & 24-hour formats
            .init(input: "telpon kurir jam 11.30", expectedTitle: "telpon kurir", expectedDate: d, expectedTime: 11 * 60 + 30, expectedPriority: .medium),
            .init(input: "ambil laundry jam 4 sore", expectedTitle: "ambil laundry", expectedDate: d, expectedTime: 16 * 60, expectedPriority: .medium),
            .init(input: "kirim invoice pukul 16.45 #kerja", expectedTitle: "kirim invoice", expectedDate: d, expectedTime: 16 * 60 + 45, expectedPriority: .medium),
            .init(input: "minum vitamin jam 8 malam #pribadi", expectedTitle: "minum vitamin", expectedDate: d, expectedTime: 20 * 60, expectedPriority: .medium),
            .init(input: "deploy hotfix 21:00 #kerja !tinggi", expectedTitle: "deploy hotfix", expectedDate: d, expectedTime: 21 * 60, expectedPriority: .high),
            .init(input: "meeting 1-on-1 13.30 #kerja", expectedTitle: "meeting 1-on-1", expectedDate: d, expectedTime: 13 * 60 + 30, expectedPriority: .medium),
            .init(input: "isi bensin jam 18.00", expectedTitle: "isi bensin", expectedDate: d, expectedTime: 18 * 60, expectedPriority: .medium),
            .init(input: "beli galon jam 2 siang", expectedTitle: "beli galon", expectedDate: d, expectedTime: 14 * 60, expectedPriority: .medium),
            .init(input: "sirami tanaman jam 6 pagi !rendah", expectedTitle: "sirami tanaman", expectedDate: d, expectedTime: 6 * 60, expectedPriority: .low),
            .init(input: "latihan gitar jam 9 malam #pribadi", expectedTitle: "latihan gitar", expectedDate: d, expectedTime: 21 * 60, expectedPriority: .medium),
            .init(input: "cek oven 19.15", expectedTitle: "cek oven", expectedDate: d, expectedTime: 19 * 60 + 15, expectedPriority: .medium),
            .init(input: "upload video jam 12 siang #kerja", expectedTitle: "upload video", expectedDate: d, expectedTime: 12 * 60, expectedPriority: .medium),
            .init(input: "rapat darurat jam 1 siang !urgent", expectedTitle: "rapat darurat", expectedDate: d, expectedTime: 13 * 60, expectedPriority: .high),
            .init(input: "backup server jam 11 malam #kerja", expectedTitle: "backup server", expectedDate: d, expectedTime: 23 * 60, expectedPriority: .medium),
            .init(input: "bikin kopi 07:30", expectedTitle: "bikin kopi", expectedDate: d, expectedTime: 7 * 60 + 30, expectedPriority: .medium),
            .init(input: "jemput adik 15.45 #pribadi !tinggi", expectedTitle: "jemput adik", expectedDate: d, expectedTime: 15 * 60 + 45, expectedPriority: .high),
            .init(input: "kelas online pukul 19:30 #belajar", expectedTitle: "kelas online", expectedDate: d, expectedTime: 19 * 60 + 30, expectedPriority: .medium),
            .init(input: "cek pesanan jam 5 sore", expectedTitle: "cek pesanan", expectedDate: d, expectedTime: 17 * 60, expectedPriority: .medium),
            .init(input: "matikan lampu jam 10 malam", expectedTitle: "matikan lampu", expectedDate: d, expectedTime: 22 * 60, expectedPriority: .medium),
            .init(input: "meeting zoom 10:00 wib #kerja", expectedTitle: "meeting zoom", expectedDate: d, expectedTime: 10 * 60, expectedPriority: .medium),

            // 86-100: Anytime tasks (no date/time), mixed priority & hashtags
            .init(input: "beli kabel USB-C #pribadi !rendah", expectedTitle: "beli kabel USB-C", expectedDate: nil, expectedTime: nil, expectedPriority: .low),
            .init(input: "rapikan folder Google Drive #kerja", expectedTitle: "rapikan folder Google Drive", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "baca dokumentasi SwiftUI #belajar !sedang", expectedTitle: "baca dokumentasi SwiftUI", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "cari kado ulang tahun !penting", expectedTitle: "cari kado ulang tahun", expectedDate: nil, expectedTime: nil, expectedPriority: .high),
            .init(input: "ganti password router #umum !tinggi", expectedTitle: "ganti password router", expectedDate: nil, expectedTime: nil, expectedPriority: .high),
            .init(input: "catat ide artikel baru", expectedTitle: "catat ide artikel baru", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "cuci sepatu olahraga #pribadi !santai", expectedTitle: "cuci sepatu olahraga", expectedDate: nil, expectedTime: nil, expectedPriority: .low),
            .init(input: "riset harga monitor 27 inch", expectedTitle: "riset harga monitor 27 inch", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "update CV terbaru #kerja !normal", expectedTitle: "update CV terbaru", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "beli baterai AA #umum", expectedTitle: "beli baterai AA", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "bersihkan keyboard mekanik", expectedTitle: "bersihkan keyboard mekanik", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "tonton rekaman kuliah #belajar", expectedTitle: "tonton rekaman kuliah", expectedDate: nil, expectedTime: nil, expectedPriority: .medium),
            .init(input: "foto KTP untuk administrasi !high", expectedTitle: "foto KTP untuk administrasi", expectedDate: nil, expectedTime: nil, expectedPriority: .high),
            .init(input: "periksa ban cadangan mobil !low", expectedTitle: "periksa ban cadangan mobil", expectedDate: nil, expectedTime: nil, expectedPriority: .low),
            .init(input: "buat daftar belanja mingguan #pribadi", expectedTitle: "buat daftar belanja mingguan", expectedDate: nil, expectedTime: nil, expectedPriority: .medium)
        ]

        XCTAssertEqual(cases.count, 100)

        var correctCount = 0
        var mismatches: [String] = []
        for item in cases {
            let parsed = NaturalLanguageTaskParser.parse(item.input, today: today, categories: cats)
            let ok = parsed.title.lowercased() == item.expectedTitle.lowercased() &&
                     parsed.dueDate == item.expectedDate &&
                     parsed.dueTimeMinutes == item.expectedTime &&
                     parsed.priority == item.expectedPriority
            if ok {
                correctCount += 1
            } else {
                mismatches.append("'\(item.input)' -> got title='\(parsed.title)' date=\(String(describing: parsed.dueDate)) time=\(String(describing: parsed.dueTimeMinutes)) prio=\(parsed.priority)")
            }
        }

        let accuracy = Double(correctCount) / Double(cases.count) * 100.0
        print("SC-P2 Natural Language accuracy: \(correctCount)/100 (\(String(format: "%.1f", accuracy))%)")
        XCTAssertGreaterThanOrEqual(correctCount, 90, "SC-P2 failed (<90%): \(mismatches.joined(separator: "\n"))")
    }
}
