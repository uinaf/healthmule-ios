import BackgroundTasks
import Foundation

enum BackgroundRefreshCoordinator {
    static let identifier = "dev.uinaf.healthmule.refresh"

    static func schedule() {
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: identifier
        )
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Scheduling is best-effort; foreground reconciliation remains the
            // durable fallback.
        }
    }
}
