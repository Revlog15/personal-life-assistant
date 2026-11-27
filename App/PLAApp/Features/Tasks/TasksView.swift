import SwiftUI
import PLACore

enum TaskSegment: Int, CaseIterable, Identifiable {
    case agenda = 0
    case upcoming = 1
    case anytime = 2
    case completed = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .agenda: return "Jadwal"
        case .upcoming: return "Mendatang"
        case .anytime: return "Kapan Saja"
        case .completed: return "Selesai"
        }
    }
}

/// Tasks tab (PRD §7.2, F-02..F-06): Horizontal 7-day calendar strip, time-slotted agenda timeline,
/// natural-language quick-add bar, and full-width Royal Blue pill CTA.
struct TasksView: View {
    @Environment(AppStore.self) private var store

    @State private var selectedSegment: TaskSegment = .agenda
    @State private var selectedDate: LocalDate? = nil
    @State private var showAddSheet = false
    @State private var editingTask: PLATask?
    @State private var reschedulingTask: PLATask?
    @State private var recurringTaskToDelete: PLATask?
    @State private var overdueRecurringToComplete: PLATask?

    private var activeDate: LocalDate {
        selectedDate ?? store.today
    }

    private var weekDatesAroundSelected: [LocalDate] {
        let mondayOffset = -(activeDate.weekdayISO - 1)
        let monday = activeDate.addingDays(mondayOffset)
        return (0..<7).map { monday.addingDays($0) }
    }

