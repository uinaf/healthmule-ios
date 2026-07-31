import Foundation
import HealthRelayCore
import OSLog

struct DiagnosticErrorCode: Equatable, Sendable {
    fileprivate let value: String

    init(capturing error: any Error) {
        value = String(reflecting: type(of: error))
    }
}

enum DiagnosticSyncFailureCode: String, Sendable {
    case accountNotReady = "drive_account_not_ready"
    case destinationChanged = "drive_destination_changed"
    case invalidResponse = "drive_invalid_response"
    case missingDailyDate = "missing_daily_date"
    case reauthorizationRequired = "drive_reauthorization_required"
    case remote = "drive_remote"
    case tokenRefresh = "google_token_refresh"
    case transport = "drive_transport"
    case unknown

    init(_ failure: SyncFailureSummary) {
        switch failure.code {
        case "drive_account_not_ready":
            self = .accountNotReady
        case "drive_destination_changed":
            self = .destinationChanged
        case "drive_invalid_response":
            self = .invalidResponse
        case "missing_daily_date":
            self = .missingDailyDate
        case "drive_reauthorization_required":
            self = .reauthorizationRequired
        case "google_token_refresh":
            self = .tokenRefresh
        case let code where code.hasPrefix("transport_"):
            self = .transport
        case let code where code.hasPrefix("drive_"):
            self = .remote
        default:
            self = .unknown
        }
    }
}

struct DiagnosticCoreReport: Sendable {
    fileprivate let failedCount: Int
    fileprivate let failureCodes: [DiagnosticSyncFailureCode]
    fileprivate let pendingCount: Int
    fileprivate let stagedCount: Int
    fileprivate let unchangedCount: Int
    fileprivate let uploadedCount: Int

    init(_ report: SyncReport) {
        failedCount = report.failures.count
        failureCodes = report.failures
            .map(DiagnosticSyncFailureCode.init)
            .sorted { $0.rawValue < $1.rawValue }
        pendingCount = report.pendingUploadCount
        stagedCount = report.stagedDailyCount
        unchangedCount = report.unchangedDailyCount
        uploadedCount = report.uploadedDailyCount
    }
}

enum DiagnosticInputEvent: Sendable {
    case bootstrapStarted
    case bootstrapFinished
    case healthRequestCompleted
    case healthRequestFailed(DiagnosticErrorCode)
    case googleConnected
    case googleConnectFailed(DiagnosticErrorCode)
    case googleDisconnected
    case googleRestoreFailed(DiagnosticErrorCode)
    case syncStarted(SyncTrigger)
    case syncFinished(
        durationMilliseconds: Int,
        failureCount: Int,
        pendingCount: Int,
        stagedCount: Int,
        uploadedCount: Int
    )
    case syncFailed(DiagnosticErrorCode)
    case syncCoreReport(DiagnosticCoreReport)
    case credentialRestoreResumeFailed(DiagnosticErrorCode)
    case observerStagingFailed(DiagnosticErrorCode)
    case observerUploadFailed(DiagnosticErrorCode)
    case localReset
    case localStorageRestored
    case localStorageRestoreFailed(DiagnosticErrorCode)

