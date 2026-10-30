import Foundation
import HealthMuleCore

enum InitialLoadPhase: Equatable, Sendable {
    case loading
    case loaded
}

enum SyncTrigger: String, Codable, Equatable, Sendable {
    case appLaunch
    case foreground
    case manual
    case retry
    case rebuild
    case metricSelection
    case historySelection
    case backgroundRefresh
    case healthObserver
    case watchCompanion

    var operationOrigin: OperationOrigin {
        switch self {
        case
            .manual,
            .retry,
            .rebuild,
            .watchCompanion,
            .metricSelection,
            .historySelection:
            .userInitiated
        case
            .appLaunch,
            .foreground,
            .backgroundRefresh,
            .healthObserver:
            .automatic
        }
    }

    var activityLabel: String {
        switch self {
        case .appLaunch:
            "App launch"
        case .foreground:
            "App foreground"
        case .manual:
            "Manual sync"
        case .retry:
            "Retry uploads"
        case .rebuild:
            "Rebuild"
        case .metricSelection:
            "Metric selection"
        case .historySelection:
            "History selection"
        case .backgroundRefresh:
            "Background refresh"
        case .healthObserver:
            "Health observer"
        case .watchCompanion:
            "Watch request"
        }
    }
}

struct SyncProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case staging
        case uploading

        var unitNoun: String {
            switch self {
            case .staging: "days"
            case .uploading: "files"
            }
        }

        var verb: String {
            switch self {
            case .staging: "Processing"
            case .uploading: "Uploading"
            }
        }
    }

    let phase: Phase
    let completedUnits: Int
    let totalUnits: Int
    let currentDate: LocalDate?

    var presentationText: String {
        let count = "\(phase.verb) \(completedUnits.formatted()) of \(totalUnits.formatted()) \(phase.unitNoun)"
        guard
            let currentDate,
            let day = BackfillDateCodec.date(from: currentDate.rawValue)
        else {
            return count
        }
        return "\(count) · \(day.formatted(date: .abbreviated, time: .omitted))"
    }

    var accessibilityValue: String {
        presentationText
    }
}

struct SyncProgressState: Equatable, Sendable {
    private(set) var progress: SyncProgress?
    private var activeEpoch: UInt64?

    mutating func begin(epoch: UInt64) {
        activeEpoch = epoch
        progress = nil
    }

    mutating func publish(_ progress: SyncProgress, epoch: UInt64) {
        guard activeEpoch == epoch else {
            return
        }
        self.progress = progress
    }

    mutating func clear() {
        activeEpoch = nil
        progress = nil
    }
}

struct SelectionReconciliationQueue: Equatable, Sendable {
    private var hasMetricSelection = false
    private var hasHistorySelection = false

    mutating func enqueue(_ trigger: SyncTrigger) {
        switch trigger {
        case .metricSelection:
            hasMetricSelection = true
        case .historySelection:
            hasHistorySelection = true
        case
            .appLaunch,
            .foreground,
            .manual,
            .retry,
            .rebuild,
            .backgroundRefresh,
            .healthObserver,
            .watchCompanion:
            break
        }
    }

    mutating func beginPass() {
        hasMetricSelection = false
        hasHistorySelection = false
    }

    var followUpTrigger: SyncTrigger? {
        if hasHistorySelection {
            return .historySelection
        }
        if hasMetricSelection {
            return .metricSelection
        }
        return nil
    }
}

struct ReconcileOccupancy: Equatable, Sendable {
    private(set) var occupied = false

    mutating func admit() -> Bool {
        if occupied {
            return false
        }
        occupied = true
        return true
    }

    mutating func release() {
        occupied = false
    }
}

struct ObserverFlushQueue: Equatable, Sendable {
    private(set) var isDraining = false
    private var hasPendingPass = false

    mutating func request() -> Bool {
        hasPendingPass = true
        guard !isDraining else {
            return false
        }
        isDraining = true
        return true
    }

    mutating func beginPass() -> Bool {
        guard hasPendingPass else {
            return false
        }
        hasPendingPass = false
        return true
    }

    mutating func finish() {
        precondition(!hasPendingPass)
        isDraining = false
    }
}

enum OperationKind: Equatable {
    case healthAuthorization
    case googleConnection
    case sync
    case diagnostics
    case localReset
    case driveDeletion
}

