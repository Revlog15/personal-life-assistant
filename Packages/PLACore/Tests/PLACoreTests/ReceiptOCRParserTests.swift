import XCTest
@testable import PLACore

/// Verifies P-05 & SC-P1 on 50 Indonesian bank/e-wallet/QRIS/retail OCR receipt transcripts:
/// Target: Amount >= 95%, Date >= 90%, Merchant >= 80%.
final class ReceiptOCRParserTests: XCTestCase {
    struct ReceiptSample {
        let app: String
        let text: String
        let expectedAmount: Int64
        let expectedDate: LocalDate
        let expectedMerchantSubstring: String
    }

    func testFiftyIndonesianReceiptsMeetSCP1AccuracyTargets() {
        var samples: [ReceiptSample] = []

        // 10 BCA (m-BCA / myBCA / QRIS BCA) samples
        let bcaData: [(String, Int64, String, LocalDate)] = [
            ("Kopi Kenangan Sudirman", 38_000, "26/11/2026", LocalDate(year: 2026, month: 11, day: 26)!),
            ("Warung Padang Sederhana", 65_000, "25/11/2026", LocalDate(year: 2026, month: 11, day: 25)!),
            ("Tokopedia Pembayaran", 245_000, "20/11/2026", LocalDate(year: 2026, month: 11, day: 20)!),
            ("Indomaret Kemang", 42_500, "18/11/2026", LocalDate(year: 2026, month: 11, day: 18)!),
            ("Budi Santoso Kos", 1_500_000, "01/11/2026", LocalDate(year: 2026, month: 11, day: 1)!),
            ("PLN Pascabayar", 387_500, "15/11/2026", LocalDate(year: 2026, month: 11, day: 15)!),
            ("Biznet Home", 375_000, "14/11/2026", LocalDate(year: 2026, month: 11, day: 14)!),
            ("Apotek K24", 89_000, "12/11/2026", LocalDate(year: 2026, month: 11, day: 12)!),
            ("Gramedia Matraman", 155_000, "10/11/2026", LocalDate(year: 2026, month: 11, day: 10)!),
            ("Bakmi GM Plaza", 74_000, "08/11/2026", LocalDate(year: 2026, month: 11, day: 8)!)
        ]
        for (merch, amt, dateStr, expDate) in bcaData {
            let txt = """
            m-BCA
            m-Transfer : BERHASIL
            \(dateStr) 14:22:10
            Penerima: \(merch)
            No. Ref: 829104920192
            Nominal: Rp \(formatDots(amt)),00
            Biaya Admin: Rp 0,00
            Total Bayar: Rp \(formatDots(amt)),00
            """
            samples.append(ReceiptSample(app: "BCA", text: txt, expectedAmount: amt, expectedDate: expDate, expectedMerchantSubstring: merch))
        }

        // 10 Mandiri (Livin' by Mandiri) samples
        let mandiriData: [(String, Int64, String, LocalDate)] = [
            ("Alfamart Tebet", 54_000, "24 Nov 2026", LocalDate(year: 2026, month: 11, day: 24)!),
            ("Shell TB Simatupang", 120_000, "22 Nov 2026", LocalDate(year: 2026, month: 11, day: 22)!),
            ("Fore Coffee Senayan", 45_000, "21 Nov 2026", LocalDate(year: 2026, month: 11, day: 21)!),
            ("Klinik Medika", 250_000, "19 Nov 2026", LocalDate(year: 2026, month: 11, day: 19)!),
            ("Uniqlo Grand Indonesia", 399_000, "17 Nov 2026", LocalDate(year: 2026, month: 11, day: 17)!),
            ("Sate Khas Senayan", 185_000, "16 Nov 2026", LocalDate(year: 2026, month: 11, day: 16)!),
            ("Superindo Pancoran", 215_500, "13 Nov 2026", LocalDate(year: 2026, month: 11, day: 13)!),
            ("CGV Grand Indonesia", 110_000, "11 Nov 2026", LocalDate(year: 2026, month: 11, day: 11)!),
            ("Laundry Express", 48_000, "09 Nov 2026", LocalDate(year: 2026, month: 11, day: 9)!),
            ("Pertamina SPBU", 100_000, "05 Nov 2026", LocalDate(year: 2026, month: 11, day: 5)!)
        ]
        for (merch, amt, dateStr, expDate) in mandiriData {
            let txt = """
            Livin' by Mandiri
            Pembayaran Berhasil
            \(dateStr) • 18:10 WIB
            Nama Merchant
            \(merch)
            Total Transaksi
            Rp\(formatDots(amt))
            ID Transaksi: LV9981231231
            """
            samples.append(ReceiptSample(app: "Mandiri", text: txt, expectedAmount: amt, expectedDate: expDate, expectedMerchantSubstring: merch))
        }

        // 10 GoPay samples
        let gopayData: [(String, Int64, String, LocalDate)] = [
            ("GoRide Stasiun", 18_500, "26 Nov 2026", LocalDate(year: 2026, month: 11, day: 26)!),
            ("Ayam Geprek Bensu", 34_000, "25 Nov 2026", LocalDate(year: 2026, month: 11, day: 25)!),
            ("Martabak Pecenongan", 78_000, "23 Nov 2026", LocalDate(year: 2026, month: 11, day: 23)!),
            ("GoCar Bandara", 165_000, "20 Nov 2026", LocalDate(year: 2026, month: 11, day: 20)!),
            ("Janji Jiwa Toast", 41_000, "18 Nov 2026", LocalDate(year: 2026, month: 11, day: 18)!),
            ("Mixue Blok M", 22_000, "15 Nov 2026", LocalDate(year: 2026, month: 11, day: 15)!),
            ("HokBen Kuningan", 62_000, "14 Nov 2026", LocalDate(year: 2026, month: 11, day: 14)!),
            ("Solaria Mall", 88_000, "11 Nov 2026", LocalDate(year: 2026, month: 11, day: 11)!),
            ("GoSend Paket", 24_000, "07 Nov 2026", LocalDate(year: 2026, month: 11, day: 7)!),
            ("Chatime Senopati", 31_000, "04 Nov 2026", LocalDate(year: 2026, month: 11, day: 4)!)
        ]
        for (merch, amt, dateStr, expDate) in gopayData {
            let txt = """
            GoPay
            Transaksi Berhasil
            Bayar ke: \(merch)
            Tanggal: \(dateStr)
            Total Bayar
            Rp \(formatDots(amt))
            Saldo GoPay tersisa: Rp 500.000
            """
            samples.append(ReceiptSample(app: "GoPay", text: txt, expectedAmount: amt, expectedDate: expDate, expectedMerchantSubstring: merch))
        }

        // 10 OVO samples
        let ovoData: [(String, Int64, String, LocalDate)] = [
            ("GrabBike Kantor", 16_000, "26 Nov 2026", LocalDate(year: 2026, month: 11, day: 26)!),
            ("Starbucks SCBD", 68_000, "24 Nov 2026", LocalDate(year: 2026, month: 11, day: 24)!),
            ("KFC Kemang", 59_000, "21 Nov 2026", LocalDate(year: 2026, month: 11, day: 21)!),
            ("GrabFood Soto Betawi", 47_500, "19 Nov 2026", LocalDate(year: 2026, month: 11, day: 19)!),
            ("Hypermart Kemang", 192_000, "16 Nov 2026", LocalDate(year: 2026, month: 11, day: 16)!),
            ("Cinema XXI", 90_000, "13 Nov 2026", LocalDate(year: 2026, month: 11, day: 13)!),
            ("Guardian Farmasi", 73_000, "10 Nov 2026", LocalDate(year: 2026, month: 11, day: 10)!),
            ("BreadTalk", 44_000, "06 Nov 2026", LocalDate(year: 2026, month: 11, day: 6)!),
            ("Es Teler 77", 52_000, "03 Nov 2026", LocalDate(year: 2026, month: 11, day: 3)!),
            ("Ace Hardware", 135_000, "02 Nov 2026", LocalDate(year: 2026, month: 11, day: 2)!)
        ]
        for (merch, amt, dateStr, expDate) in ovoData {
            let txt = """
            OVO Cash
            Berhasil
            Merchant: \(merch)
            \(dateStr) 12:15
            Total Pembayaran Rp\(formatDots(amt))
            OVO Points: 1.500
            """
            samples.append(ReceiptSample(app: "OVO", text: txt, expectedAmount: amt, expectedDate: expDate, expectedMerchantSubstring: merch))
        }

        // 10 DANA & QRIS / Retail samples
        let danaQrisData: [(String, Int64, String, LocalDate)] = [
            ("Warteg Bahari Jaya", 22_000, "2026-11-26", LocalDate(year: 2026, month: 11, day: 26)!),
            ("Nasi Goreng Kebon Sirih", 35_000, "2026-11-25", LocalDate(year: 2026, month: 11, day: 25)!),
            ("Barberbox Menteng", 75_000, "2026-11-23", LocalDate(year: 2026, month: 11, day: 23)!),
            ("FamilyMart Thamrin", 29_500, "2026-11-21", LocalDate(year: 2026, month: 11, day: 21)!),
            ("Lawson Kuningan", 33_000, "2026-11-18", LocalDate(year: 2026, month: 11, day: 18)!),
            ("Kopi Tuku Cipete", 28_000, "15-11-2026", LocalDate(year: 2026, month: 11, day: 15)!),
            ("Mie Gacoan Bekasi", 26_500, "12-11-2026", LocalDate(year: 2026, month: 11, day: 12)!),
            ("Richeese Factory", 61_000, "09-11-2026", LocalDate(year: 2026, month: 11, day: 9)!),
            ("Toko Buah Segar", 95_000, "06-11-2026", LocalDate(year: 2026, month: 11, day: 6)!),
            ("Fotokopi Kampus", 15_000, "02-11-2026", LocalDate(year: 2026, month: 11, day: 2)!)
        ]
        for (idx, item) in danaQrisData.enumerated() {
            let (merch, amt, dateStr, expDate) = item
            let txt: String
            if idx < 5 {
                txt = """
                DANA
                Pembayaran QRIS Berhasil
                \(dateStr) 19:40
                Merchant: \(merch)
                Total Bayar: Rp \(formatDots(amt))
                """
            } else {
                // Thermal paper receipt style (no explicit "Merchant:" prefix)
                txt = """
                \(merch)
                Jl. Raya No. 10 Jakarta
                \(dateStr) 13:05
                Item Belanja       \(formatDots(amt))
                GRAND TOTAL  Rp \(formatDots(amt))
                TUNAI        Rp \(formatDots(amt + 10_000))
                KEMBALIAN    Rp 10.000
                """
            }
            samples.append(ReceiptSample(app: idx < 5 ? "DANA" : "Retail", text: txt, expectedAmount: amt, expectedDate: expDate, expectedMerchantSubstring: merch))
        }

        XCTAssertEqual(samples.count, 50)

        var amountOk = 0
        var dateOk = 0
        var merchantOk = 0

        for sample in samples {
            let parsed = ReceiptOCRParser.parse(text: sample.text)
            if parsed.amount == sample.expectedAmount { amountOk += 1 }
            if parsed.date == sample.expectedDate { dateOk += 1 }
            if let m = parsed.merchant, m.lowercased().contains(sample.expectedMerchantSubstring.lowercased()) {
                merchantOk += 1
            }
        }

        let amountPct = Double(amountOk) / 50.0 * 100.0
        let datePct = Double(dateOk) / 50.0 * 100.0
        let merchantPct = Double(merchantOk) / 50.0 * 100.0
        print("SC-P1 OCR Parser 50-receipt benchmark -> Amount: \(amountPct)%, Date: \(datePct)%, Merchant: \(merchantPct)%")

        XCTAssertGreaterThanOrEqual(amountPct, 95.0, "SC-P1 amount accuracy below 95%")
        XCTAssertGreaterThanOrEqual(datePct, 90.0, "SC-P1 date accuracy below 90%")
        XCTAssertGreaterThanOrEqual(merchantPct, 80.0, "SC-P1 merchant accuracy below 80%")
    }

