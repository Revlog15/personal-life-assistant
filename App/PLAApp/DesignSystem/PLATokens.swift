import SwiftUI
import UIKit
import PLACore

/// Unified White & Blue design system tokens with explicit Light/Dark palettes and WCAG AA verified contrast.
/// Liquid Glass chrome is restricted to floating overlays (bottom tab dock and transient banners) to maintain visual hierarchy.
enum PLATokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Deliberate 3-step radius hierarchy: 12pt controls/inputs, 20pt content cards, 24pt telemetry hero.
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }

    static let minTouchTarget: CGFloat = 44
    /// Reserved bottom padding so ScrollViews always clear the detached floating Liquid Glass tab dock.
    static let floatingDockClearance: CGFloat = 112

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    enum Colors {
        // Core neutral ground and card surfaces (White & Blue Light Mode / Midnight Slate Dark Mode)
        static let canvas = adaptive(
            light: UIColor(red: 0.961, green: 0.969, blue: 0.984, alpha: 1),  // #F5F7FB Porcelain White
            dark: UIColor(red: 0.027, green: 0.043, blue: 0.078, alpha: 1)    // #070B14 Midnight Obsidian
        )
        static let surface = adaptive(
            light: UIColor.white,                                             // #FFFFFF Pure White
            dark: UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1)    // #111827 Deep Slate
        )
        static let elevatedSurface = adaptive(
            light: UIColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1),  // #F8FAFC
            dark: UIColor(red: 0.090, green: 0.125, blue: 0.200, alpha: 1)    // #172033
        )
        static let groupedBackground = canvas

        // Crisp hairline borders and interactive input borders (WCAG 1.4.11 verified)
        static let border = adaptive(
            light: UIColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1),  // #E2E8F0
            dark: UIColor(red: 0.122, green: 0.165, blue: 0.251, alpha: 1)    // #1F2A40
        )
        static let inputBorder = adaptive(
            light: UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1),  // #64748B (4.76:1 on white)
            dark: UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1)    // #64748B (3.73:1 on #111827)
        )

        // Typography inks (WCAG AA verified >= 6.3:1)
        static let textPrimary = adaptive(
            light: UIColor(red: 0.059, green: 0.090, blue: 0.165, alpha: 1),  // #0F172A (17.85:1 on white)
            dark: UIColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1)    // #F8FAFC (16.96:1 on dark surface)
        )
        static let textSecondary = adaptive(
            light: UIColor(red: 0.278, green: 0.333, blue: 0.412, alpha: 1),  // #475569 (7.58:1 on white)
            dark: UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)    // #94A3B8 (6.92:1 on dark surface)
        )

        // Single deliberate primary accent: Royal Cobalt Blue
        static let accent = adaptive(
            light: UIColor(red: 0.114, green: 0.306, blue: 0.847, alpha: 1),  // #1D4ED8 (6.70:1 on white)
            dark: UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1)    // #60A5FA (6.98:1 on #111827)
        )
        /// Solid Royal Blue fill for primary CTA buttons and active dock pill (#FFFFFF text = 5.17:1).
        static let primaryBlue = Color(red: 0.145, green: 0.388, blue: 0.922) // #2563EB
        /// Soft ice-blue selection capsule surface (active calendar day & subtle highlight tint).
        static let softBlueTint = adaptive(
            light: UIColor(red: 0.937, green: 0.965, blue: 1.000, alpha: 1),  // #EFF6FF
            dark: UIColor(red: 0.090, green: 0.145, blue: 0.329, alpha: 1)    // #172554
        )
        static let softBlueText = adaptive(
            light: UIColor(red: 0.114, green: 0.306, blue: 0.847, alpha: 1),  // #1D4ED8 (6.16:1 on #EFF6FF)
            dark: UIColor(red: 0.576, green: 0.773, blue: 0.992, alpha: 1)    // #93C5FD (8.15:1 on #172554)
        )

        // Signature Dark Contrast Telemetry Card (echoing reference's obsidian chart anchor)
        static let obsidianCard = adaptive(
            light: UIColor(red: 0.043, green: 0.067, blue: 0.125, alpha: 1),  // #0B1120
            dark: UIColor(red: 0.055, green: 0.086, blue: 0.161, alpha: 1)    // #0E1629
        )
        static let obsidianBorder = adaptive(
            light: UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1),  // #1E293B
            dark: UIColor(red: 0.141, green: 0.196, blue: 0.302, alpha: 1)    // #24324D
        )
        static let obsidianMutedText = Color(red: 0.580, green: 0.639, blue: 0.722) // #94A3B8 (7.34:1 on #0B1120)
        static let chartLine = Color(red: 0.376, green: 0.647, blue: 0.980)         // #60A5FA (7.41:1 on #0B1120)
        static let chartLineDeep = Color(red: 0.231, green: 0.510, blue: 0.965)     // #3B82F6 (5.12:1 on #0B1120)

        // Liquid Glass dock tones (applied strictly to floating navigation dock & toast)
        static let glassTint = adaptive(
            light: UIColor(red: 0.945, green: 0.965, blue: 0.996, alpha: 0.76),
            dark: UIColor(red: 0.051, green: 0.082, blue: 0.149, alpha: 0.78)
        )
        static let glassInactiveIcon = adaptive(
            light: UIColor(red: 0.200, green: 0.255, blue: 0.333, alpha: 1),  // #334155 (8.95:1 on frosted white)
            dark: UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)    // #94A3B8 (7.11:1 on obsidian glass)
        )

        // Semantic status colors (used strictly to communicate state, never decorative sprawl)
        static let safe = adaptive(
            light: UIColor(red: 0.082, green: 0.502, blue: 0.239, alpha: 1),  // #15803D (5.02:1 on white)
            dark: UIColor(red: 0.204, green: 0.827, blue: 0.600, alpha: 1)    // #34D399 (9.23:1 on #111827)
        )
        static let warning = adaptive(
            light: UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1),  // #B45309 (5.02:1 on white)
            dark: UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)    // #FBBF24 (10.63:1 on #111827)
        )
        static let danger = adaptive(
            light: UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1),  // #DC2626 (4.83:1 on white)
            dark: UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1)    // #F87171 (6.41:1 on #111827)
        )

        // Cohesive aliases mapping legacy domain tokens into the restrained White & Blue + semantic system
        static let info = accent
        static let indigo = accent
        static let violet = accent
        static let coral = danger
        static let rose = accent

        static let heroStart = adaptive(
            light: UIColor(red: 0.067, green: 0.165, blue: 0.420, alpha: 1),  // #112A6B Deep Cobalt
            dark: UIColor(red: 0.055, green: 0.118, blue: 0.275, alpha: 1)    // #0E1E46
        )
        static let heroEnd = adaptive(
            light: UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1),  // #2563EB Royal Blue
            dark: UIColor(red: 0.114, green: 0.306, blue: 0.847, alpha: 1)    // #1D4ED8
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
        heroGradient
    }

    /// Maps stored category/account color tokens into the restrained Blue + Neutral + Semantic palette.
    static func color(forToken token: String) -> Color {
        switch token.lowercased() {
        case "green": return Colors.safe
        case "amber", "yellow", "orange": return Colors.warning
        case "red": return Colors.danger
        case "teal", "blue", "indigo", "purple", "violet", "pink", "rose":
            return Colors.accent
        default:
            return Colors.textSecondary
        }
    }

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .high: return Colors.danger
        case .medium: return Colors.warning
        case .low: return Colors.accent
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
        case .notSet: return Colors.textSecondary
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
        case .high: return Colors.danger
        case .medium: return Colors.warning
        case .info: return Colors.accent
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
