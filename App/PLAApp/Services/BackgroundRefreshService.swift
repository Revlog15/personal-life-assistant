import Foundation
import BackgroundTasks
import PLACore
import PLAData

/// Registers and schedules `BGAppRefreshTask` (`id.pla.refresh-notifications`) as a rolling-queue safety layer (PRD §9.3 & V-11).
final class BackgroundRefreshService: @unchecked Sendable {
    static let taskIdentifier = "id.pla.refresh-notifications"

    private let diagnostics: DiagnosticsService
    private let notificationAdapter: NotificationAdapter
    private let settingsStore: SettingsStore

    init(
        diagnostics: DiagnosticsService,
        notificationAdapter: NotificationAdapter,
        settingsStore: SettingsStore
    ) {
        self.diagnostics = diagnostics
        self.notificationAdapter = notificationAdapter
        self.settingsStore = settingsStore
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleAppRefresh(task: refreshTask)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600) // +6 hours per PRD §9.3
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            diagnostics.log(level: "WARN", category: "BGTask", message: "Gagal menjadwalkan BGAppRefresh: \(error.localizedDescription)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let workTask = _Concurrency.Task {
            do {
                let dbManager = try DatabaseManager()
                let store = GRDBStore(dbManager: dbManager)
                let settings = settingsStore.loadSettings()
                let clock = SystemClock()
                let sideload = SideloadExpiryReader.read(
                    manualRefreshDate: settingsStore.loadManualSideloadRefreshDate(),
                    timeZone: clock.timeZone
                )

                let tasks = try store.fetchAllTasks()
                let bills = try store.fetchAllBills()
                let reminders = try store.fetchAllReminders()

                let plan = NotificationQueuePlanner.buildQueue(
                    now: clock.currentLocalDateTime,
                    tasks: tasks,
                    bills: bills,
                    reminders: reminders,
                    settings: settings,
                    sideloadExpiryDate: sideload.expirationDate
                )
                _ = await notificationAdapter.syncQueue(plan: plan, timeZone: clock.timeZone)
                diagnostics.recordBackgroundRefreshRun()
                task.setTaskCompleted(success: true)
            } catch {
                diagnostics.log(level: "ERROR", category: "BGTask", message: "BGAppRefresh error: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }
}
