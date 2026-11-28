import SwiftUI
import PLACore

// MARK: - Core Flat Content Surfaces & Layout Primitives

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

/// Calm flat content surface (pure white on soft porcelain canvas in Light Mode; deep slate with hairline rim in Dark Mode).
/// Never nests inside another card; relies on clean canvas contrast rather than noisy borders.
struct PLACard<Content: View>: View {
    var padding: CGFloat = PLATokens.Spacing.lg
    var cornerRadius: CGFloat = PLATokens.Radius.lg
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        padding: CGFloat = PLATokens.Spacing.lg,
        cornerRadius: CGFloat = PLATokens.Radius.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PLATokens.Colors.surface)
            )
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(PLATokens.Colors.hairline, lineWidth: 0.75)
                }
            }
    }
}

/// Single clean surface grouping related list rows with subtle inset hairlines (eliminates border-per-row card noise).
struct PLAGroupList<Content: View>: View {
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, PLATokens.Spacing.lg)
        .padding(.vertical, PLATokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PLATokens.Radius.lg, style: .continuous)
                .fill(PLATokens.Colors.surface)
        )
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: PLATokens.Radius.lg, style: .continuous)
                    .stroke(PLATokens.Colors.hairline, lineWidth: 0.75)
            }
        }
    }
}

/// Delicate 0.5pt inset separator between grouped rows inside `PLAGroupList`.
struct PLAInsetDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(PLATokens.Colors.hairline)
            .frame(height: 0.75)
            .padding(.leading, leadingInset)
    }
}

/// Clean section heading without eyebrows or kickers; optional trailing action meets 44pt tap height.
struct PLASectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
            Spacer(minLength: PLATokens.Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.accent)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
    }
}

/// Consistent top screen header shared across all 4 tabs (single bold title, zero eyebrow clutter, optional trailing controls).
struct PLAScreenHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PLATokens.Spacing.sm) {
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
            Spacer(minLength: PLATokens.Spacing.sm)
            trailing
        }
        .padding(.top, PLATokens.Spacing.xs)
    }
}

// MARK: - Liquid Glass Chrome (Floating Dock, Translucent Segment Capsule & Header Pill Controls)

/// Reusable Liquid Glass capsule background modifier (iOS 17+ native `.ultraThinMaterial` + specular white rim).
private struct PLALiquidGlassChrome: ViewModifier {
    var elevated: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .background(PLATokens.Colors.glassTint, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.28 : 0.92),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: elevated ? Color.black.opacity(colorScheme == .dark ? 0.42 : 0.12) : .clear,
                radius: elevated ? 18 : 0,
                x: 0,
                y: elevated ? 8 : 0
            )
    }
}

/// Compact circular Liquid Glass action button for top bar controls (44x44pt minimum touch target).
struct PLALiquidGlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
                .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                .modifier(PLALiquidGlassChrome(elevated: false))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Full-width translucent Liquid Glass segmented capsule for <=4 equal options (fits 1 screen with zero horizontal scrolling).