    func testReceiptParserEmptyAndSourceDetection() {
        let empty = ReceiptOCRParser.parse(lines: [], fallbackDate: LocalDate(year: 2026, month: 11, day: 26)!)
        XCTAssertNil(empty.amount)
        XCTAssertEqual(empty.date, LocalDate(year: 2026, month: 11, day: 26))
        XCTAssertNil(empty.merchant)

        let bca = ReceiptOCRParser.parse(text: "myBCA\nTotal Bayar Rp 50.000\n26/11/2026\nMerchant: Toko A")
        XCTAssertEqual(bca.detectedSourceApp, "BCA")

        let gopay = ReceiptOCRParser.parse(text: "GoPay\nTotal Bayar Rp 25.000")
        XCTAssertEqual(gopay.detectedSourceApp, "GoPay")

        let ovo = ReceiptOCRParser.parse(text: "OVO Cash\nTotal Rp 30.000")
        XCTAssertEqual(ovo.detectedSourceApp, "OVO")

        let dana = ReceiptOCRParser.parse(text: "DANA Transaksi Berhasil\nTotal Rp 15.000")
        XCTAssertEqual(dana.detectedSourceApp, "DANA")
    }

    private func formatDots(_ value: Int64) -> String {
        let raw = Array(String(value))
        var out = ""
        for i in raw.indices {
            if i > 0 && (raw.count - i) % 3 == 0 { out.append(".") }
            out.append(raw[i])
        }
        return out
    }
}
