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

/// Consistent tinted SF Symbol icon container giving each domain/category an instant chromatic anchor.
struct PLAIconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 34
    var iconFont: Font = .subheadline.weight(.semibold)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.16))
            Image(systemName: systemName)
                .font(iconFont)
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Committed brand-colored hero container with directional depth shadow (never flat monochrome).
struct PLAHeroCard<Content: View>: View {
    var gradient: LinearGradient = PLATokens.heroGradient
    private let content: Content

    init(gradient: LinearGradient = PLATokens.heroGradient, @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    var body: some View {
        content
            .padding(PLATokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PLATokens.Radius.lg, style: .continuous)
                    .fill(gradient)
                    .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
            )
    }
}

/// Domain-tinted quick action pill button for fast 1-tap Dashboard workflows.
struct PLAQuickActionPill: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: PLATokens.Radius.md, style: .continuous)
                    .fill(PLATokens.Colors.surface)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Live dot-formatted Indonesian Rupiah input field (`1000000` -> `1.000.000` as you type).
struct RupiahTextField: View {
    let placeholder: String
    @Binding var text: String
    var allowZero: Bool = false
    var font: Font = .title3.weight(.bold)
    var accentColor: Color = PLATokens.Colors.accent

    var body: some View {
        HStack(spacing: PLATokens.Spacing.sm) {
            Text("Rp")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField(placeholder, text: $text)
                .font(font)
                .monospacedDigit()
                .keyboardType(.numberPad)
                .onChange(of: text) { _, newValue in
                    let formatted = PLAFormatters.formatDigitsWithDots(newValue, allowZero: allowZero)
                    if formatted != newValue {
                        text = formatted
                    }
                }
                .onAppear {
                    if !text.isEmpty {
                        let formatted = PLAFormatters.formatDigitsWithDots(text, allowZero: allowZero)
                        if formatted != text {
                            text = formatted
                        }
                    }
                }

            if !text.isEmpty && !(allowZero && text == "0") {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hapus nominal")
            }
        }
    }
}

/// Non-color-only semantic badge (icon + text, WCAG AA contrast).
struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color
    var onDarkSurface: Bool = false

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(onDarkSurface ? Color.white : color)
            .padding(.horizontal, PLATokens.Spacing.sm)
            .padding(.vertical, PLATokens.Spacing.xs)
            .background(
                (onDarkSurface ? Color.white.opacity(0.20) : color.opacity(0.15)),
                in: Capsule()
            )
            .accessibilityElement(children: .combine)
    }
}

/// Tabular-numeral Rupiah label for crisp financial scanning (`Rp1.000.000`).
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

/// Reusable empty state using native iOS 17 ContentUnavailableView with domain-colored accent & clear CTA.
struct PLAEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = PLATokens.Colors.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: PLATokens.Spacing.sm) {
                PLAIconBadge(systemName: systemImage, color: tint, size: 54, iconFont: .title2.weight(.semibold))
                Text(title)
                    .font(.headline)
            }
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }
}

/// Insight card with tinted severity badge, copy, 👍/👎 feedback (SC-16), and dismiss button (AC-11.4).
struct InsightCardView: View {
    let insight: FinancialInsight
    let currentFeedback: Int?
    let onFeedback: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        let copy = PLAFormatters.insightCopy(for: insight)
        let color = PLATokens.color(for: insight.severity)

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.md) {
                PLAIconBadge(
                    systemName: PLATokens.icon(for: insight.severity),
                    color: color,
                    size: 38,
                    iconFont: .body.weight(.semibold)
                )

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
                .foregroundStyle(currentFeedback == 1 ? PLATokens.Colors.safe : .secondary)
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

/// Non-intrusive bottom toast with semantic emerald checkmark & optional Undo pill (AC-02.3: 5-second Urungkan).
struct ToastBannerView: View {
    let message: String
    let undoTitle: String?
    let onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: PLATokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.safe)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let undoTitle, let onUndo {
                Spacer(minLength: PLATokens.Spacing.sm)
                Button(undoTitle, action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(PLATokens.Colors.accent.opacity(0.14), in: Capsule())
            }
        }
        .padding(.horizontal, PLATokens.Spacing.lg)
        .padding(.vertical, PLATokens.Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PLATokens.Radius.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 5)
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
            HStack(alignment: .top, spacing: PLATokens.Spacing.md) {
                PLAIconBadge(systemName: icon, color: tint, size: 36)
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
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .controlSize(.small)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }
}

/// P-09: Personal Intelligence opt-in suggestion card (R-PER-01 & R-PER-02) with distinct Violet intelligence accent.
struct PersonalSuggestionRow: View {
    let suggestion: PersonalSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.md) {
                PLAIconBadge(systemName: iconName, color: PLATokens.Colors.violet, size: 38)
                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: PLATokens.Spacing.sm) {
                Button(acceptLabel, action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(PLATokens.Colors.violet)
                    .controlSize(.small)
                    .frame(minHeight: PLATokens.minTouchTarget)
                Button("Nanti Saja", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }

    private var iconName: String {
        switch suggestion.kind {
        case .productiveTimeBlock: return "clock.arrow.circlepath"
        case .categoryLatenessHabit: return "bell.badge.waveform.fill"
        }
    }

    private var titleText: String {
        switch suggestion.kind {
        case .productiveTimeBlock(let block, _, _):
            return "Jam Produktif: \(block.labelIndonesian)"
        case .categoryLatenessHabit(_, let name, let pct, _):
            return "\(pct)% Tugas \(name) Lewat Deadline"
        }
    }

    private var bodyText: String {
        switch suggestion.kind {
        case .productiveTimeBlock(let block, let pct, let count):
            return "\(pct)% dari \(count) tugas terakhir Anda selesai di waktu \(block.labelIndonesian). Mau jadikan pukul \(PLAFormatters.time24(block.suggestedReminderMinutes)) sebagai jam default pengingat?"
        case .categoryLatenessHabit(_, let name, let pct, let count):
            return "\(pct)% dari \(count) tugas kategori \(name) selesai melewati deadline. Tambah pengingat otomatis 1 hari lebih awal untuk kategori ini?"
        }
    }

    private var acceptLabel: String {
        switch suggestion.kind {
        case .productiveTimeBlock: return "Terapkan Jam Default"
        case .categoryLatenessHabit: return "Majukan 1 Hari"
        }
    }
}
