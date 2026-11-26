import Foundation

/// Parsed preview result of bilingual Indonesian + English natural-language quick add (PRD P-01 & SC-P2).
public struct ParsedQuickTask: Equatable, Sendable {
    public let title: String
    public let dueDate: LocalDate?
    public let dueTimeMinutes: Int?
    public let priority: TaskPriority
    public let priorityExplicitlySet: Bool
    public let matchedCategoryId: UUID?
    public let rawCategoryTag: String?

    public init(
        title: String,
        dueDate: LocalDate?,
        dueTimeMinutes: Int?,
        priority: TaskPriority,
        priorityExplicitlySet: Bool,
        matchedCategoryId: UUID?,
        rawCategoryTag: String?
    ) {
        self.title = title
        self.dueDate = dueDate
        self.dueTimeMinutes = dueTimeMinutes
        self.priority = priority
        self.priorityExplicitlySet = priorityExplicitlySet
        self.matchedCategoryId = matchedCategoryId
        self.rawCategoryTag = rawCategoryTag
    }
}

/// Deterministic bilingual Indonesian + English natural-language task parser
/// (e.g. "rapat besok jam 3 sore #kerja !tinggi" or "meeting with dimas at 3 oclock").
public enum NaturalLanguageTaskParser {
    private static let monthLookup: [String: Int] = [
        "jan": 1, "januari": 1, "january": 1,
        "feb": 2, "februari": 2, "february": 2, "peb": 2, "pebruari": 2,
        "mar": 3, "maret": 3, "march": 3,
        "apr": 4, "april": 4,
        "mei": 5, "may": 5,
        "jun": 6, "juni": 6, "june": 6,
        "jul": 7, "juli": 7, "july": 7,
        "agu": 8, "agt": 8, "agustus": 8, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "okt": 10, "oktober": 10, "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "des": 12, "desember": 12, "dec": 12, "december": 12
    ]

    private static let weekdayLookup: [String: Int] = [
        "senin": 1, "monday": 1,
        "selasa": 2, "tuesday": 2,
        "rabu": 3, "wednesday": 3,
        "kamis": 4, "thursday": 4,
        "jumat": 5, "jum'at": 5, "friday": 5,
        "sabtu": 6, "saturday": 6,
        "minggu": 7, "ahad": 7, "sunday": 7
    ]

