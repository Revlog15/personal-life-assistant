import SwiftUI
import UIKit
import PLACore

/// Unified design system tokens (4-pt grid, vivid domain palette, Light/Dark explicitly composed, WCAG AA contrast).
enum PLATokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 22
    }

    static let minTouchTarget: CGFloat = 44

    /// Explicitly composed Light & Dark adaptive dynamic color helper.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    enum Colors {
        // Brand anchor: Deep Emerald-Teal
        static let accent = adaptive(
            light: UIColor(red: 0.059, green: 0.463, blue: 0.431, alpha: 1),  // #0F766E
            dark: UIColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 1)    // #2DD4BF
        )

        // Composed Light & Dark surfaces (tinted cool-mint light canvas, rich deep slate dark)
        static let canvas = adaptive(
            light: UIColor(red: 0.949, green: 0.969, blue: 0.965, alpha: 1),  // #F2F7F6
            dark: UIColor(red: 0.047, green: 0.063, blue: 0.075, alpha: 1)    // #0C1013
        )
        static let surface = adaptive(
            light: UIColor.white,
            dark: UIColor(red: 0.086, green: 0.110, blue: 0.129, alpha: 1)    // #161C21
        )
        static let groupedBackground = canvas

        // Semantic & domain accents (WCAG AA on Light & Dark)
        static let safe = adaptive(
            light: UIColor(red: 0.020, green: 0.588, blue: 0.412, alpha: 1),    // #059669 Emerald
            dark: UIColor(red: 0.204, green: 0.827, blue: 0.600, alpha: 1)    // #34D399
        )
        static let warning = adaptive(
            light: UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1),  // #D97706 Amber
            dark: UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)    // #FBBF24
        )
        static let coral = adaptive(
            light: UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 1),  // #EA580C Coral-Orange
            dark: UIColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1)    // #FB923C
        )
        static let danger = adaptive(
            light: UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1),  // #DC2626 Crimson
            dark: UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1)    // #F87171
        )
        static let info = adaptive(
            light: UIColor(red: 0.008, green: 0.518, blue: 0.780, alpha: 1),  // #0284C7 Sky Blue
            dark: UIColor(red: 0.220, green: 0.741, blue: 0.973, alpha: 1)    // #38BDF8
        )
        static let indigo = adaptive(
            light: UIColor(red: 0.263, green: 0.322, blue: 0.878, alpha: 1),  // #4352E0 Cobalt Indigo (Tasks)
            dark: UIColor(red: 0.506, green: 0.549, blue: 0.973, alpha: 1)    // #818CF8
        )
        static let violet = adaptive(
            light: UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1),  // #7C3AED Violet (Savings & What-If)
            dark: UIColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 1)    // #A78BFA
        )
        static let rose = adaptive(
            light: UIColor(red: 0.859, green: 0.153, blue: 0.467, alpha: 1),  // #DB2777 Rose (Bills & Trials)
            dark: UIColor(red: 0.957, green: 0.447, blue: 0.714, alpha: 1)    // #F472B6
        )

        // Hero surface endpoints (explicitly deeper in Dark Mode so white text stays crisp)
        static let heroStart = adaptive(
            light: UIColor(red: 0.047, green: 0.400, blue: 0.376, alpha: 1),  // #0C6660
            dark: UIColor(red: 0.043, green: 0.306, blue: 0.290, alpha: 1)    // #0B4E4A
        )
        static let heroEnd = adaptive(
            light: UIColor(red: 0.059, green: 0.569, blue: 0.518, alpha: 1),  // #0F9184
            dark: UIColor(red: 0.059, green: 0.439, blue: 0.408, alpha: 1)    // #0F7068
        )
        static let violetStart = adaptive(
            light: UIColor(red: 0.357, green: 0.129, blue: 0.714, alpha: 1),  // #5B21B6
            dark: UIColor(red: 0.263, green: 0.098, blue: 0.529, alpha: 1)
        )
        static let violetEnd = adaptive(
            light: UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1),  // #7C3AED
            dark: UIColor(red: 0.388, green: 0.180, blue: 0.761, alpha: 1)
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Colors.heroStart, Colors.heroEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var savingsGradient: LinearGradient {
        LinearGradient(
            colors: [Colors.violetStart, Colors.violetEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func color(forToken token: String) -> Color {
        switch token.lowercased() {
        case "teal": return Colors.accent
        case "blue": return Colors.info
        case "indigo": return Colors.indigo
        case "green": return Colors.safe
        case "orange": return Colors.coral
        case "amber", "yellow": return Colors.warning
        case "red": return Colors.danger
        case "purple", "violet": return Colors.violet
        case "pink", "rose": return Colors.rose
        default: return Color(uiColor: .systemGray)
        }
    }

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .high: return Colors.danger
        case .medium: return Colors.warning
        case .low: return Colors.info
        }
    }

    static func icon(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle.fill"
        }
    }

    static func label(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "Tinggi"
        case .medium: return "Sedang"
        case .low: return "Rendah"
        }
    }

    static func color(for status: BudgetHealthStatus) -> Color {
        switch status {
        case .notSet: return Color(uiColor: .secondaryLabel)
        case .safe: return Colors.safe
        case .warning: return Colors.warning
        case .exceeded: return Colors.danger
        }
    }

    static func icon(for status: BudgetHealthStatus) -> String {
        switch status {
        case .notSet: return "slider.horizontal.3"
        case .safe: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .exceeded: return "xmark.octagon.fill"
        }
    }

    static func label(for status: BudgetHealthStatus) -> String {
        switch status {
        case .notSet: return "Belum diatur"
        case .safe: return "Aman"
        case .warning: return "Waspada"
        case .exceeded: return "Melebihi"
        }
    }

    static func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .critical: return Colors.danger
        case .high: return Colors.coral
        case .medium: return Colors.warning
        case .info: return Colors.info
        }
    }

    static func icon(for severity: InsightSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "gauge.with.needle.fill"
        case .info: return "lightbulb.fill"
        }
    }
}
