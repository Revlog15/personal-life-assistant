import SwiftUI
import PLACore

// MARK: - Core Layout & Surface Containers

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

/// Crisp solid content card (pure white in Light Mode, deep slate in Dark Mode) with a clean hairline border.
/// Stays flat on the canvas so elevation is reserved exclusively for floating chrome.
struct PLACard<Content: View>: View {
    var padding: CGFloat = PLATokens.Spacing.lg
    var cornerRadius: CGFloat = PLATokens.Radius.lg
    private let content: Content

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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PLATokens.Colors.border, lineWidth: 1)
            )
    }
}

/// Architectural section header with bold title and optional trailing action button.
struct PLASectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                }
            }
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

/// Compact circular Liquid Glass action button for top bar controls (44x44pt minimum touch target).
struct PLALiquidGlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.textPrimary)
                .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                .background(.ultraThinMaterial, in: Circle())
                .background(PLATokens.Colors.glassTint, in: Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.28 : 0.90),
                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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

// MARK: - Detached Floating Liquid Glass Bottom Dock

/// Floating Liquid Glass pill navigation dock hovering above the bottom safe area (inspired by reference dock).
/// Uses native iOS 17 `.ultraThinMaterial` + specular hairline rim so it works seamlessly on iOS 17+ Light & Dark modes.
struct PLAFloatingGlassTabBar: View {
    @Binding var selectedTab: AppTab