    public static func parse(
        _ rawInput: String,
        today: LocalDate,
        categories: [PLACategory] = []
    ) -> ParsedQuickTask {
        var working = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else {
            return ParsedQuickTask(
                title: "", dueDate: nil, dueTimeMinutes: nil,
                priority: .medium, priorityExplicitlySet: false,
                matchedCategoryId: nil, rawCategoryTag: nil
            )
        }

        // 1. Priority tag (!tinggi / !urgent / !penting / !sedang / !rendah) or explicit "prioritas tinggi" / "high priority"
        var priority: TaskPriority = .medium
        var priorityExplicit = false
        if let match = firstMatch(#"(?i)(?:^|\s)!(tinggi|urgent|penting|high|sedang|normal|medium|rendah|santai|low)(?=\s|$)"#, in: working) {
            let token = substring(working, match.range(at: 1)).lowercased()
            applyPriority(token: token, priority: &priority, explicit: &priorityExplicit)
            working = removeMatch(working, match.range)
        } else if let match = firstMatch(#"(?i)\bprioritas\s+(tinggi|sedang|rendah)\b"#, in: working) {
            let token = substring(working, match.range(at: 1)).lowercased()
            applyPriority(token: token, priority: &priority, explicit: &priorityExplicit)
            working = removeMatch(working, match.range)
        } else if let match = firstMatch(#"(?i)\b(high|medium|low)\s+priority\b"#, in: working) {
            let token = substring(working, match.range(at: 1)).lowercased()
            applyPriority(token: token, priority: &priority, explicit: &priorityExplicit)
            working = removeMatch(working, match.range)
        }

        // 2. Category hashtag (#kerja, #pribadi, #belajar, #umum)
        var rawCategoryTag: String? = nil
        var matchedCategoryId: UUID? = nil
        if let match = firstMatch(#"(?i)(?:^|\s)#([a-z0-9_]+)(?=\s|$)"#, in: working) {
            let tag = substring(working, match.range(at: 1))
            rawCategoryTag = tag
            let taskCats = categories.filter { $0.scope == .task && !$0.isArchived }
            if let exact = taskCats.first(where: { $0.name.lowercased() == tag.lowercased() }) {
                matchedCategoryId = exact.id
            } else if let prefix = taskCats.first(where: { $0.name.lowercased().hasPrefix(tag.lowercased()) }) {
                matchedCategoryId = prefix.id
            }
            working = removeMatch(working, match.range)
        }

        // 3. Time extraction (Indonesian + English):
        //    3a. "jam/pukul H[:.]MM [pagi|siang|sore|malam|am|pm|wib|wita|wit]"
        //    3b. "[at] H[:.]MM o'clock/oclock [am|pm|pagi|siang|sore|malam]"
        //    3c. "[at] H[:.]MM am/pm" (e.g. "at 3 pm", "3pm", "9:30 am")
        //    3d. "at H[:.]MM" (e.g. "at 15:00", "at 3")
        //    3e. Standalone "HH:MM / HH.MM [period]"
        var parsedTime: Int? = nil
        if let match = firstMatch(#"(?i)\b(?:jam|pukul)\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*(pagi|siang|sore|malam|am|pm|wib|wita|wit))?\b"#, in: working) {
            let hourRaw = Int(substring(working, match.range(at: 1))) ?? 0
            let minRaw = match.range(at: 2).location != NSNotFound ? (Int(substring(working, match.range(at: 2))) ?? 0) : 0
            let period = match.range(at: 3).location != NSNotFound ? substring(working, match.range(at: 3)).lowercased() : nil
            if let normalized = normalizeTime(hour: hourRaw, minute: minRaw, period: period) {
                parsedTime = normalized
                working = removeMatch(working, match.range)
            }
        } else if let match = firstMatch(#"(?i)\b(?:at\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*o['’]?clock(?:\s*(am|pm|pagi|siang|sore|malam))?\b"#, in: working) {
            let hourRaw = Int(substring(working, match.range(at: 1))) ?? 0
            let minRaw = match.range(at: 2).location != NSNotFound ? (Int(substring(working, match.range(at: 2))) ?? 0) : 0
            let explicitPeriod = match.range(at: 3).location != NSNotFound ? substring(working, match.range(at: 3)).lowercased() : nil
            // Daytime convention for unqualified "at 3 o'clock": 1..6 -> PM (13:00..18:00), 7..12 -> morning/noon
            let resolvedPeriod: String? = explicitPeriod ?? ((1...6).contains(hourRaw) ? "pm" : nil)
            if let normalized = normalizeTime(hour: hourRaw, minute: minRaw, period: resolvedPeriod) {
                parsedTime = normalized
                working = removeMatch(working, match.range)
            }
        } else if let match = firstMatch(#"(?i)\b(?:at\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b"#, in: working) {
            let hourRaw = Int(substring(working, match.range(at: 1))) ?? 0
            let minRaw = match.range(at: 2).location != NSNotFound ? (Int(substring(working, match.range(at: 2))) ?? 0) : 0
            let period = substring(working, match.range(at: 3)).lowercased()
            if (1...12).contains(hourRaw), let normalized = normalizeTime(hour: hourRaw, minute: minRaw, period: period) {
                parsedTime = normalized
                working = removeMatch(working, match.range)
            }
        } else if let match = firstMatch(#"(?i)\bat\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*(pagi|siang|sore|malam|wib|wita|wit))?\b"#, in: working) {
            let hourRaw = Int(substring(working, match.range(at: 1))) ?? 0
            let minRaw = match.range(at: 2).location != NSNotFound ? (Int(substring(working, match.range(at: 2))) ?? 0) : 0
            let explicitPeriod = match.range(at: 3).location != NSNotFound ? substring(working, match.range(at: 3)).lowercased() : nil
            let hasMinutes = match.range(at: 2).location != NSNotFound
            let resolvedPeriod: String? = explicitPeriod ?? ((!hasMinutes && (1...6).contains(hourRaw)) ? "pm" : nil)
            if let normalized = normalizeTime(hour: hourRaw, minute: minRaw, period: resolvedPeriod) {
                parsedTime = normalized
                working = removeMatch(working, match.range)
            }
        } else if let match = firstMatch(#"(?i)\b(\d{1,2})[:.](\d{2})(?:\s*(pagi|siang|sore|malam|am|pm|wib|wita|wit))?\b"#, in: working) {
            let hourRaw = Int(substring(working, match.range(at: 1))) ?? 0
            let minRaw = Int(substring(working, match.range(at: 2))) ?? 0
            let period = match.range(at: 3).location != NSNotFound ? substring(working, match.range(at: 3)).lowercased() : nil
            if (0...23).contains(hourRaw), (0...59).contains(minRaw),
               let normalized = normalizeTime(hour: hourRaw, minute: minRaw, period: period) {
                parsedTime = normalized
                working = removeMatch(working, match.range)
            }
        }

        // 4. Date extraction (Indonesian + English)
        var parsedDate: LocalDate? = nil

        // 4a. "N hari lagi" / "in N days"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:(\d{1,3})\s+hari\s+lagi|in\s+(\d{1,3})\s+days?)\b"#, in: working) {
            let numStr = match.range(at: 1).location != NSNotFound ? substring(working, match.range(at: 1)) : substring(working, match.range(at: 2))
            if let delta = Int(numStr), delta >= 1 {
                parsedDate = today.addingDays(delta)
                working = removeMatch(working, match.range)
            }
        }

