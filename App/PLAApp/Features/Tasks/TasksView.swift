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

/// Tasks tab (PRD §7.2, F-02..F-06): Calm reference-inspired layout with translucent Liquid Glass 4-tab bar,
/// full monthly calendar grid with indicator dots (shown only for Jadwal), minimalist 1-line Quick Add, and clean timeline rows.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PLATokens.Spacing.lg) {
                    PLAScreenHeader("Tugas") {
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

                    PLAGlassSegmentBar(
                        options: TaskSegment.allCases,
                        selection: $selectedSegment,
                        title: \.title
                    )

                    if selectedSegment == .agenda {
                        PLAMonthCalendarView(
                            selectedDate: Binding(
                                get: { activeDate },
                                set: { selectedDate = $0 }
                            ),
                            today: store.today,
                            markers: store.calendarMarkers(year: activeDate.year, month: activeDate.month)
                        )
                    }

                    if selectedSegment != .completed {
                        QuickAddNaturalBar()
                    }

                    if let topSuggestion = store.personalSuggestions.first, selectedSegment == .agenda {
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
                        flatTaskList(
                            title: "Mendatang",
                            tasks: store.upcomingTasks,
                            emptyTitle: "Belum Ada Tugas Mendatang",
                            emptyMessage: "Tambahkan tugas dengan tanggal jatuh tempo agar pengingat otomatis berjalan."
                        )
                    case .anytime:
                        flatTaskList(
                            title: "Kapan Saja",
                            tasks: store.anytimeTasks,
                            emptyTitle: "Daftar Kapan Saja Kosong",
                            emptyMessage: "Tugas tanpa tanggal jatuh tempo akan tersimpan di sini."
                        )
                    case .completed:
                        flatTaskList(
                            title: "Riwayat Selesai",
                            tasks: store.completedTasks,
                            emptyTitle: "Belum Ada Tugas Selesai",
                            emptyMessage: "Tugas yang telah dicentang selesai akan tampil di sini.",
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
                TaskFormSheet(initialDate: selectedSegment == .agenda ? activeDate : nil)
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

    // MARK: - Agenda Timeline Content

    @ViewBuilder
    private var agendaContent: some View {
        let isTodaySelected = activeDate == store.today
        let scheduled = store.tasksScheduled(on: activeDate)
        let billsOnDate = store.billsDue(on: activeDate)

        if isTodaySelected && !store.overdueTasks.isEmpty {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                PLASectionHeader(title: "Terlambat (\(store.overdueTasks.count))")
                PLAGroupList {
                    ForEach(Array(store.overdueTasks.enumerated()), id: \.element.id) { idx, task in
                        compactTaskRow(task, isOverdue: true)
                        if idx < store.overdueTasks.count - 1 {
                            PLAInsetDivider(leadingInset: 52)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            PLASectionHeader(title: isTodaySelected ? "Hari Ini" : PLAFormatters.fullDate(activeDate))

            if scheduled.isEmpty && billsOnDate.isEmpty {
                if !isTodaySelected || store.overdueTasks.isEmpty {
                    PLAEmptyStateView(
                        title: isTodaySelected ? "Hari Ini Bersih" : "Belum Ada Jadwal",
                        message: isTodaySelected
                            ? "Tidak ada tugas jatuh tempo hari ini. Ketik cepat di atas atau tekan Tambah Tugas."
                            : "Tidak ada tugas atau tagihan terjadwal pada \(PLAFormatters.shortDate(activeDate)).",
                        systemImage: "checkmark.seal.fill",
                        tint: PLATokens.Colors.accent
                    )
                } else {
                    Text("Tidak ada tugas tambahan jatuh tempo hari ini.")
                        .font(.subheadline)
                        .foregroundStyle(PLATokens.Colors.textSecondary)
                        .padding(.vertical, PLATokens.Spacing.sm)
                }
            } else {
                VStack(spacing: PLATokens.Spacing.sm) {
                    ForEach(scheduled) { task in
                        timelineAgendaRow(task, isOverdue: task.isOverdue(at: store.currentDateTime))
                    }

                    if !billsOnDate.isEmpty {
                        PLAGroupList {
                            ForEach(Array(billsOnDate.enumerated()), id: \.element.id) { idx, bill in
                                calendarBillRow(bill)
                                if idx < billsOnDate.count - 1 {
                                    PLAInsetDivider(leadingInset: 48)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func calendarBillRow(_ bill: Bill) -> some View {
        HStack(spacing: PLATokens.Spacing.md) {
            PLAIconBadge(systemName: "creditcard.fill", color: PLATokens.Colors.warning, size: 32, iconFont: .caption.weight(.bold))

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                Text(bill.isTrial ? "Akhir uji coba" : "Tagihan jatuh tempo")
                    .font(.caption)
                    .foregroundStyle(PLATokens.Colors.warning)
            }

            Spacer()

            Text(store.isFinanceLocked ? PLAFormatters.maskedRupiah() : PLAFormatters.rupiah(bill.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(PLATokens.Colors.textPrimary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func flatTaskList(
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
                PLAGroupList {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, task in
                        compactTaskRow(task, isOverdue: task.isOverdue(at: store.currentDateTime))
                        if idx < tasks.count - 1 {
                            PLAInsetDivider(leadingInset: 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reference-Style Time-Slotted Row (Flat Soft Surface, Context Menu for Actions)

    private func timelineAgendaRow(_ task: PLATask, isOverdue: Bool) -> some View {
        let isCompleted = task.status == .completed
        let timeLabel = task.dueTimeMinutes.map { PLAFormatters.time24($0) } ?? "Harian"

        return HStack(alignment: .center, spacing: PLATokens.Spacing.md) {
            Text(timeLabel)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isOverdue && !isCompleted ? PLATokens.Colors.danger : PLATokens.Colors.textSecondary)
                .frame(width: 46, alignment: .trailing)

            PLACard(padding: PLATokens.Spacing.md, cornerRadius: 16) {
                compactTaskRow(task, isOverdue: isOverdue, showDueDate: false)
            }
        }
    }

    private func compactTaskRow(_ task: PLATask, isOverdue: Bool, showDueDate: Bool = true) -> some View {
        let isCompleted = task.status == .completed
        let rule = store.recurrenceRule(for: task.recurrenceRuleId)

        return HStack(alignment: .center, spacing: PLATokens.Spacing.sm) {
            Button {
                handleCompleteTap(task)
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? PLATokens.Colors.safe : PLATokens.color(for: task.priority))
                    .frame(width: PLATokens.minTouchTarget, height: PLATokens.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Buka ulang tugas \(task.title)" : "Selesaikan tugas \(task.title)")

            Button {
                editingTask = task
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? PLATokens.Colors.textSecondary : PLATokens.Colors.textPrimary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: PLATokens.Spacing.xs) {
                        if showDueDate, let due = task.dueDateLocal {
                            let label = PLAFormatters.relativeDayLabel(due, today: store.today)
                            let suffix = task.dueTimeMinutes.map { " \(PLAFormatters.time24($0))" } ?? ""
                            Text(label + suffix)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isOverdue && !isCompleted ? PLATokens.Colors.danger : PLATokens.Colors.accent)
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                        }

                        Text(store.categoryName(for: task.categoryId))
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.textSecondary)

                        if let rule {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(PLATokens.Colors.textSecondary)
                                .accessibilityLabel(PLAFormatters.recurrenceLabel(rule))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isOverdue && !isCompleted {
                Button("Jadwalkan") {
                    reschedulingTask = task
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PLATokens.Colors.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(PLATokens.Colors.softBlueTint, in: Capsule())
                .buttonStyle(.plain)
            } else if task.priority == .high && !isCompleted {
                Image(systemName: PLATokens.icon(for: TaskPriority.high))
                    .font(.subheadline)
                    .foregroundStyle(PLATokens.Colors.danger)
                    .accessibilityLabel("Prioritas tinggi")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
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