    private func countFor(_ segment: TaskSegment) -> Int {
        switch segment {
        case .agenda: return store.todayTasks.count + store.overdueTasks.count
        case .upcoming: return store.upcomingTasks.count
        case .anytime: return store.anytimeTasks.count
        case .completed: return store.completedTasks.count
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.lg) {
                    headerBar

                    PLAWeekStripCalendar(
                        selectedDate: Binding(
                            get: { activeDate },
                            set: { newDate in
                                selectedDate = newDate
                                selectedSegment = .agenda
                            }
                        ),
                        today: store.today,
                        activeTaskDates: store.datesWithActiveTasks(in: weekDatesAroundSelected)
                    )

                    segmentStrip

                    QuickAddNaturalBar()

                    if let topSuggestion = store.personalSuggestions.first {
                        PLACard(padding: PLATokens.Spacing.md) {
                            PersonalSuggestionRow(
                                suggestion: topSuggestion,
                                onAccept: { store.acceptPersonalSuggestion(topSuggestion) },
                                onDismiss: { store.dismissPersonalSuggestion(topSuggestion) }
                            )
                        }
                    }

                    if store.notificationAuthStatus == .denied {
                        PLACard(padding: PLATokens.Spacing.md) {
                            AlertBannerRow(
                                icon: "bell.slash.fill",
                                tint: PLATokens.Colors.warning,
                                title: "Notifikasi Nonaktif",
                                message: "Aktifkan izin notifikasi agar pengingat tugas berbunyi tepat waktu.",
                                actionTitle: "Buka Settings iOS",
                                action: { store.notificationAdapter.openSystemSettings() }
                            )
                        }
                    }

                    switch selectedSegment {
                    case .agenda:
                        agendaContent
                    case .upcoming:
                        taskListSection(
                            title: "Tugas Mendatang",
                            tasks: store.upcomingTasks,
                            emptyTitle: "Belum Ada Tugas Mendatang",
                            emptyMessage: "Tambahkan tugas dengan deadline agar Smart Reminder otomatis berjalan."
                        )
                    case .anytime:
                        taskListSection(
                            title: "Daftar Kapan Saja",
                            tasks: store.anytimeTasks,
                            emptyTitle: "Daftar Kapan Saja Kosong",
                            emptyMessage: "Tugas tanpa tanggal jatuh tempo akan tersimpan rapi di sini."
                        )
                    case .completed:
                        taskListSection(
                            title: "Riwayat Selesai",
                            tasks: store.completedTasks,
                            emptyTitle: "Belum Ada Tugas Selesai",
                            emptyMessage: "Tugas yang telah dicentang selesai akan tampil sebagai riwayat di sini.",
                            allowAddCTA: false
                        )
                    }

                    PLAPrimaryPillButton(title: "Tambah Tugas", systemImage: "plus") {
                        showAddSheet = true
                    }
                    .padding(.top, PLATokens.Spacing.xs)
                }
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.top, PLATokens.Spacing.sm)
                .padding(.bottom, PLATokens.floatingDockClearance)
            }
            .background(PLATokens.Colors.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddSheet) {
                TaskFormSheet()
                    .environment(store)
            }
            .sheet(item: $editingTask) { task in
                TaskFormSheet(editingTask: task)
                    .environment(store)
            }
            .sheet(item: $reschedulingTask) { task in
                RescheduleSheet(task: task)
                    .environment(store)
            }
            .confirmationDialog(
                "Hapus Tugas Berulang",
                isPresented: Binding(
                    get: { recurringTaskToDelete != nil },
                    set: { if !$0 { recurringTaskToDelete = nil } }
                ),
                presenting: recurringTaskToDelete
            ) { task in
                Button("Hapus Siklus Ini Saja") {
                    store.deleteTask(task, deleteEntireSeries: false)
                    recurringTaskToDelete = nil
                }
                Button("Hapus Seluruh Seri Berulang", role: .destructive) {
                    store.deleteTask(task, deleteEntireSeries: true)
                    recurringTaskToDelete = nil
                }
                Button("Batal", role: .cancel) {
                    recurringTaskToDelete = nil
                }
            } message: { task in
                Text("Pilih apakah ingin melewati siklus \"\(task.title)\" kali ini atau menghentikan seluruh pengulangannya.")
            }
            .confirmationDialog(
                "Tugas Berulang Tertinggal Beberapa Siklus",
                isPresented: Binding(
                    get: { overdueRecurringToComplete != nil },
                    set: { if !$0 { overdueRecurringToComplete = nil } }
                ),
                presenting: overdueRecurringToComplete
            ) { task in
                Button("Lanjutkan Siklus Berikutnya dari Hari Ini") {
                    store.completeTask(task, catchUpFromToday: true)
                    overdueRecurringToComplete = nil
                }
                Button("Lanjutkan dari Jadwal Asli") {
                    store.completeTask(task, catchUpFromToday: false)
                    overdueRecurringToComplete = nil
                }
                Button("Batal", role: .cancel) {
                    overdueRecurringToComplete = nil
                }
            } message: { _ in
                Text("Agar jadwal tidak menumpuk, Anda dapat langsung melompat ke siklus berikutnya setelah hari ini.")
            }
        }
    }

    // MARK: - Header & Segment Pills

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agenda & Pengingat")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                Text("Tugas")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
                    .background(PLATokens.Colors.primaryBlue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tambah tugas baru")
        }
    }

    private var segmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PLATokens.Spacing.sm) {
                ForEach(TaskSegment.allCases) { seg in
                    let active = selectedSegment == seg
                    let count = countFor(seg)
                    Button {
                        selectedSegment = seg
                    } label: {
                        HStack(spacing: 6) {
                            Text(seg.title)
                                .font(.subheadline.weight(active ? .bold : .medium))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        active ? Color.white.opacity(0.24) : PLATokens.Colors.softBlueTint,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(active ? Color.white : PLATokens.Colors.softBlueText)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(
                            Capsule()
                                .fill(active ? PLATokens.Colors.primaryBlue : PLATokens.Colors.surface)
                        )
                        .overlay(
                            Capsule()
                                .stroke(active ? Color.clear : PLATokens.Colors.border, lineWidth: 1)
                        )
                        .foregroundStyle(active ? Color.white : PLATokens.Colors.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Agenda Timeline Content

    @ViewBuilder
    private var agendaContent: some View {
        let isTodaySelected = activeDate == store.today
        let scheduled = store.tasksScheduled(on: activeDate)

        if isTodaySelected && !store.overdueTasks.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Terlambat (\(store.overdueTasks.count))")
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(store.overdueTasks) { task in
                        timelineTaskRow(task, isOverdue: true)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(
                title: isTodaySelected ? "Hari Ini" : PLAFormatters.fullDate(activeDate),
                subtitle: isTodaySelected ? PLAFormatters.fullDate(store.today) : nil
            )

            if scheduled.isEmpty {
                if !isTodaySelected || store.overdueTasks.isEmpty {
                    PLAEmptyStateView(
                        title: isTodaySelected ? "Hari Ini Bersih" : "Belum Ada Jadwal",
                        message: isTodaySelected
                            ? "Tidak ada tugas jatuh tempo hari ini. Gunakan kolom ketik cepat atau tombol Tambah Tugas di bawah."
                            : "Tidak ada tugas terjadwal pada \(PLAFormatters.shortDate(activeDate)).",
                        systemImage: "checkmark.seal.fill",
                        tint: PLATokens.Colors.accent
                    )
                } else {
                    PLACard(padding: PLATokens.Spacing.md) {
                        Text("Tidak ada tugas tambahan jatuh tempo hari ini.")
                            .font(.subheadline)
                            .foregroundStyle(PLATokens.Colors.textSecondary)
                    }
                }
            } else {
                VStack(spacing: PLATokens.Spacing.md) {
                    ForEach(scheduled) { task in
                        timelineTaskRow(task, isOverdue: task.isOverdue(at: store.currentDateTime))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskListSection(
        title: String,
        tasks: [PLATask],
        emptyTitle: String,
        emptyMessage: String,
        allowAddCTA: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(title: title)

            if tasks.isEmpty {
                PLAEmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: "checklist",
                    tint: PLATokens.Colors.accent,
                    actionTitle: allowAddCTA ? "Buat Tugas" : nil,
                    action: allowAddCTA ? { showAddSheet = true } : nil
                )
            } else {
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(tasks) { task in
                        timelineTaskRow(task, isOverdue: task.isOverdue(at: store.currentDateTime))
                    }
                }
            }
        }
    }

    // MARK: - Reference-Inspired Time-Slotted Task Row

    private func timelineTaskRow(_ task: PLATask, isOverdue: Bool) -> some View {
        let isCompleted = task.status == .completed
        let rule = store.recurrenceRule(for: task.recurrenceRuleId)
        let timeLabel = task.dueTimeMinutes.map { PLAFormatters.time24($0) } ?? "Harian"

        return HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
            // Left time gutter (inspired by reference's 06.00 / 08.00 / 16.00 column)
            VStack(alignment: .trailing, spacing: 3) {
                Text(timeLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverdue && !isCompleted ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                if let due = task.dueDateLocal, selectedSegment != .agenda {
                    Text(PLAFormatters.shortDayMonth(due))
                        .font(.caption2)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                }
            }
            .frame(width: 52, alignment: .trailing)
            .padding(.top, 14)

            // Right crisp content card
            PLACard(padding: PLATokens.Spacing.md, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                    HStack(alignment: .top, spacing: PLATokens.Spacing.sm) {
                        Button {
                            handleCompleteTap(task)
                        } label: {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isCompleted ? PLATokens.Colors.safe : PLATokens.color(for: task.priority))
                                .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isCompleted ? "Buka ulang tugas \(task.title)" : "Selesaikan tugas \(task.title)")

                        Button {
                            editingTask = task
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.subheadline.weight(.bold))
                                    .strikethrough(isCompleted)
                                    .foregroundStyle(isCompleted ? PLATokens.Colors.textSecondary : PLATokens.Colors.textPrimary)
                                    .multilineTextAlignment(.leading)

                                if let notes = task.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(PLATokens.Colors.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                HStack(spacing: PLATokens.Spacing.xs) {
                                    Text(store.categoryName(for: task.categoryId))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(PLATokens.Colors.softBlueText)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(PLATokens.Colors.softBlueTint, in: Capsule())

                                    if task.priority != .medium {
                                        StatusBadge(
                                            text: PLATokens.label(for: task.priority),
                                            icon: PLATokens.icon(for: task.priority),
                                            color: PLATokens.color(for: task.priority)
                                        )
                                    }

                                    if let rule {
                                        Label(PLAFormatters.recurrenceLabel(rule), systemImage: "repeat")
                                            .font(.caption2)
                                            .foregroundStyle(PLATokens.Colors.textSecondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                editingTask = task
                            } label: {
                                Label("Sunting", systemImage: "pencil")
                            }
                            if !isCompleted {
                                Button {
                                    reschedulingTask = task
                                } label: {
                                    Label("Jadwalkan Ulang", systemImage: "calendar.badge.clock")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                if task.recurrenceRuleId != nil && task.status == .active {
                                    recurringTaskToDelete = task
                                } else {
                                    store.deleteTask(task, deleteEntireSeries: true)
                                }
                            } label: {
                                Label("Hapus", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Opsi tugas \(task.title)")
                    }

                    if isOverdue && !isCompleted {
                        HStack {
                            if let due = task.dueDateLocal {
                                Text(PLAFormatters.relativeDayLabel(due, today: store.today))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PLATokens.Colors.danger)
                            }
                            Spacer()
                            Button {
                                reschedulingTask = task
                            } label: {
                                Label("Jadwalkan Ulang", systemImage: "calendar.badge.clock")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PLATokens.Colors.accent)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(PLATokens.Colors.softBlueTint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func handleCompleteTap(_ task: PLATask) {
        if task.status == .completed {
            store.reopenTask(task)
            return
        }
        if let ruleId = task.recurrenceRuleId,
           let rule = store.recurrenceRule(for: ruleId),
           let due = task.dueDateLocal {
            let missed = RecurrenceEngine.missedCycleCount(from: due, upTo: store.today, rule: rule)
            if missed > 1 {
                overdueRecurringToComplete = task
                return
            }
        }
        store.completeTask(task)
    }
}
