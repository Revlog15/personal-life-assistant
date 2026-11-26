import Foundation
import PLACore

/// Indonesia-first formatters (PRD §13.3): Rp1.500.000, -Rp50.000, 26 Nov 2026, Kamis, 26 November 2026, 14.30.
enum PLAFormatters {
    private static let shortMonths = [
        "", "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
        "Jul", "Agu", "Sep", "Okt", "Nov", "Des"
    ]

    private static let fullMonths = [
        "", "Januari", "Februari", "Maret", "April", "Mei", "Juni",
        "Juli", "Agustus", "September", "Oktober", "November", "Desember"
    ]

    private static let fullWeekdays = [
        "", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"
    ]

    private static let shortWeekdays = [
        "", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"
    ]

    /// Deterministic Indonesian Rupiah string independent of device locale settings (`Rp1.500.000`).
    static func rupiah(_ amount: Int64) -> String {
        let isNegative = amount < 0
        let absValue: UInt64 = amount == Int64.min ? UInt64(Int64.max) + 1 : UInt64(abs(amount))
        let grouped = groupDigits(String(absValue))
        return isNegative ? "-Rp\(grouped)" : "Rp\(grouped)"
    }

    /// Formats any integer with dot thousand separators (`2.000`, `1.000.000`).
    static func groupedInteger(_ value: Int64) -> String {
        let isNegative = value < 0
        let absValue: UInt64 = value == Int64.min ? UInt64(Int64.max) + 1 : UInt64(abs(value))
        let grouped = groupDigits(String(absValue))
        return isNegative ? "-\(grouped)" : grouped
    }

