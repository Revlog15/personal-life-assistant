import SwiftUI
import PLACore

/// Quick & Smart Reschedule sheet (MVP F-06 + Pasca-MVP P-08 R-PER-03 weighted daily score & read-only EventKit).
/// Never mutates the schedule automatically — requires explicit user confirmation.
struct RescheduleSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: PLATask

    @State private var chosenDate: LocalDate
    @State private var pickerDate: Date
    @State private var calendarCounts: [LocalDate: Int] = [:]

    private var smartOptions: [SmartRescheduleOption] {
        RescheduleSuggester.smartOptionsInNext7Days(
            from: store.today,
            activeTasks: store.tasks,
            calendarEventCounts: calendarCounts,
            excludingTaskId: task.id
        )
    }

    private var bestOption: SmartRescheduleOption {
        smartOptions.first ?? RescheduleSuggester.smartBestDayInNext7Days(
            from: store.today,
            activeTasks: store.tasks,
            calendarEventCounts: calendarCounts,
            excludingTaskId: task.id
        )
    }

    init(task: PLATask) {
        self.task = task
        let tz = TimeZone.current
        let today = LocalDate.from(date: Date(), timeZone: tz)
        let tomorrow = today.addingDays(1)
        _chosenDate = State(initialValue: tomorrow)
        _pickerDate = State(initialValue: tomorrow.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tugas") {
                    Text(task.title)
                        .font(.headline)
                    if let oldDue = task.dueDateLocal {
                        Text("Jadwal sebelumnya: \(PLAFormatters.fullDate(oldDue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // P-08 (R-PER-03): Weighted workload score + optional EventKit calendar awareness
                Section {
                    ForEach(smartOptions.prefix(3)) { option in
                        Button {
                            select(option.date)
                        } label: {
                            HStack(spacing: PLATokens.Spacing.md) {
                                Image(systemName: option.id == bestOption.id ? "sparkles" : "calendar")
                                    .font(.title3)
                                    .foregroundStyle(option.id == bestOption.id ? PLATokens.Colors.accent : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: PLATokens.Spacing.xs) {
                                        Text(PLAFormatters.fullDate(option.date))
                                            .font(.body.weight(option.id == bestOption.id ? .semibold : .regular))
                                            .foregroundStyle(.primary)
                                        if option.id == bestOption.id {
                                            StatusBadge(text: "Terbaik", icon: "star.fill", color: PLATokens.Colors.accent)
                                        }
                                    }
                                    Text(optionSummary(option))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if chosenDate == option.date {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PLATokens.Colors.accent)
                                }
                            }
                            .frame(minHeight: PLATokens.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }

                    if !store.settings.useCalendarForReschedule {
                        Button {
                            _Concurrency.Task {
                                let granted = await store.calendarService.requestReadAccess()
                                if granted {
                                    store.updateSettings { $0.useCalendarForReschedule = true }
                                    calendarCounts = store.calendarEventCountsForNext7Days()
                                    select(bestOption.date)
                                } else {
                                    store.showToast("Izin Kalender tidak diberikan")
                                }
                            }
                        } label: {
                            Label("Pertimbangkan Agenda Apple Calendar (Hanya-Baca)", systemImage: "calendar.badge.plus")
                                .font(.footnote.weight(.medium))
                        }
                    }
                } header: {
                    Text("Saran Hari Paling Longgar (Skor Beban 7 Hari)")
                } footer: {
                    Text("Skor beban = (Tinggi × 3) + (Sedang × 2) + (Rendah × 1)\(store.settings.useCalendarForReschedule ? " + jumlah rapat Kalender iOS." : ".")")
                }

                Section("Pilihan Cepat") {
                    quickOptionRow("Hari Ini", date: store.today)
                    quickOptionRow("Besok", date: store.today.addingDays(1))
                    quickOptionRow("Akhir Pekan", date: RescheduleSuggester.nextWeekendDate(from: store.today))

                    DatePicker("Pilih Tanggal Lain", selection: $pickerDate, displayedComponents: .date)
                        .onChange(of: pickerDate) { _, newValue in
                            chosenDate = LocalDate.from(date: newValue, timeZone: store.clock.timeZone)
                        }
                }

                Section {
                    Button {
                        store.rescheduleTask(task, to: chosenDate)
                        dismiss()
                    } label: {
                        Text("Konfirmasi Pindah ke \(PLAFormatters.shortDate(chosenDate))")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Jadwal tidak diubah sampai Anda menekan tombol konfirmasi di atas. Smart Reminder akan dihitung ulang otomatis.")
                }
            }
            .navigationTitle("Jadwalkan Ulang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .onAppear {
                calendarCounts = store.calendarEventCountsForNext7Days()
                select(bestOption.date)
            }
        }
    }

    private func optionSummary(_ opt: SmartRescheduleOption) -> String {
        var parts: [String] = ["Skor \(opt.workloadScore)"]
        if opt.totalTaskCount == 0 {
            parts.append("0 tugas")
        } else {
            parts.append("\(opt.totalTaskCount) tugas")
        }
        if store.settings.useCalendarForReschedule {
            parts.append("\(opt.calendarEventCount) agenda kalender")
        }
        return parts.joined(separator: " • ")
    }

    private func select(_ date: LocalDate) {
        chosenDate = date
        pickerDate = date.toDate(minutesFromMidnight: 9 * 60, timeZone: store.clock.timeZone)
    }

    private func quickOptionRow(_ title: String, date: LocalDate) -> some View {
        Button {
            select(date)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(PLAFormatters.shortDate(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if chosenDate == date {
                    Image(systemName: "checkmark")
                        .foregroundStyle(PLATokens.Colors.accent)
                        .fontWeight(.semibold)
                }
            }
            .frame(minHeight: PLATokens.minTouchTarget)
        }
        .buttonStyle(.plain)
    }
}
