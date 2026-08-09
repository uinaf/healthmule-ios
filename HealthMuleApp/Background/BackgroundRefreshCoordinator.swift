@preconcurrency import BackgroundTasks
import Foundation

@MainActor
enum BackgroundRefreshCoordinator {
    static let identifier = "dev.uinaf.healthmule.refresh"

    static func schedule() async -> BackgroundRefreshScheduleResult {
        let requestIdentifier = identifier
        let hasExistingRequest = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(
                    returning: requests.contains {
                        $0.identifier == requestIdentifier
                    }
                )
            }
        }
        guard shouldSubmit(hasExistingRequest: hasExistingRequest) else {
            return .existingRequestKept
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            return .submitted
        } catch {
            let nsError = error as NSError
            return .failed(
                scheduleFailure(domain: nsError.domain, code: nsError.code)
            )
        }
    }

    static func shouldSubmit(hasExistingRequest: Bool) -> Bool {
        !hasExistingRequest
    }

    static func scheduleFailure(
        domain: String,
        code: Int
    ) -> BackgroundRefreshScheduleFailure {
        guard domain == BGTaskScheduler.errorDomain else {
            return .unknown
        }
        switch code {
        case 1:
            return .unavailable
        case 2:
            return .tooManyPendingRequests
        case 3:
            return .notPermitted
        case 4:
            return .immediateRunIneligible
        default:
            return .unknown
        }
    }
}