enum OperationOrigin: Equatable, Sendable {
    case userInitiated
    case automatic
}

enum OperationState: Equatable {
    case idle
    case working(OperationKind, String)
    case warning(OperationKind, String)
    case succeeded(OperationKind, String)
    case failed(OperationKind, String)

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }

    func isWorking(_ kind: OperationKind) -> Bool {
        if case .working(let operationKind, _) = self {
            return operationKind == kind
        }
        return false
    }

    func isFailure(_ kind: OperationKind) -> Bool {
        if case .failed(let operationKind, _) = self {
            return operationKind == kind
        }
        return false
    }

    func isWarning(_ kind: OperationKind) -> Bool {
        if case .warning(let operationKind, _) = self {
            return operationKind == kind
        }
        return false
    }

    func presented(for origin: OperationOrigin) -> OperationState {
        if origin == .automatic, !isWorking {
            return .idle
        }
        return self
    }
}

enum GoogleConnectionState: Equatable {
    case notConfigured
    case restoring
    case disconnected
    case temporarilyUnavailable
    case reauthorizationRequired
    case authorized(GoogleAccount)
    case driveUnavailable(GoogleAccount)
    case connected(GoogleConnection)

    var account: GoogleAccount? {
        switch self {
        case .authorized(let account),
             .driveUnavailable(let account):
            account
        case .connected(let connection):
            connection.account
        case
            .notConfigured,
            .restoring,
            .disconnected,
            .temporarilyUnavailable,
            .reauthorizationRequired:
            nil
        }
    }

    var isAuthorized: Bool {
        account != nil
    }

    var isDriveReady: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var canDisconnect: Bool {
        switch self {
        case
            .temporarilyUnavailable,
            .reauthorizationRequired,
            .authorized,
            .driveUnavailable,
            .connected:
            true
        case .notConfigured, .restoring, .disconnected:
            false
        }
    }
}

struct GoogleAccount: Equatable, Sendable {
    let id: String
    let email: String?
}

struct GoogleConnection: Equatable, Sendable {
    let account: GoogleAccount
    let folderID: String
    let folderName: String

    var accountName: String? {
        account.email
    }

    var folderURL: URL? {
        URL(string: "https://drive.google.com/drive/folders/\(folderID)")
    }
}

enum MetricReadState: Equatable, Sendable {
    case checking
    case notIncluded
    case notRequested
    case unavailable
    case noReadableData
    case checkFailed
    case readable(lastSampleAt: Date)

    var title: String {
        switch self {
        case .checking:
            "Checking"
        case .notIncluded:
            "Not included"
        case .notRequested:
            "Not requested"
        case .unavailable:
            "Unavailable"
        case .noReadableData:
            "No readable data"
        case .checkFailed:
            "Check failed"
        case .readable:
            "Readable"
        }
    }
}

struct MetricStatus: Identifiable, Equatable, Sendable {
    let metric: HealthMetric
    var state: MetricReadState

    var id: HealthMetric { metric }
}

struct BackgroundDeliveryAdvisory: Equatable, Sendable {
    let metrics: [HealthMetric]

    init?(failedMetrics: Set<HealthMetric>) {
        let metrics = HealthMetric.allCases.filter(failedMetrics.contains)
        guard !metrics.isEmpty else {
            return nil
        }
        self.metrics = metrics
    }

    var title: String {
        "Background updates need another try"
    }

    var message: String {
        let titles = metrics.map(\.title)
        let names: String
        switch titles.count {
        case 1:
            names = titles[0]
        case 2:
            names = titles.joined(separator: " and ")
        default:
            names = titles.dropLast().joined(separator: ", ")
                + ", and \(titles[titles.count - 1])"
        }
        return "Background updates are off for \(names). Open the app to sync."
    }
}

struct BackgroundDeliveryRegistrationState: Equatable, Sendable {
    private(set) var failedEnabledMetrics: Set<HealthMetric> = []

    mutating func apply(
        _ summary: BackgroundDeliveryRegistrationSummary
    ) {
        failedEnabledMetrics = summary.failedEnabledMetrics
    }
}

