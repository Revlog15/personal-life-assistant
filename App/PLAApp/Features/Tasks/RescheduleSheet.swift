import SwiftUI
import PLACore

/// Quick Reschedule sheet with lightest-day suggestion in next 7 days (PRD F-06 / AC-06.2..06.4).
/// Never mutates the schedule automatically — requires explicit user confirmation.
struct RescheduleSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: PLATask

    @State private var chosenDate: LocalDate
    @State private var pickerDate: Date

    private var suggestion: RescheduleSuggestion {
        RescheduleSuggester.bestDayInNext7Days(
            from: store.today,
            activeTasks: store.tasks,
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

                // Highlighted best-day suggestion (AC-06.2)
                Section("Saran Hari Paling Longgar (7 Hari Ke Depan)") {
                    Button {
                        select(suggestion.date)
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(PLATokens.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PLAFormatters.fullDate(suggestion.date))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(suggestion.existingTaskCount == 0
                                     ? "Belum ada tugas aktif di hari ini"
                                     : "Hanya \(suggestion.existingTaskCount) tugas aktif di hari ini")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if chosenDate == suggestion.date {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(PLATokens.Colors.accent)
                            }
                        }
                        .frame(minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.plain)
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
                select(suggestion.date)
            }
        }
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
