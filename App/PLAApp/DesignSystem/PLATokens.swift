import SwiftUI
import UIKit
import PLACore

/// Unified design system tokens (4-pt grid, semantic iOS colors, WCAG AA contrast, Light/Dark adaptive).
enum PLATokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    static let minTouchTarget: CGFloat = 44

    enum Colors {
        static let accent = Color("AccentColor")
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let safe = Color(uiColor: .systemGreen)
        static let warning = Color(uiColor: .systemOrange)
        static let danger = Color(uiColor: .systemRed)
        static let info = Color(uiColor: .systemBlue)
    }

    static func color(forToken token: String) -> Color {
        switch token.lowercased() {
        case "teal": return Colors.accent
        case "blue": return Color(uiColor: .systemBlue)
        case "green": return Color(uiColor: .systemGreen)
        case "orange": return Color(uiColor: .systemOrange)
        case "amber", "yellow": return Color(uiColor: .systemYellow)
        case "red": return Color(uiColor: .systemRed)
        case "purple": return Color(uiColor: .systemPurple)
        case "pink": return Color(uiColor: .systemPink)
        default: return Color(uiColor: .systemGray)
        }
    }

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .high: return Colors.danger
        case .medium: return Colors.warning
        case .low: return Color(uiColor: .secondaryLabel)
        }
    }

    static func icon(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle"
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
        case .safe: return "checkmark.circle.fill"
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
        case .high: return Colors.warning
        case .medium: return Color(uiColor: .systemYellow)
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