    /// Live-formats raw user input digits with Indonesian dot separators (`1000000` -> `1.000.000`),
    /// stripping non-digits and capping to 12 digits (`999.999.999.999`).
    static func formatDigitsWithDots(_ raw: String, allowZero: Bool = false) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        let strippedLeading = String(digits.drop(while: { $0 == "0" }))
        if strippedLeading.isEmpty {
            return allowZero ? "0" : ""
        }
        let capped = String(strippedLeading.prefix(12))
        return groupDigits(capped)
    }

    static func greeting(for hour: Int) -> String {
        switch hour {
        case 4..<11: return "Selamat Pagi"
        case 11..<15: return "Selamat Siang"
        case 15..<19: return "Selamat Sore"
        default: return "Selamat Malam"
        }
    }

    private static func groupDigits(_ raw: String) -> String {
        var grouped = ""
        grouped.reserveCapacity(raw.count + raw.count / 3)
        let chars = Array(raw)
        for idx in chars.indices {
            if idx > 0 && (chars.count - idx) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(chars[idx])
        }
        return grouped
    }

    static func maskedRupiah() -> String {
        "Rp••••••"
    }

    static func shortDate(_ date: LocalDate) -> String {
        let m = (1...12).contains(date.month) ? shortMonths[date.month] : "\(date.month)"
        return "\(date.day) \(m) \(date.year)"
    }

    static func fullDate(_ date: LocalDate) -> String {
        let wd = (1...7).contains(date.weekdayISO) ? fullWeekdays[date.weekdayISO] : ""
        let m = (1...12).contains(date.month) ? fullMonths[date.month] : "\(date.month)"
        return "\(wd), \(date.day) \(m) \(date.year)"
    }

    static func shortWeekday(_ weekdayISO: Int) -> String {
        (1...7).contains(weekdayISO) ? shortWeekdays[weekdayISO] : ""
    }

    static func time24(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 1439)
        let h = clamped / 60
        let m = clamped % 60
        let hs = h < 10 ? "0\(h)" : "\(h)"
        let ms = m < 10 ? "0\(m)" : "\(m)"
        return "\(hs).\(ms)"
    }

    static func dateTime(_ dt: LocalDateTime) -> String {
        "\(shortDate(dt.date)), \(time24(dt.minutesFromMidnight))"
    }

    static func relativeDayLabel(_ date: LocalDate, today: LocalDate) -> String {
        let diff = today.days(until: date)
        switch diff {
        case 0: return "Hari ini"
        case 1: return "Besok"
        case -1: return "Kemarin"
        case ..<(-1): return "Terlambat \(-diff) hari"
        default: return shortDate(date)
        }
    }

    static func periodRange(_ period: BudgetPeriod) -> String {
        "\(shortDate(period.start)) – \(shortDate(period.end))"
    }

    static func recurrenceLabel(_ rule: RecurrenceRule) -> String {
        let step = rule.interval
        switch rule.frequency {
        case .daily:
            return step == 1 ? "Harian" : "Tiap \(step) hari"
        case .weekly:
            if let mask = rule.weekdaysMask, mask != 0 {
                let names = (1...7).compactMap { wd -> String? in
                    (mask & (1 << (wd - 1))) != 0 ? shortWeekdays[wd] : nil
                }
                let prefix = step == 1 ? "Mingguan" : "Tiap \(step) minggu"
                return "\(prefix) (\(names.joined(separator: ", ")))"
            }
            return step == 1 ? "Mingguan" : "Tiap \(step) minggu"
        case .monthly:
            let base = step == 1 ? "Bulanan" : "Tiap \(step) bulan"
            if let anchor = rule.anchorDayOfMonth {
                if anchor == -1 { return "\(base) (akhir bulan)" }
                return "\(base) (tgl \(anchor))"
            }
            return base
        case .yearly:
            return step == 1 ? "Tahunan" : "Tiap \(step) tahun"
        }
    }

    static func accountTypeLabel(_ type: AccountType) -> String {
        switch type {
        case .cash: return "Tunai"
        case .bank: return "Bank"
        case .ewallet: return "E-wallet"
        }
    }

    static func soundLabel(_ soundName: String) -> String {
        switch soundName {
        case ReminderSound.plaDefault.rawValue: return "Lonceng PLA (Default)"
        case ReminderSound.plaUrgent.rawValue: return "Tegas PLA (Prioritas Tinggi)"
        case ReminderSound.plaBill.rawValue: return "Koin PLA (Tagihan)"
        case ReminderSound.plaDigest.rawValue: return "Pagi PLA (Ringkasan)"
        case ReminderSound.systemDefault.rawValue: return "Bawaan iOS"
        case ReminderSound.none.rawValue: return "Hening"
        default: return soundName
        }
    }

    /// Renders deterministic Indonesian copy matching PRD §10.1.
    static func insightCopy(for insight: FinancialInsight) -> (title: String, body: String) {
        switch insight.ruleCode {
        case .budgetExceeded:
            let over = rupiah(insight.primaryAmount ?? 0)
            return (
                "Anggaran Terlampaui",
                "Anggaran terlampaui sebesar \(over). Tunda pengeluaran non-esensial sampai periode baru."
            )

        case .budgetNearLimit:
            let pct = insight.percentage ?? 85
            let sisa = rupiah(insight.primaryAmount ?? 0)
            let daily = rupiah(insight.secondaryAmount ?? 0)
            let days = insight.dayCount ?? 1
            return (
                "Anggaran Terpakai \(pct)%",
                "Sisa anggaran bebas \(sisa) untuk \(days) hari. Batasi pengeluaran maksimal \(daily)/hari agar tidak melebihi batas bulanan."
            )

        case .forecastOverBudget:
            let forecast = rupiah(insight.primaryAmount ?? 0)
            let cut = rupiah(insight.secondaryAmount ?? 0)
            let pctOver = insight.percentage ?? 10
            let cat = insight.categoryName ?? "pengeluaran harian"
            return (
                "Proyeksi Melebihi Anggaran (+\(pctOver)%)",
                "Dengan laju saat ini, pengeluaran diperkirakan mencapai \(forecast). Pangkas \(cut)/hari, fokus pada kategori terbesar: \(cat)."
            )

        case .fastBurnPace:
            let pct = insight.percentage ?? 30
            let day = insight.dayCount ?? 5
            let total = insight.totalDays ?? 30
            return (
                "Laju Pengeluaran Lebih Cepat",
                "Pengeluaran 25%+ lebih cepat dari laju hari (\(pct)% terpakai di hari ke-\(day) dari \(total))."
            )

        case .categoryBudgetNearLimit:
            let cat = insight.categoryName ?? "Kategori"
            let pct = insight.percentage ?? 85
            let rem = rupiah(insight.primaryAmount ?? 0)
            return (
                "Anggaran \(cat) Terpakai \(pct)%",
                "Sisa batas kategori \(cat) tinggal \(rem) untuk periode ini."
            )

        case .categoryHistoricalSpike:
            let cat = insight.categoryName ?? "Kategori"
            let pct = insight.percentage ?? 30
            let diff = rupiah(insight.primaryAmount ?? 0)
            return (
                "Lonjakan di \(cat)",
                "Pengeluaran \(cat) bulan ini \(pct)% (+\(diff)) lebih tinggi dari rata-rata bulan sebelumnya."
            )

        case .categoryDominance:
            let cat = insight.categoryName ?? "Kategori"
            let pct = insight.percentage ?? 40
            return (
                "Kategori Terbesar: \(cat)",
                "\(cat) menyumbang \(pct)% dari pengeluaran harianmu bulan ini."
            )
        }
    }
}
