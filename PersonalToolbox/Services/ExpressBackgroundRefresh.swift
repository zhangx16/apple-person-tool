import BackgroundTasks
import Foundation

/// Best-effort iOS background refresh for explicitly tracked, in-transit packages.
/// iOS decides the actual execution time; manual pull-to-refresh remains available.
enum ExpressBackgroundRefresh {
    static let identifier = "app.parsnip6345.lake8262.express-refresh"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule(after interval: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let operation = Task { @MainActor in
            await ExpressService.shared.refreshTracked()
            task.setTaskCompleted(success: true)
            if ExpressService.shared.packages.contains(where: {
                $0.bucket == .active && $0.isTracked == true
            }) {
                schedule()
            }
        }
        task.expirationHandler = { operation.cancel() }
    }
}