    @Environment(\.colorScheme) private var colorScheme
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
        TabItem(tab: .finance, title: "Keuangan", icon: "chart.bar", activeIcon: "chart.bar.fill"),
        TabItem(tab: .settings, title: "Pengaturan", icon: "gearshape", activeIcon: "gearshape.fill")
    ]

    var body: some View {
        HStack(spacing: PLATokens.Spacing.sm) {
            ForEach(items) { item in
                let isSelected = selectedTab == item.tab
                Button {
                    if reduceMotion {
                        selectedTab = item.tab
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedTab = item.tab
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? item.activeIcon : item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : PLATokens.Colors.glassInactiveIcon)

                        if isSelected {
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, isSelected ? 16 : 0)
                    .frame(minWidth: 48, minHeight: 48)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(PLATokens.Colors.primaryBlue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .background(PLATokens.Colors.glassTint, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.92),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14),
            radius: 18,
            x: 0,
            y: 8
        )
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

/// High-contrast obsidian telemetry card with timeframe pills, smooth blue trend curve, and bottom tick ruler.
/// Driven exclusively by real local transaction totals; displays an honest flat baseline when no expenses exist.
struct PLAChartHeroCard: View {
    let title: String
    let subtitle: String
    let totalAmount: Int64
    let points: [PLADailyMetricPoint]
    @Binding var selectedRange: SpendingChartRange
    var status: BudgetHealthStatus? = nil
    var showStatusBadge: Bool = true
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
            // Header row: question title + status pill
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
                        let pt = points[idx]
                        Text(PLAFormatters.rupiah(pt.amount))
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
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
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

            // Segmented timeframe selector pills (active pill crisp white with dark text)
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

            // Chart body
            if isMasked {
                lockedPlaceholder
            } else if !hasAnyData {
                emptyChartPlaceholder
            } else {
                smoothCurvePlot
            }

            // Bottom tick ruler + day labels
            if !isMasked && !points.isEmpty {
                tickRuler
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
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
    }

    private var emptyChartPlaceholder: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            Rectangle()
                .fill(PLATokens.Colors.chartLine.opacity(0.35))
                .frame(height: 2)
                .padding(.top, 26)
            Text("Belum ada pengeluaran tercatat pada rentang \(selectedRange.label.lowercased()).")
                .font(.caption)
                .foregroundStyle(PLATokens.Colors.obsidianMutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
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
                    // Vertical guide hair
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: pt.y))
                        p.addLine(to: CGPoint(x: pt.x, y: h))
                    }
                    .stroke(PLATokens.Colors.chartLine.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    // Active highlight dot (single focal glow accent on chart node)
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
        .frame(height: 112)
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
                        .frame(width: 1, height: tick % 6 == 0 ? 10 : 5)
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

// MARK: - Reference-Inspired Rings, Week Strip Calendar, Metric Tiles & Breakdown Bars

/// Single day column with circular completion ring and weekday letter (modeled on reference overview rings).
struct PLAMiniRingDayColumn: View {
    let point: PLADailyRingPoint

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(PLATokens.Colors.border, lineWidth: 3)
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

/// Interactive 7-day horizontal calendar strip with soft-blue vertical active day capsule.
struct PLAWeekStripCalendar: View {
    @Binding var selectedDate: LocalDate
    let today: LocalDate
    let activeTaskDates: Set<LocalDate>

    private var weekDates: [LocalDate] {
        let mondayOffset = -(selectedDate.weekdayISO - 1)
        let monday = selectedDate.addingDays(mondayOffset)
        return (0..<7).map { monday.addingDays($0) }
    }

    var body: some View {
        PLACard(padding: PLATokens.Spacing.md) {
            VStack(spacing: PLATokens.Spacing.md) {
                HStack {
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
                        .frame(minHeight: 32)
                        .background(PLATokens.Colors.softBlueTint, in: Capsule())
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 4) {
                        Button {
                            selectedDate = selectedDate.addingDays(-7)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Minggu sebelumnya")

                        Button {
                            selectedDate = selectedDate.addingDays(7)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Minggu berikutnya")
                    }
                }

                HStack(spacing: 4) {
                    ForEach(weekDates, id: \.self) { date in
                        let isSelected = date == selectedDate
                        let isToday = date == today
                        let hasTasks = activeTaskDates.contains(date)

                        Button {
                            selectedDate = date
                        } label: {
                            VStack(spacing: 5) {
                                Text(PLAFormatters.singleLetterWeekday(date.weekdayISO))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        isSelected
                                        ? PLATokens.Colors.softBlueText
                                        : PLATokens.Colors.textSecondary
                                    )

                                Text(date.day < 10 ? "0\(date.day)" : "\(date.day)")
                                    .font(.subheadline.weight(isSelected || isToday ? .bold : .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        isSelected
                                        ? PLATokens.Colors.softBlueText
                                        : PLATokens.Colors.textPrimary
                                    )

                                Circle()
                                    .fill(hasTasks ? PLATokens.Colors.accent : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(PLATokens.Colors.softBlueTint)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(PLATokens.Colors.accent.opacity(0.35), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(PLAFormatters.fullDate(date))\(hasTasks ? ", ada tugas aktif" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// Clean 2x2 stat tile (label top-left, subtle icon top-right, tabular metric below).
struct PLAMetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let systemImage: String
    var valueColor: Color = PLATokens.Colors.textPrimary
    var iconTint: Color = PLATokens.Colors.accent

    var body: some View {
        PLACard(padding: PLATokens.Spacing.md, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconTint)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
                        .fill(PLATokens.Colors.border.opacity(0.85))
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

/// Tinted SF Symbol badge for structured rows and forms.
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

/// Deep Cobalt-Blue hero container used on Onboarding and Accounts/Savings summary headers.
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
                PLAIconBadge(systemName: systemImage, color: tint, size: 48, iconFont: .title3.weight(.semibold))
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

/// Insight card with severity icon, deterministic Indonesian copy, thumbs feedback (SC-16), and dismiss (AC-11.4).
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
                    size: 36,
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

            HStack(spacing: PLATokens.Spacing.sm) {
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
    }
}

/// Floating Liquid Glass toast banner with semantic checkmark and optional 5-second Undo button (AC-02.3).
struct ToastBannerView: View {
    let message: String
    let undoTitle: String?
    let onUndo: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

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
        .background(.ultraThinMaterial, in: Capsule())
        .background(PLATokens.Colors.glassTint, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    Color.white.opacity(colorScheme == .dark ? 0.22 : 0.85),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, x: 0, y: 6)
        .padding(.horizontal, PLATokens.Spacing.lg)
    }
}

/// Alert banner for sideload expiry (AC-14.2), denied notifications (AC-05.4), or database recovery.
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
    }
}

/// P-09: Personal Intelligence opt-in suggestion card (R-PER-01 & R-PER-02).
struct PersonalSuggestionRow: View {
    let suggestion: PersonalSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(alignment: .top, spacing: PLATokens.Spacing.md) {
                PLAIconBadge(systemName: iconName, color: PLATokens.Colors.accent, size: 36)
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
