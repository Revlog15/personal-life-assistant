import SwiftUI
import PLACore

enum TaskSegment: Int, CaseIterable, Identifiable {
    case today = 0
    case upcoming = 1
    case anytime = 2
    case completed = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: return "Hari Ini"
        case .upcoming: return "Mendatang"
        case .anytime: return "Kapan Saja"
        case .completed: return "Selesai"
        }
    }
}

/// Tasks tab (PRD §7.2, F-02..F-06).
struct TasksView: View {
    @Environment(AppStore.self) private var store

    @State private var selectedSegment: TaskSegment = .today
    @State private var showAddSheet = false
    @State private var editingTask: PLATask?
    @State private var reschedulingTask: PLATask?

    // Dialog states for recurring tasks (AC-04.4 & §12 overdue catch-up)
    @State private var recurringTaskToDelete: PLATask?
    @State private var overdueRecurringToComplete: PLATask?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Segmen Tugas", selection: $selectedSegment) {
                    ForEach(TaskSegment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.vertical, PLATokens.Spacing.sm)

                List {
                    // P-01: Inline Natural Language Quick Add bar
                    Section {
                        QuickAddNaturalBar()
                    }

                    // P-09: Personal Intelligence opt-in suggestion card
                    if let topSuggestion = store.personalSuggestions.first {
                        Section("Saran Kebiasaan Lokal") {
                            PersonalSuggestionRow(
                                suggestion: topSuggestion,
                                onAccept: { store.acceptPersonalSuggestion(topSuggestion) },
                                onDismiss: { store.dismissPersonalSuggestion(topSuggestion) }
                            )
                        }
                    }

                    // AC-05.4: Non-intrusive notification-denied banner
                    if store.notificationAuthStatus == .denied {
                        Section {
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
                    case .today:
                        todayContent
                    case .upcoming:
                        taskListSection(
                            tasks: store.upcomingTasks,
                            emptyTitle: "Belum Ada Tugas Mendatang",
                            emptyMessage: "Tambahkan tugas dengan deadline agar Smart Reminder otomatis berjalan."
                        )
                    case .anytime:
                        taskListSection(
                            tasks: store.anytimeTasks,
                            emptyTitle: "Daftar Kapan Saja Kosong",
                            emptyMessage: "Tugas tanpa deadline akan tersimpan rapi di sini."
                        )
                    case .completed:
                        taskListSection(
                            tasks: store.completedTasks,
                            emptyTitle: "Belum Ada Tugas Selesai",
                            emptyMessage: "Tugas yang telah dicentang selesai akan tampil sebagai riwayat di sini.",
                            allowAddCTA: false
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Tugas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
                    }
                    .accessibilityLabel("Tambah tugas baru")
                }
            }
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
            // AC-04.4: Recurring delete choice dialog
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
            // PRD §12: Overdue recurring catch-up choice (> 1 missed cycle)
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

    @ViewBuilder
    private var todayContent: some View {
        if !store.overdueTasks.isEmpty {
            Section {
                ForEach(store.overdueTasks) { task in
                    taskRow(task, isOverdue: true)
                }
            } header: {
                Label("Terlambat (\(store.overdueTasks.count))", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(PLATokens.Colors.danger)
            }
        }

        Section("Hari Ini") {
            if store.todayTasks.isEmpty {
                if store.overdueTasks.isEmpty {
                    PLAEmptyStateView(
                        title: "Hari Ini Bersih",
                        message: "Tidak ada tugas jatuh tempo hari ini. Ketuk tombol di bawah untuk mencatat tugas cepat.",
                        systemImage: "checkmark.seal",
                        actionTitle: "Buat Tugas",
                        action: { showAddSheet = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Text("Tidak ada tugas tambahan jatuh tempo hari ini.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.todayTasks) { task in
                    taskRow(task, isOverdue: false)
                }
            }
        }
    }

    @ViewBuilder
    private func taskListSection(
        tasks: [PLATask],
        emptyTitle: String,
        emptyMessage: String,
        allowAddCTA: Bool = true
    ) -> some View {
        if tasks.isEmpty {
            Section {
                PLAEmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: "checklist",
                    actionTitle: allowAddCTA ? "Buat Tugas" : nil,
                    action: allowAddCTA ? { showAddSheet = true } : nil
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(tasks) { task in
                    taskRow(task, isOverdue: task.isOverdue(at: store.currentDateTime))
                }
            }
        }
    }

    private func taskRow(_ task: PLATask, isOverdue: Bool) -> some View {
        let isCompleted = task.status == .completed
        let rule = store.recurrenceRule(for: task.recurrenceRuleId)

        return VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
            HStack(alignment: .center, spacing: PLATokens.Spacing.sm) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.body.weight(.medium))
                            .strikethrough(isCompleted)
                            .foregroundStyle(isCompleted ? .secondary : .primary)

                        HStack(spacing: PLATokens.Spacing.sm) {
                            if let due = task.dueDateLocal {
                                let label = PLAFormatters.relativeDayLabel(due, today: store.today)
                                let timeSuffix = task.dueTimeMinutes.map { " • \(PLAFormatters.time24($0))" } ?? ""
                                Label(label + timeSuffix, systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(isOverdue ? PLATokens.Colors.danger : .secondary)
                            }
                            if let rule {
                                Label(PLAFormatters.recurrenceLabel(rule), systemImage: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.accent)
                            }
                        }

                        HStack(spacing: PLATokens.Spacing.xs) {
                            Text(store.categoryName(for: task.categoryId))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if task.priority != .medium {
                                StatusBadge(
                                    text: PLATokens.label(for: task.priority),
                                    icon: PLATokens.icon(for: task.priority),
                                    color: PLATokens.color(for: task.priority)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if isOverdue && !isCompleted {
                HStack {
                    Spacer()
                    Button {
                        reschedulingTask = task
                    } label: {
                        Label("Jadwalkan Ulang", systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: PLATokens.minTouchTarget)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if task.recurrenceRuleId != nil && task.status == .active {
                    recurringTaskToDelete = task
                } else {
                    store.deleteTask(task, deleteEntireSeries: true)
                }
            } label: {
                Label("Hapus", systemImage: "trash")
            }

            if !isCompleted {
                Button {
                    reschedulingTask = task
                } label: {
                    Label("Jadwalkan", systemImage: "calendar.badge.clock")
                }
                .tint(PLATokens.Colors.info)
            }
        }
    }

    private func handleCompleteTap(_ task: PLATask) {
        if task.status == .completed {
            store.reopenTask(task)
            return
        }
        // Check if overdue recurring task missed > 1 cycle (PRD §12)
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
