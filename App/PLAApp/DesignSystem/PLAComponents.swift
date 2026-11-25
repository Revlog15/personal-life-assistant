import SwiftUI
import PLACore

/// Adapts between horizontal side-by-side and vertical stacking automatically for Dynamic Type up to AX3 (PRD §13.2).
struct AdaptiveKeyValueRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: PLATokens.Spacing.sm) {
                leading
                Spacer(minLength: PLATokens.Spacing.sm)
                trailing
            }
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                leading
                trailing
            }
        }
    }
}

/// Non-color-only semantic badge (icon + text, WCAG AA contrast).
struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, PLATokens.Spacing.sm)
            .padding(.vertical, PLATokens.Spacing.xs)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

/// Tabular-numeral Rupiah label for crisp financial scanning.
struct MoneyText: View {
    let amount: Int64
    var masked: Bool = false
    var style: Font = .body.weight(.semibold)
    var color: Color = .primary

    var body: some View {
        Text(masked ? PLAFormatters.maskedRupiah() : PLAFormatters.rupiah(amount))
            .font(style)
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel(masked ? "Nominal disamarkan" : PLAFormatters.rupiah(amount))
    }
}

/// Reusable empty state using native iOS 17 ContentUnavailableView with 1 clear CTA (PRD §12).
struct PLAEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }
}

/// Insight card with severity icon, copy, 👍/👎 feedback (SC-16), and dismiss button (AC-11.4).
struct InsightCardView: View {
    let insight: FinancialInsight
    let currentFeedback: Int?
    let onFeedback: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        let copy = PLAFormatters.insightCopy(for: insight)
        let color = PLATokens.color(for: insight.severity)

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                Image(systemName: PLATokens.icon(for: insight.severity))
                    .foregroundStyle(color)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(copy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(copy.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: PLATokens.Spacing.sm) {
                Text("Berguna?")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onFeedback(true)
                } label: {
                    Image(systemName: currentFeedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentFeedback == 1 ? PLATokens.Colors.accent : .secondary)
                .accessibilityLabel("Insight berguna")

                Button {
                    onFeedback(false)
                } label: {
                    Image(systemName: currentFeedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentFeedback == -1 ? PLATokens.Colors.danger : .secondary)
                .accessibilityLabel("Insight kurang berguna")

                Spacer()

                Button("Tutup", action: onDismiss)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }
}

/// Non-intrusive bottom toast with optional Undo button (AC-02.3: 5-second Urungkan).
struct ToastBannerView: View {
    let message: String
    let undoTitle: String?
    let onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: PLATokens.Spacing.md) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let undoTitle, let onUndo {
                Spacer(minLength: PLATokens.Spacing.sm)
                Button(undoTitle, action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.accent)
                    .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.horizontal, PLATokens.Spacing.lg)
        .padding(.vertical, PLATokens.Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PLATokens.Radius.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, PLATokens.Spacing.lg)
    }
}

/// Alert banner for sideload expiry (AC-14.2) or denied notifications (AC-05.4).
struct AlertBannerRow: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(tint)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }
}
