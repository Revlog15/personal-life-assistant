import SwiftUI
import PLACore

/// Quick-add & edit task sheet engineered for <= 3 taps outside typing title (AC-02.1..02.5, F-03, F-04).
struct TaskFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editingTask: PLATask?

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var selectedDate: Date
    @State private var hasDueTime: Bool
    @State private var selectedTime: Date
    @State private var priority: TaskPriority
    @State private var selectedCategoryId: UUID?

    // Recurrence (F-04)
    @State private var isRecurring: Bool
    @State private var frequency: RecurrenceFrequency
    @State private var interval: Int
    @State private var weekdaysMask: Int
    @State private var monthlyUseEndOfMonth: Bool
    @State private var recurrenceAnchorMode: RecurrenceAnchorMode

    @FocusState private var isTitleFocused: Bool

    init(editingTask: PLATask? = nil) {
        self.editingTask = editingTask
        _title = State(initialValue: editingTask?.title ?? "")
        _notes = State(initialValue: editingTask?.notes ?? "")
        _hasDueDate = State(initialValue: editingTask?.dueDateLocal != nil)
        let tz = TimeZone.current
        if let due = editingTask?.dueDateLocal {
            _selectedDate = State(initialValue: due.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
        } else {
            _selectedDate = State(initialValue: Date())
        }
        _hasDueTime = State(initialValue: editingTask?.dueTimeMinutes != nil)
        if let mins = editingTask?.dueTimeMinutes {
            let base = editingTask?.dueDateLocal ?? LocalDate.from(date: Date(), timeZone: tz)
            _selectedTime = State(initialValue: base.toDate(minutesFromMidnight: mins, timeZone: tz))
        } else {
            let base = LocalDate.from(date: Date(), timeZone: tz)
            _selectedTime = State(initialValue: base.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
        }
        _priority = State(initialValue: editingTask?.priority ?? .medium)
        _selectedCategoryId = State(initialValue: editingTask?.categoryId)
        _isRecurring = State(initialValue: editingTask?.recurrenceRuleId != nil)
        _frequency = State(initialValue: .monthly)
        _interval = State(initialValue: 1)
        _weekdaysMask = State(initialValue: 1) // Monday default
        _monthlyUseEndOfMonth = State(initialValue: false)
        _recurrenceAnchorMode = State(initialValue: .fixedSchedule)
    }

    private var isTitleValid: Bool {
        PLATask.isValidTitle(title)
    }

    private var resolvedLocalDate: LocalDate? {
        guard hasDueDate else { return nil }
        return LocalDate.from(date: selectedDate, timeZone: store.clock.timeZone)
    }

    private var resolvedTimeMinutes: Int? {
        guard hasDueDate && hasDueTime else { return nil }
        let dt = LocalDateTime.from(date: selectedTime, timeZone: store.clock.timeZone)
        return dt.minutesFromMidnight
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apa yang ingin dikerjakan?", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)

                    if !title.isEmpty && !isTitleValid {
                        Text("Judul wajib diisi (maks. 200 karakter).")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }

                    TextField("Catatan tambahan (opsional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Quick deadline chips (AC-02.2)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PLATokens.Spacing.sm) {
                            quickDateChip("Tanpa Tanggal", isSelected: !hasDueDate) {
                                hasDueDate = false
                                isRecurring = false
                            }
                            quickDateChip("Hari Ini", isSelected: resolvedLocalDate == store.today) {
                                applyQuickDate(store.today)
                            }
                            quickDateChip("Besok", isSelected: resolvedLocalDate == store.today.addingDays(1)) {
                                applyQuickDate(store.today.addingDays(1))
                            }
                            let weekend = RescheduleSuggester.nextWeekendDate(from: store.today)
                            quickDateChip("Akhir Pekan", isSelected: resolvedLocalDate == weekend) {
                                applyQuickDate(weekend)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Toggle("Pilih Tanggal Khusus", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Tanggal", selection: $selectedDate, displayedComponents: .date)
                        Toggle("Atur Jam Spesifik", isOn: $hasDueTime)
                        if hasDueTime {
                            DatePicker("Jam", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        }
                    }
                } header: {
                    Text("Deadline & Smart Reminder")
                } footer: {
                    if let previewText = smartReminderSummary {
                        Text(previewText)
                    }
                }

                Section("Prioritas & Kategori") {
                    Picker("Prioritas", selection: $priority) {
                        Text("Rendah").tag(TaskPriority.low)
                        Text("Sedang").tag(TaskPriority.medium)
                        Text("Tinggi").tag(TaskPriority.high)
                    }
                    .pickerStyle(.segmented)

                    Picker("Kategori", selection: $selectedCategoryId) {
                        ForEach(store.taskCategories) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                }

                if hasDueDate {
                    Section("Pengulangan (Opsional)") {
                        Toggle("Tugas Berulang", isOn: $isRecurring)
                        if isRecurring {
                            Picker("Frekuensi", selection: $frequency) {
                                Text("Harian").tag(RecurrenceFrequency.daily)
                                Text("Mingguan").tag(RecurrenceFrequency.weekly)
                                Text("Bulanan").tag(RecurrenceFrequency.monthly)
                                Text("Tahunan").tag(RecurrenceFrequency.yearly)
                            }

                            Stepper("Setiap \(interval) \(intervalUnitLabel)", value: $interval, in: 1...30)

                            if frequency == .weekly {
                                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                                    Text("Pilih Hari")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: PLATokens.Spacing.xs) {
                                        ForEach(1...7, id: \.self) { wd in
                                            let bit = 1 << (wd - 1)
                                            let active = (weekdaysMask & bit) != 0
                                            Button(PLAFormatters.shortWeekday(wd)) {
                                                if active {
                                                    let next = weekdaysMask & ~bit
                                                    if next != 0 { weekdaysMask = next }
                                                } else {
                                                    weekdaysMask |= bit
                                                }
                                            }
                                            .font(.caption2.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                            .background(active ? PLATokens.Colors.accent : Color(uiColor: .tertiarySystemFill))
                                            .foregroundStyle(active ? Color.white : Color.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            if frequency == .monthly {
                                Toggle("Selalu pada Hari Terakhir Bulan", isOn: $monthlyUseEndOfMonth)
                            }

                            Picker("Patokan Siklus Berikutnya", selection: $recurrenceAnchorMode) {
                                Text("Dari Jadwal Asli").tag(RecurrenceAnchorMode.fixedSchedule)
                                Text("Dari Tanggal Selesai").tag(RecurrenceAnchorMode.fromCompletionDate)
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingTask == nil ? "Tugas Baru" : "Sunting Tugas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isTitleValid)
                }
            }
            .onAppear {
                if selectedCategoryId == nil {
                    selectedCategoryId = store.defaultTaskCategory?.id
                }
                if let ruleId = editingTask?.recurrenceRuleId,
                   let rule = store.recurrenceRule(for: ruleId) {
                    isRecurring = true
                    frequency = rule.frequency
                    interval = rule.interval
                    weekdaysMask = rule.weekdaysMask ?? (resolvedLocalDate?.weekdayBit ?? 1)
                    monthlyUseEndOfMonth = (rule.anchorDayOfMonth == -1)
                    recurrenceAnchorMode = rule.anchorMode
                } else if editingTask == nil {
                    isTitleFocused = true
                }
            }
        }
    }

    private func quickDateChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, PLATokens.Spacing.md)
            .frame(minHeight: PLATokens.minTouchTarget)
            .background(isSelected ? PLATokens.Colors.accent : Color(uiColor: .tertiarySystemFill))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }

    private func applyQuickDate(_ date: LocalDate) {
        hasDueDate = true
        selectedDate = date.toDate(minutesFromMidnight: 9 * 60, timeZone: store.clock.timeZone)
    }

    private var intervalUnitLabel: String {
        switch frequency {
        case .daily: return "hari"
        case .weekly: return "minggu"
        case .monthly: return "bulan"
        case .yearly: return "tahun"
        }
    }

    private var smartReminderSummary: String? {
        guard let due = resolvedLocalDate else {
            return "Tanpa deadline — tugas akan masuk segmen Kapan Saja tanpa notifikasi otomatis."
        }
        let draft = PLATask(
            title: title.isEmpty ? "Draft" : title,
            dueDateLocal: due,
            dueTimeMinutes: resolvedTimeMinutes,
            priority: priority
        )
        let planned = ReminderPlanner.planTaskReminders(for: draft, now: store.currentDateTime, settings: store.settings)
        if planned.isEmpty {
            return "Deadline sudah sangat dekat; tidak ada pengingat otomatis tersisa di masa depan."
        }
        return "Smart Reminder otomatis menjadwalkan \(planned.count) pengingat (berikutnya: \(PLAFormatters.dateTime(planned[0].fireDateLocal)))."
    }

    private func save() {
        var rule: RecurrenceRule? = nil
        if isRecurring, let due = resolvedLocalDate {
            let existingRuleId = editingTask?.recurrenceRuleId ?? UUID()
            rule = RecurrenceRule(
                id: existingRuleId,
                frequency: frequency,
                interval: interval,
                weekdaysMask: frequency == .weekly ? weekdaysMask : nil,
                anchorDayOfMonth: frequency == .monthly ? (monthlyUseEndOfMonth ? -1 : due.day) : (frequency == .yearly ? due.day : nil),
                anchorMonth: frequency == .yearly ? due.month : nil,
                anchorMode: recurrenceAnchorMode
            )
        }

        store.createOrUpdateTask(
            existing: editingTask,
            title: title,
            notes: notes,
            dueDate: resolvedLocalDate,
            dueTimeMinutes: resolvedTimeMinutes,
            priority: priority,
            categoryId: selectedCategoryId,
            recurrenceRule: rule
        )

        // §9.5: Prompt notification authorization gently when user creates their first task with a deadline
        if resolvedLocalDate != nil && store.notificationAuthStatus == .notDetermined {
            _Concurrency.Task {
                await store.requestNotificationPermission()
            }
        }

        dismiss()
    }
}