struct PLAGlassSegmentBar<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let active = selection == option
                Button {
                    if reduceMotion {
                        selection = option
                    } else {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            selection = option
                        }
                    }
                } label: {
                    Text(title(option))
                        .font(.caption.weight(active ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(active ? Color.white : PLATokens.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if active {
                                Capsule()
                                    .fill(PLATokens.Colors.primaryBlue)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .modifier(PLALiquidGlassChrome(elevated: false))
    }
}

/// Primary full-width Royal Blue pill CTA button (meets WCAG AA 5.17:1 contrast and >= 50pt height).
struct PLAPrimaryPillButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PLATokens.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule()
                    .fill(PLATokens.Colors.primaryBlue)
            )
            .opacity(isDisabled ? 0.48 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// Detached floating Liquid Glass bottom dock with clear labeled icons on all 4 destinations (`>= 48pt` tap targets).
struct PLAFloatingGlassTabBar: View {
    @Binding var selectedTab: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct TabItem: Identifiable {
        let tab: AppTab
        let title: String
        let icon: String
        let activeIcon: String
        var id: Int { tab.rawValue }
    }

    private let items: [TabItem] = [
        TabItem(tab: .dashboard, title: "Beranda", icon: "house", activeIcon: "house.fill"),
        TabItem(tab: .tasks, title: "Tugas", icon: "checklist", activeIcon: "checklist"),
        TabItem(tab: .finance, title: "Keuangan", icon: "wallet.pass", activeIcon: "wallet.pass.fill"),
        TabItem(tab: .settings, title: "Setelan", icon: "gearshape", activeIcon: "gearshape.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = selectedTab == item.tab
                Button {
                    if reduceMotion {
                        selectedTab = item.tab
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            selectedTab = item.tab
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? item.activeIcon : item.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.white : PLATokens.Colors.glassInactiveIcon)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(PLATokens.Colors.primaryBlue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title == "Setelan" ? "Pengaturan" : item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .modifier(PLALiquidGlassChrome(elevated: true))
        .padding(.horizontal, PLATokens.Spacing.lg)
        .padding(.bottom, PLATokens.Spacing.sm)
    }
}

// MARK: - Signature Dark Obsidian Telemetry Chart Hero Card

enum SpendingChartRange: Int, CaseIterable, Identifiable {
    case sevenDays = 0
    case fourteenDays = 1
    case cycle = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .sevenDays: return "7 Hari"
        case .fourteenDays: return "14 Hari"
        case .cycle: return "Siklus"
        }
    }
}

/// High-contrast obsidian telemetry card with timeframe pills, smooth blue trend curve, tick ruler, and optional compact footer metrics.
struct PLAChartHeroCard: View {
    let title: String
    let subtitle: String
    let totalAmount: Int64
    let points: [PLADailyMetricPoint]
    @Binding var selectedRange: SpendingChartRange
    var status: BudgetHealthStatus? = nil
    var showStatusBadge: Bool = true
    var footerLeftLabel: String? = nil
    var footerLeftValue: String? = nil
    var footerRightLabel: String? = nil
    var footerRightValue: String? = nil
    var isMasked: Bool = false
    var onUnlock: (() -> Void)? = nil

    @State private var inspectedIndex: Int? = nil

    private var hasAnyData: Bool {
        points.contains { $0.amount > 0 }
    }

    private var activeIndex: Int? {
        guard !points.isEmpty else { return nil }
        if let idx = inspectedIndex, points.indices.contains(idx) {
            return idx
        }
        return points.indices.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
            // Header row
            HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.obsidianMutedText)
                    if isMasked {
                        Text(PLAFormatters.maskedRupiah())
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    } else if let idx = inspectedIndex, points.indices.contains(idx) {
                        Text(PLAFormatters.rupiah(points[idx].amount))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    } else {
                        Text(PLAFormatters.rupiah(totalAmount))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                    Text(headerCaption)
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.obsidianMutedText)
                }

                Spacer(minLength: PLATokens.Spacing.sm)

                if isMasked, let onUnlock {
                    Button(action: onUnlock) {
                        Label("Buka", systemImage: "faceid")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.obsidianCard)
                            .padding(.horizontal, 14)
                            .frame(minHeight: PLATokens.minTouchTarget)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Buka data keuangan dengan Face ID")
                } else if showStatusBadge, let status {
                    StatusBadge(
                        text: PLATokens.label(for: status),
                        icon: PLATokens.icon(for: status),
                        color: PLATokens.color(for: status),
                        onDarkSurface: true
                    )
                }
            }

            // Segmented timeframe selector pills
            HStack(spacing: PLATokens.Spacing.xs) {
                ForEach(SpendingChartRange.allCases) { range in
                    let active = selectedRange == range
                    Button {
                        selectedRange = range
                        inspectedIndex = nil
                    } label: {
                        Text(range.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? PLATokens.Colors.obsidianCard : PLATokens.Colors.obsidianMutedText)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background {
                                if active {
                                    Capsule().fill(Color.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())

            // Plot body
            if isMasked {
                lockedPlaceholder
            } else if !hasAnyData {
                emptyChartPlaceholder
            } else {
                smoothCurvePlot
            }

            // Bottom tick ruler
            if !isMasked && !points.isEmpty {
                tickRuler
            }

            // Optional integrated compact 2-column summary strip (avoids redundant cards underneath)
            if !isMasked, let leftLabel = footerLeftLabel, let leftValue = footerLeftValue {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.75)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leftLabel)
                            .font(.caption2)
                            .foregroundStyle(PLATokens.Colors.obsidianMutedText)
                        Text(leftValue)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                    Spacer(minLength: PLATokens.Spacing.sm)
                    if let rightLabel = footerRightLabel, let rightValue = footerRightValue {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(rightLabel)
                                .font(.caption2)
                                .foregroundStyle(PLATokens.Colors.obsidianMutedText)
                            Text(rightValue)
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(PLATokens.Colors.chartLine)
                        }
                    }
                }
            }
        }
        .padding(PLATokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PLATokens.Radius.xl, style: .continuous)
                .fill(PLATokens.Colors.obsidianCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PLATokens.Radius.xl, style: .continuous)
                .stroke(PLATokens.Colors.obsidianBorder, lineWidth: 1)
        )
    }

    private var headerCaption: String {
        if isMasked {
            return "Nominal dan grafik disamarkan saat terkunci"
        }
        if let idx = inspectedIndex, points.indices.contains(idx) {
            return "Dipilih: \(PLAFormatters.fullDate(points[idx].date))"
        }
        return subtitle
    }

    private var lockedPlaceholder: some View {
        HStack(spacing: PLATokens.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(PLATokens.Colors.chartLine)
            Text("Autentikasi untuk melihat grafik tren pengeluaran harian.")
                .font(.caption)
                .foregroundStyle(PLATokens.Colors.obsidianMutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    }

    private var emptyChartPlaceholder: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            Rectangle()
                .fill(PLATokens.Colors.chartLine.opacity(0.35))
                .frame(height: 2)
                .padding(.top, 22)
            Text("Belum ada pengeluaran tercatat pada rentang \(selectedRange.label.lowercased()).")
                .font(.caption)
                .foregroundStyle(PLATokens.Colors.obsidianMutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    }

    private var smoothCurvePlot: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = max(points.map(\.amount).max() ?? 1, 1)
            let coords = chartCoordinates(width: w, height: h, maxVal: maxVal)
            let linePath = smoothPath(through: coords)
            let fillPath = areaPath(linePath: linePath, coords: coords, height: h)

            ZStack(alignment: .topLeading) {
                fillPath
                    .fill(
                        LinearGradient(
                            colors: [
                                PLATokens.Colors.chartLineDeep.opacity(0.42),
                                PLATokens.Colors.chartLineDeep.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath
                    .stroke(
                        PLATokens.Colors.chartLine,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                    )

                if let idx = activeIndex, coords.indices.contains(idx) {
                    let pt = coords[idx]
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: pt.y))
                        p.addLine(to: CGPoint(x: pt.x, y: h))
                    }
                    .stroke(PLATokens.Colors.chartLine.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Circle()
                        .fill(PLATokens.Colors.chartLine.opacity(0.28))
                        .frame(width: 22, height: 22)
                        .position(pt)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(PLATokens.Colors.primaryBlue, lineWidth: 2.5)
                        )
                        .position(pt)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard points.count > 1, w > 0 else { return }
                        let ratio = min(max(value.location.x / w, 0), 1)
                        let idx = min(max(Int((ratio * CGFloat(points.count - 1)).rounded()), 0), points.count - 1)
                        inspectedIndex = (inspectedIndex == idx) ? nil : idx
                    }
            )
        }
        .frame(height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), total \(PLAFormatters.rupiah(totalAmount))")
    }

    private var tickRuler: some View {
        let labelIndices = sampledLabelIndices(count: points.count)
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<25, id: \.self) { tick in
                    Rectangle()
                        .fill(tick % 6 == 0 ? Color.white.opacity(0.55) : Color.white.opacity(0.20))
                        .frame(width: 1, height: tick % 6 == 0 ? 9 : 4)
                    if tick < 24 {
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack {
                ForEach(labelIndices, id: \.self) { idx in
                    Text(points[idx].axisLabel)
                        .font(.caption2.weight(idx == activeIndex ? .bold : .medium))
                        .foregroundStyle(idx == activeIndex ? Color.white : PLATokens.Colors.obsidianMutedText)
                        .monospacedDigit()
                    if idx != labelIndices.last {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func sampledLabelIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 7 {
            return Array(0..<count)
        }
        let step = max(1, (count - 1) / 4)
        var out: [Int] = []
        var i = 0
        while i < count - 1 {
            out.append(i)
            i += step
        }
        if out.last != count - 1 {
            out.append(count - 1)
        }
        return out
    }

    private func chartCoordinates(width: CGFloat, height: CGFloat, maxVal: Int64) -> [CGPoint] {
        guard points.count > 1 else {
            return [CGPoint(x: width / 2, y: height * 0.5)]
        }
        let topPad: CGFloat = 12
        let bottomPad: CGFloat = 8
        let usableH = max(height - topPad - bottomPad, 1)
        let stepX = width / CGFloat(points.count - 1)

        return points.enumerated().map { idx, pt in
            let norm = CGFloat(Double(pt.amount) / Double(maxVal))
            let x = CGFloat(idx) * stepX
            let y = topPad + usableH * (1 - norm)
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }

        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let midX = (prev.x + curr.x) / 2
            path.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        return path
    }

    private func areaPath(linePath: Path, coords: [CGPoint], height: CGFloat) -> Path {
        guard let first = coords.first, let last = coords.last else { return Path() }
        var area = linePath
        area.addLine(to: CGPoint(x: last.x, y: height))
        area.addLine(to: CGPoint(x: first.x, y: height))
        area.closeSubpath()
        return area
    }
}

// MARK: - Reference-Inspired Rings, Flat Week Strip Calendar & Breakdown Bars

/// Single day column with circular completion ring and weekday letter.
struct PLAMiniRingDayColumn: View {
    let point: PLADailyRingPoint

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(PLATokens.Colors.hairline, lineWidth: 3)
                if point.totalCount > 0 {
                    Circle()
                        .trim(from: 0, to: min(max(point.progress, 0.08), 1))
                        .stroke(
                            point.progress >= 1 ? PLATokens.Colors.safe : PLATokens.Colors.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                if point.totalCount > 0 && point.completedCount == point.totalCount {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PLATokens.Colors.safe)
                } else if point.totalCount > 0 {
                    Text("\(point.completedCount)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                }
            }
            .frame(width: 30, height: 30)

            Text(point.letter)
                .font(.caption2.weight(point.isToday ? .bold : .medium))
                .foregroundStyle(point.isToday ? PLATokens.Colors.accent : PLATokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PLAFormatters.shortDayMonth(point.date)), \(point.completedCount) dari \(point.totalCount) tugas selesai")
    }
}

/// Full monthly calendar grid (7 columns Mon-Sun) with crisp per-day indicator dots for scheduled tasks and bills.
/// Displayed exclusively on the Jadwal tab; all tap targets meet >= 44x44pt.
struct PLAMonthCalendarView: View {
    @Binding var selectedDate: LocalDate
    let today: LocalDate
    let markers: [LocalDate: PLACalendarDayMarker]

    private let weekdayLabels = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var monthCells: [LocalDate?] {
        guard let firstDay = LocalDate(year: selectedDate.year, month: selectedDate.month, day: 1) else {
            return []
        }
        let leadingBlanks = max(0, firstDay.weekdayISO - 1) // Monday = 1 -> 0 blanks
        let daysInMonth = LocalDate.daysInMonth(year: selectedDate.year, month: selectedDate.month)

        var cells: [LocalDate?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth {
            cells.append(LocalDate(year: selectedDate.year, month: selectedDate.month, day: day))
        }
        return cells
    }

    var body: some View {
        PLACard(padding: PLATokens.Spacing.md, cornerRadius: PLATokens.Radius.lg) {
            VStack(spacing: PLATokens.Spacing.sm) {
                // Month header + Today shortcut + Prev/Next month arrows (44x44pt)
                HStack(spacing: PLATokens.Spacing.xs) {
                    Text(PLAFormatters.monthYear(selectedDate))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)

                    Spacer()

                    if selectedDate != today {
                        Button("Hari Ini") {
                            selectedDate = today
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: PLATokens.minTouchTarget)
                        .buttonStyle(.plain)
                    }

                    Button {
                        selectedDate = selectedDate.addingMonths(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bulan sebelumnya")

                    Button {
                        selectedDate = selectedDate.addingMonths(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bulan berikutnya")
                }

                // Weekday headers (Sen..Min)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Full month day cells with indicator dots
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(monthCells.enumerated()), id: \.offset) { _, maybeDate in
                        if let date = maybeDate {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ date: LocalDate) -> some View {
        let isSelected = date == selectedDate
        let isToday = date == today
        let marker = markers[date]
        let dotColors = resolveDotColors(marker: marker, isSelected: isSelected)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(date.day)")
                    .font(.subheadline.weight(isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected
                        ? Color.white
                        : (isToday ? PLATokens.Colors.softBlueText : PLATokens.Colors.textPrimary)
                    )

                HStack(spacing: 3) {
                    if dotColors.isEmpty {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4.5, height: 4.5)
                    } else {
                        ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: 4.5, height: 4.5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PLATokens.Colors.primaryBlue)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PLATokens.Colors.softBlueTint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, marker: marker))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func resolveDotColors(marker: PLACalendarDayMarker?, isSelected: Bool) -> [Color] {
        guard let marker else { return [] }
        var colors: [Color] = []
        if marker.hasUrgentOrOverdue {
            colors.append(isSelected ? Color.white : PLATokens.Colors.danger)
        }
        if marker.taskCount > (marker.hasUrgentOrOverdue ? 1 : 0) {
            colors.append(isSelected ? Color.white.opacity(0.92) : PLATokens.Colors.accent)
        }
        if marker.hasBillDue {
            colors.append(isSelected ? Color.white.opacity(0.75) : PLATokens.Colors.warning)
        }
        return Array(colors.prefix(3))
    }

    private func accessibilityLabel(for date: LocalDate, marker: PLACalendarDayMarker?) -> String {
        var parts = [PLAFormatters.fullDate(date)]
        if let marker {
            if marker.taskCount > 0 { parts.append("\(marker.taskCount) tugas") }
            if marker.hasBillDue { parts.append("ada tagihan") }
        }
        return parts.joined(separator: ", ")
    }
}

/// Actionable schedule conflict warning banner showing the colliding event, free time ranges, and 1-tap free slot pills.
struct PLAScheduleConflictBanner: View {
    let report: ScheduleConflictReport
    let onSelectFreeTime: (Int) -> Void

    private var conflictDescription: String {
        let items = report.conflictingSlots.prefix(2).map { slot -> String in
            let source = slot.isCalendarEvent ? " (Kalender)" : ""
            return "\"\(slot.title)\"\(source) pukul \(PLAFormatters.time24(slot.startMinutes)) - \(PLAFormatters.time24(slot.endMinutes))"
        }
        let joined = items.joined(separator: " dan ")
        return "Di \(PLAFormatters.shortDate(report.date)) kamu sudah ada \(joined)."
    }

    private var freeRangesText: String {
        if report.freeWindows.isEmpty {
            return "Jadwal hari ini penuh. Pertimbangkan geser ke hari lain."
        }
        let ranges = report.freeWindows.prefix(3).map {
            "\(PLAFormatters.time24($0.startMinutes)) - \(PLAFormatters.time24($0.endMinutes))"
        }
        return "Kosong pada: \(ranges.joined(separator: ", "))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.warning)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Jadwal Bentrok")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PLATokens.Colors.warning)
                    Text(conflictDescription)
                        .font(.footnote)
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(freeRangesText)
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !report.suggestedStartMinutes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pindah ke jam kosong:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PLATokens.Spacing.xs) {
                            ForEach(report.suggestedStartMinutes, id: \.self) { mins in
                                Button {
                                    onSelectFreeTime(mins)
                                } label: {
                                    Text(PLAFormatters.time24(mins))
                                        .font(.caption.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(PLATokens.Colors.softBlueText)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: PLATokens.minTouchTarget)
                                        .background(PLATokens.Colors.softBlueTint, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Pindah ke jam kosong pukul \(PLAFormatters.time24(mins))")
                            }
                        }
                    }
                }
            }
        }
        .padding(PLATokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PLATokens.Radius.md, style: .continuous)
                .fill(PLATokens.Colors.warning.opacity(0.10))
        )
    }
}

/// Horizontal category/budget/savings breakdown row (modeled on reference macro bars).
struct PLABreakdownBarRow: View {
    let title: String
    let valueText: String
    var subtitle: String? = nil
    let progress: Double
    var barColor: Color = PLATokens.Colors.primaryBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveKeyValueRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } trailing: {
                Text(valueText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(PLATokens.Colors.textPrimary)
            }

            GeometryReader { geo in
                let clamped = min(max(progress, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PLATokens.Colors.hairline)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(clamped > 0 ? 8 : 0, geo.size.width * clamped))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Preserved & Harmonized Shared Components

/// Tinted SF Symbol badge for structured forms and compact headers.
struct PLAIconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 34
    var iconFont: Font = .subheadline.weight(.semibold)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(color.opacity(0.14))
            Image(systemName: systemName)
                .font(iconFont)
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Deep Cobalt-Blue hero container used on Onboarding and Dompet total liquidity summary.
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
                RoundedRectangle(cornerRadius: PLATokens.Radius.xl, style: .continuous)
                    .fill(gradient)
            )
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
                .background(PLATokens.Colors.softBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hapus nominal")
            }
        }
    }
}

/// Non-color-only semantic status badge (icon + text, WCAG AA contrast).
struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color
    var onDarkSurface: Bool = false

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onDarkSurface ? Color.white : color)
            .padding(.horizontal, PLATokens.Spacing.sm)
            .padding(.vertical, 4)
            .background(
                (onDarkSurface ? Color.white.opacity(0.16) : color.opacity(0.12)),
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
    var color: Color = PLATokens.Colors.textPrimary

    var body: some View {
        Text(masked ? PLAFormatters.maskedRupiah() : PLAFormatters.rupiah(amount))
            .font(style)
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel(masked ? "Nominal disamarkan" : PLAFormatters.rupiah(amount))
    }
}

/// Clear, honest empty state explaining why the view is empty and offering the single next action.
struct PLAEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = PLATokens.Colors.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        PLACard(padding: PLATokens.Spacing.xl) {
            VStack(spacing: PLATokens.Spacing.md) {
                PLAIconBadge(systemName: systemImage, color: tint, size: 46, iconFont: .title3.weight(.semibold))
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                if let actionTitle, let action {
                    PLAPrimaryPillButton(title: actionTitle, action: action)
                        .padding(.top, PLATokens.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Insight row with severity icon, deterministic Indonesian copy, thumbs feedback (SC-16), and dismiss (AC-11.4).
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
                    size: 34,
                    iconFont: .subheadline.weight(.semibold)
                )

                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(copy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    Text(copy.body)
                        .font(.footnote)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: PLATokens.Spacing.xs) {
                Text("Berguna?")
                    .font(.caption)
                    .foregroundStyle(PLATokens.Colors.textSecondary)

                Button {
                    onFeedback(true)
                } label: {
                    Image(systemName: currentFeedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentFeedback == 1 ? PLATokens.Colors.safe : PLATokens.Colors.textSecondary)
                .accessibilityLabel("Insight berguna")

                Button {
                    onFeedback(false)
                } label: {
                    Image(systemName: currentFeedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentFeedback == -1 ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                .accessibilityLabel("Insight kurang berguna")

                Spacer()

                Button("Tutup", action: onDismiss)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                    .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.sm)
    }
}

/// Floating Liquid Glass toast banner with semantic checkmark and optional 5-second Undo button (AC-02.3).
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
                .foregroundStyle(PLATokens.Colors.textPrimary)
                .lineLimit(2)

            if let undoTitle, let onUndo {
                Spacer(minLength: PLATokens.Spacing.sm)
                Button(undoTitle, action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(PLATokens.Colors.softBlueTint, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PLATokens.Spacing.lg)
        .padding(.vertical, PLATokens.Spacing.sm)
        .modifier(PLALiquidGlassChrome(elevated: true))
        .padding(.horizontal, PLATokens.Spacing.lg)
    }
}

/// Alert row for sideload expiry (AC-14.2), denied notifications (AC-05.4), or database recovery.
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
                PLAIconBadge(systemName: icon, color: tint, size: 34)
                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
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
        .padding(.vertical, PLATokens.Spacing.sm)
    }
}

/// P-09: Personal Intelligence opt-in suggestion row (R-PER-01 & R-PER-02).
struct PersonalSuggestionRow: View {
    let suggestion: PersonalSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.md) {
                PLAIconBadge(systemName: iconName, color: PLATokens.Colors.accent, size: 34)
                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PLATokens.Colors.textPrimary)
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: PLATokens.Spacing.sm) {
                Button(acceptLabel, action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(PLATokens.Colors.primaryBlue)
                    .controlSize(.small)
                    .frame(minHeight: PLATokens.minTouchTarget)
                Button("Nanti Saja", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: PLATokens.minTouchTarget)
            }
        }
        .padding(.vertical, PLATokens.Spacing.sm)
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