enum HealthAuthorizationState: Equatable, Sendable {
    case unavailable
    case checking
    case statusUnavailable(previouslyRequested: Bool)
    case notRequested
    case reviewRequired
    case requestCompleted

    var allowsQueries: Bool {
        switch self {
        case .reviewRequired, .requestCompleted:
            true
        case .statusUnavailable(let previouslyRequested):
            previouslyRequested
        case .unavailable, .checking, .notRequested:
            false
        }
    }
}

enum SyncReadiness: Equatable, Sendable {
    case localStorageUnavailable
    case checkingConnections
    case healthUnavailable
    case healthStatusUnavailable(canSync: Bool)
    case healthRequestRequired
    case healthReviewRecommended
    case googleNotConfigured
    case googleDisconnected
    case googleTemporarilyUnavailable
    case googleReauthorizationRequired
    case googleDriveSetupRequired
    case googleDriveUnavailable
    case ready

    static func resolve(
        health: HealthAuthorizationState,
        google: GoogleConnectionState,
        localStorageAvailable: Bool = true
    ) -> SyncReadiness {
        guard localStorageAvailable else {
            return .localStorageUnavailable
        }

        let healthAdvisory: SyncReadiness?
        switch health {
        case .checking:
            return .checkingConnections
        case .unavailable:
            return .healthUnavailable
        case .statusUnavailable(let previouslyRequested):
            guard previouslyRequested else {
                return .healthStatusUnavailable(canSync: false)
            }
            healthAdvisory = .healthStatusUnavailable(canSync: true)
        case .notRequested:
            return .healthRequestRequired
        case .reviewRequired:
            healthAdvisory = .healthReviewRecommended
        case .requestCompleted:
            healthAdvisory = nil
        }

        switch google {
        case .notConfigured:
            return .googleNotConfigured
        case .restoring:
            return .checkingConnections
        case .disconnected:
            return .googleDisconnected
        case .temporarilyUnavailable:
            return .googleTemporarilyUnavailable
        case .reauthorizationRequired:
            return .googleReauthorizationRequired
        case .authorized:
            return .googleDriveSetupRequired
        case .driveUnavailable:
            return .googleDriveUnavailable
        case .connected:
            return healthAdvisory ?? .ready
        }
    }

    var canSync: Bool {
        switch self {
        case .ready, .healthReviewRecommended:
            true
        case .healthStatusUnavailable(let canSync):
            canSync
        default:
            false
        }
    }
}

struct SyncSummary: Equatable, Sendable {
    var lastSuccessfulSyncAt: Date?
    var latestExportedDate: String?
    var pendingUploadCount: Int
    var retryableUploadCount: Int
    var permanentFailureCount: Int

    static let empty = SyncSummary(
        lastSuccessfulSyncAt: nil,
        latestExportedDate: nil,
        pendingUploadCount: 0,
        retryableUploadCount: 0,
        permanentFailureCount: 0
    )

    var lastSyncText: String {
        lastSuccessfulSyncAt?
            .formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? "Never"
    }

    var latestExportedDayText: String {
        guard let latestExportedDate else { return "None" }
        guard let day = try? Date(
            latestExportedDate,
            strategy: Date.ISO8601FormatStyle().year().month().day()
        ) else {
            return latestExportedDate
        }
        // The day is a calendar date, so format it in UTC to keep it intact.
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return day.formatted(style)
    }
}

enum BackfillRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case thirtyDays
    case ninetyDays
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyDays:
            "Last 30 days"
        case .ninetyDays:
            "Last 90 days"
        case .custom:
            "Custom start date"
        }
    }

    func startDate(
        customDate: Date,
        timeZone: TimeZone = .current
    ) -> Date {
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let today = calendar.startOfDay(for: .now)
        switch self {
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -89, to: today) ?? today
        case .custom:
            return calendar.startOfDay(for: customDate)
        }
    }
}

enum LocalDayCalendar {
    static var current: Calendar {
        make(timeZone: .current)
    }

    static func make(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}

enum BackfillDateCodec {
    static func string(
        from date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    static func date(
        from value: String,
        timeZone: TimeZone = .current
    ) -> Date? {
        guard (try? LocalDate(rawValue: value)) != nil else {
            return nil
        }
        return formatter(timeZone: timeZone).date(from: value)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = LocalDayCalendar.make(timeZone: timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