        // 4b. "N minggu lagi" / "in N weeks" / "minggu depan" / "pekan depan" / "next week"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:(\d{1,2})\s+(?:minggu|pekan)\s+lagi|in\s+(\d{1,2})\s+weeks?)\b"#, in: working) {
            let numStr = match.range(at: 1).location != NSNotFound ? substring(working, match.range(at: 1)) : substring(working, match.range(at: 2))
            if let weeks = Int(numStr), weeks >= 1 {
                parsedDate = today.addingDays(weeks * 7)
                working = removeMatch(working, match.range)
            }
        }
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:(?:minggu|pekan)\s+depan|next\s+week)\b"#, in: working) {
            parsedDate = today.addingDays(7)
            working = removeMatch(working, match.range)
        }

        // 4c. "akhir pekan" / "weekend"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:akhir\s+pekan|(?:this\s+)?weekend)\b"#, in: working) {
            parsedDate = RescheduleSuggester.nextWeekendDate(from: today)
            working = removeMatch(working, match.range)
        }

        // 4d. "pagi/siang/sore/malam ini" / "tonight" / "this morning/afternoon/evening"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(pagi|siang|sore|malam)\s+ini\b"#, in: working) {
            let period = substring(working, match.range(at: 1)).lowercased()
            parsedDate = today
            if parsedTime == nil {
                parsedTime = defaultMinutes(forPeriod: period)
            }
            working = removeMatch(working, match.range)
        }
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(tonight|this\s+(?:morning|afternoon|evening))\b"#, in: working) {
            let phrase = substring(working, match.range(at: 1)).lowercased()
            parsedDate = today
            if parsedTime == nil {
                if phrase.contains("morning") { parsedTime = 9 * 60 }
                else if phrase.contains("afternoon") { parsedTime = 15 * 60 }
                else if phrase.contains("evening") { parsedTime = 19 * 60 }
                else { parsedTime = 20 * 60 }
            }
            working = removeMatch(working, match.range)
        }

        // 4e. "hari ini", "besok", "lusa", "today", "tomorrow"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(hari\s+ini|besok|lusa|today|tomorrow)\b"#, in: working) {
            let token = substring(working, match.range(at: 1)).lowercased()
            if token == "besok" || token == "tomorrow" {
                parsedDate = today.addingDays(1)
            } else if token == "lusa" {
                parsedDate = today.addingDays(2)
            } else {
                parsedDate = today
            }
            working = removeMatch(working, match.range)
        }

        // 4f. Explicit DD Month [YYYY] e.g. "15 Des", "3 Januari 2027", "20 December"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:(?:tgl|tanggal|on)\s+)?(\d{1,2})\s+(januari|january|jan|februari|february|feb|pebruari|peb|maret|march|mar|april|apr|mei|may|juni|june|jun|juli|july|jul|agustus|august|agu|agt|aug|september|sept|sep|oktober|october|okt|oct|november|nov|desember|december|des|dec)(?:\s+(\d{4}))?\b"#, in: working) {
            let day = Int(substring(working, match.range(at: 1))) ?? 0
            let monthName = substring(working, match.range(at: 2)).lowercased()
            let explicitYear = match.range(at: 3).location != NSNotFound ? Int(substring(working, match.range(at: 3))) : nil
            if let month = monthLookup[monthName],
               let resolved = resolveDayMonth(day: day, month: month, explicitYear: explicitYear, today: today) {
                parsedDate = resolved
                working = removeMatch(working, match.range)
            }
        }

        // 4g. Explicit DD/MM[/YYYY] or DD-MM[-YYYY]
        if parsedDate == nil,
           let match = firstMatch(#"\b(?:(?:tgl|tanggal|on)\s+)?(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b"#, in: working) {
            let day = Int(substring(working, match.range(at: 1))) ?? 0
            let month = Int(substring(working, match.range(at: 2))) ?? 0
            var yearOpt: Int? = nil
            if match.range(at: 3).location != NSNotFound, let y = Int(substring(working, match.range(at: 3))) {
                yearOpt = y < 100 ? (2000 + y) : y
            }
            if let resolved = resolveDayMonth(day: day, month: month, explicitYear: yearOpt, today: today) {
                parsedDate = resolved
                working = removeMatch(working, match.range)
            }
        }

        // 4h. "tgl N" / "tanggal N" (day of current or next month)
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:tgl|tanggal)\s+(\d{1,2})\b"#, in: working),
           let day = Int(substring(working, match.range(at: 1))), (1...31).contains(day) {
            let thisMonthMax = LocalDate.daysInMonth(year: today.year, month: today.month)
            if day >= today.day && day <= thisMonthMax {
                parsedDate = LocalDate(year: today.year, month: today.month, day: day)
            } else {
                parsedDate = today.addingMonths(1, anchorDay: day)
            }
            working = removeMatch(working, match.range)
        }

        // 4i. Indonesian weekday names: "[hari] Senin/Selasa/... [depan|ini]"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:hari\s+)?(senin|selasa|rabu|kamis|jum'?at|sabtu|minggu|ahad)(?:\s+(depan|ini))?\b"#, in: working) {
            let dayWord = substring(working, match.range(at: 1)).lowercased()
            let modifier = match.range(at: 2).location != NSNotFound ? substring(working, match.range(at: 2)).lowercased() : nil
            if let targetWD = weekdayLookup[dayWord] {
                parsedDate = resolveWeekday(targetWeekdayISO: targetWD, modifier: modifier, today: today)
                working = removeMatch(working, match.range)
            }
        }

        // 4j. English weekday names: "[on] [next|this] Monday..Sunday"
        if parsedDate == nil,
           let match = firstMatch(#"(?i)\b(?:on\s+)?(?:(next|this)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, in: working) {
            let engMod = match.range(at: 1).location != NSNotFound ? substring(working, match.range(at: 1)).lowercased() : nil
            let dayWord = substring(working, match.range(at: 2)).lowercased()
            let mappedMod: String? = (engMod == "next") ? "depan" : (engMod == "this" ? "ini" : nil)
            if let targetWD = weekdayLookup[dayWord] {
                parsedDate = resolveWeekday(targetWeekdayISO: targetWD, modifier: mappedMod, today: today)
                working = removeMatch(working, match.range)
            }
        }

        // 5. Standalone period word ("pagi/siang/sore/malam" or "morning/afternoon/evening/night") when a date was found & time not set
        if parsedDate != nil && parsedTime == nil,
           let match = firstMatch(#"(?i)\b(pagi|siang|sore|malam|morning|afternoon|evening|night)\b"#, in: working) {
            let period = substring(working, match.range(at: 1)).lowercased()
            parsedTime = defaultMinutes(forPeriod: period)
            working = removeMatch(working, match.range)
        }

        // If user specified a time (e.g. "meeting with dimas at 3 oclock") without explicit date, default dueDate to today
        if parsedDate == nil && parsedTime != nil {
            parsedDate = today
        }

        let cleanedTitle = cleanRemainingTitle(working)
        let finalTitle = cleanedTitle.isEmpty ? rawInput.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedTitle

        return ParsedQuickTask(
            title: finalTitle,
            dueDate: parsedDate,
            dueTimeMinutes: parsedTime,
            priority: priority,
            priorityExplicitlySet: priorityExplicit,
            matchedCategoryId: matchedCategoryId,
            rawCategoryTag: rawCategoryTag
        )
    }

    private static func applyPriority(token: String, priority: inout TaskPriority, explicit: inout Bool) {
        switch token {
        case "tinggi", "urgent", "penting", "high":
            priority = .high
            explicit = true
        case "sedang", "normal", "medium":
            priority = .medium
            explicit = true
        case "rendah", "santai", "low":
            priority = .low
            explicit = true
        default:
            break
        }
    }

    private static func normalizeTime(hour: Int, minute: Int, period: String?) -> Int? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var h = hour
        if let period {
            switch period {
            case "sore", "malam":
                if (1...11).contains(h) {
                    h += 12
                } else if h == 12 && period == "malam" {
                    h = 0
                }
            case "pm":
                if (1...11).contains(h) {
                    h += 12
                }
            case "siang":
                if (1...4).contains(h) {
                    h += 12
                }
            case "pagi", "am":
                if h == 12 { h = 0 }
            default:
                break
            }
        }
        guard (0...23).contains(h) else { return nil }
        return h * 60 + minute
    }

    private static func defaultMinutes(forPeriod period: String) -> Int? {
        switch period {
        case "pagi", "morning": return 9 * 60
        case "siang": return 13 * 60
        case "sore", "afternoon": return 16 * 60
        case "evening": return 19 * 60
        case "malam", "night": return 20 * 60
        default: return nil
        }
    }

    private static func resolveDayMonth(day: Int, month: Int, explicitYear: Int?, today: LocalDate) -> LocalDate? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let y = explicitYear {
            return LocalDate(year: y, month: month, day: day)
        }
        if let candidate = LocalDate(year: today.year, month: month, day: day) {
            if candidate >= today {
                return candidate
            }
            return LocalDate(year: today.year + 1, month: month, day: day)
        }
        return LocalDate(year: today.year + 1, month: month, day: day)
    }

    private static func resolveWeekday(targetWeekdayISO: Int, modifier: String?, today: LocalDate) -> LocalDate {
        let currentWD = today.weekdayISO
        var delta = (targetWeekdayISO - currentWD + 7) % 7
        if modifier == "depan" {
            let daysUntilEndOfThisWeek = 7 - currentWD
            delta = daysUntilEndOfThisWeek + targetWeekdayISO
        } else if modifier == "ini" {
            if delta == 0 { delta = 0 }
        } else {
            if delta == 0 { delta = 7 }
        }
        return today.addingDays(delta)
    }

    private static func cleanRemainingTitle(_ raw: String) -> String {
        var s = raw
        // Strip dangling prepositions at the very end ("pada", "di", "untuk", "jam", "pukul", "at", "on", "for")
        let trailingPrep = try? NSRegularExpression(pattern: #"(?i)(?:\s+(?:pada|di|untuk|jam|pukul|tgl|tanggal|at|on|by|for))+\s*$"#)
        if let trailingPrep {
            s = trailingPrep.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        let multiSpace = try? NSRegularExpression(pattern: #"\s{2,}"#)
        if let multiSpace {
            s = multiSpace.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        return s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-;:")))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private static func removeMatch(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var copy = text
        copy.replaceSubrange(swiftRange, with: " ")
        return copy
    }
}