    fileprivate var persisted: PersistedDiagnosticInput {
        switch self {
        case .bootstrapStarted:
            .init(category: "lifecycle", event: "bootstrap-started")
        case .bootstrapFinished:
            .init(category: "lifecycle", event: "bootstrap-finished")
        case .healthRequestCompleted:
            .init(category: "authorization", event: "health-request-completed")
        case .healthRequestFailed(let code):
            .error(
                category: "authorization",
                event: "health-request-failed",
                code: code
            )
        case .googleConnected:
            .init(category: "authorization", event: "google-connected")
        case .googleConnectFailed(let code):
            .error(
                category: "authorization",
                event: "google-connect-failed",
                code: code
            )
        case .googleDisconnected:
            .init(category: "authorization", event: "google-disconnected")
        case .googleRestoreFailed(let code):
            .error(
                category: "authorization",
                event: "google-restore-failed",
                code: code
            )
        case .syncStarted(let trigger):
            .init(
                category: "sync",
                event: "started",
                fields: ["trigger": trigger.rawValue]
            )
        case let .syncFinished(
            durationMilliseconds,
            failureCount,
            pendingCount,
            stagedCount,
            uploadedCount
        ):
            .init(
                category: "sync",
                event: "finished",
                fields: [
                    "durationMilliseconds": String(durationMilliseconds),
                    "failureCount": String(failureCount),
                    "pendingCount": String(pendingCount),
                    "stagedCount": String(stagedCount),
                    "uploadedCount": String(uploadedCount),
                ]
            )
        case .syncFailed(let code):
            .error(category: "sync", event: "failed", code: code)
        case .syncCoreReport(let report):
            .init(
                category: "sync",
                event: "core-report",
                fields: [
                    "failedCount": String(report.failedCount),
                    "failureCodes": report.failureCodes
                        .map(\.rawValue)
                        .joined(separator: ","),
                    "pendingCount": String(report.pendingCount),
                    "stagedCount": String(report.stagedCount),
                    "unchangedCount": String(report.unchangedCount),
                    "uploadedCount": String(report.uploadedCount),
                ]
            )
        case .credentialRestoreResumeFailed(let code):
            .error(
                category: "sync",
                event: "credential-restore-resume-failed",
                code: code
            )
        case .observerStagingFailed(let code):
            .error(
                category: "sync",
                event: "observer-staging-failed",
                code: code
            )
        case .observerUploadFailed(let code):
            .error(
                category: "sync",
                event: "observer-upload-failed",
                code: code
            )
        case .localReset:
            .init(category: "state", event: "local-reset")
        case .localStorageRestored:
            .init(category: "state", event: "local-storage-restored")
        case .localStorageRestoreFailed(let code):
            .error(
                category: "state",
                event: "local-storage-restore-failed",
                code: code
            )
        }
    }
}

private struct PersistedDiagnosticInput {
    let category: String
    let event: String
    let fields: [String: String]

    init(
        category: String,
        event: String,
        fields: [String: String] = [:]
    ) {
        self.category = category
        self.event = event
        self.fields = fields
    }

    static func error(
        category: String,
        event: String,
        code: DiagnosticErrorCode
    ) -> Self {
        .init(
            category: category,
            event: event,
            fields: ["errorCode": code.value]
        )
    }
}

struct RecordedDiagnosticEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let event: String
    let fields: [String: String]
}

struct DiagnosticsExport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let systemVersion: String
    let events: [RecordedDiagnosticEvent]
}

actor DiagnosticsRecorder {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.uinaf.healthrelay",
        category: "sync"
    )
    private let now: @Sendable () -> Date
    private let appVersion: String
    private let systemVersion: String
    private let exportDirectory: URL
    private var events: [RecordedDiagnosticEvent] = []
    private static let maximumEventCount = 200

    init(
        now: @escaping @Sendable () -> Date = { .now },
        appVersion: String = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "unknown",
        systemVersion: String =
            ProcessInfo.processInfo.operatingSystemVersionString,
        exportDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HealthRelayDiagnostics",
                isDirectory: true
            )
    ) {
        self.now = now
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.exportDirectory = exportDirectory
    }

    func record(_ input: DiagnosticInputEvent) {
        let persisted = input.persisted
        events.append(
            RecordedDiagnosticEvent(
                id: UUID(),
                timestamp: now(),
                category: persisted.category,
                event: persisted.event,
                fields: persisted.fields
            )
        )
        if events.count > Self.maximumEventCount {
            events.removeFirst(events.count - Self.maximumEventCount)
        }

        logger.info(
            "\(persisted.category, privacy: .public).\(persisted.event, privacy: .public) metadata=\(persisted.fields.description, privacy: .private(mask: .hash))"
        )
    }

    func export() throws -> URL {
        let export = DiagnosticsExport(
            schemaVersion: 1,
            generatedAt: now(),
            appVersion: appVersion,
            systemVersion: systemVersion,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let url = exportDirectory.appendingPathComponent(
            "health-relay-diagnostics.json"
        )
        try encoder.encode(export).write(to: url, options: [.atomic])
        return url
    }
}
