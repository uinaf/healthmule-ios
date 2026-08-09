import Foundation

enum SyncActivityOutcome: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case pending
    case skipped
    case failed
    case interrupted
}

enum SyncActivityReason: String, Codable, Equatable, Sendable {
    case healthNotReady
    case driveNotReady
    case localStorageUnavailable
    case operationInProgress
    case superseded
    case googleReauthorizationRequired
    case driveDestinationChanged
    case reconcileFailed
    case observerStagingFailed
    case observerUploadFailed
    case processInterrupted
}

struct SyncActivityCounts: Codable, Equatable, Sendable {
    let staged: Int
    let uploaded: Int
    let pending: Int
    let failed: Int

    static let zero = SyncActivityCounts(
        staged: 0,
        uploaded: 0,
        pending: 0,
        failed: 0
    )

    var isValid: Bool {
        staged >= 0 && uploaded >= 0 && pending >= 0 && failed >= 0
    }
}

struct SyncActivityReceipt: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    let finishedAt: Date?
    let trigger: SyncTrigger
    let outcome: SyncActivityOutcome
    let reason: SyncActivityReason?
    let counts: SyncActivityCounts

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID,
        startedAt: Date,
        finishedAt: Date? = nil,
        trigger: SyncTrigger,
        outcome: SyncActivityOutcome = .running,
        reason: SyncActivityReason? = nil,
        counts: SyncActivityCounts = .zero
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.trigger = trigger
        self.outcome = outcome
        self.reason = reason
        self.counts = counts
    }

    func finished(
        at date: Date,
        outcome: SyncActivityOutcome,
        reason: SyncActivityReason?,
        counts: SyncActivityCounts
    ) -> SyncActivityReceipt {
        SyncActivityReceipt(
            schemaVersion: schemaVersion,
            id: id,
            startedAt: startedAt,
            finishedAt: date,
            trigger: trigger,
            outcome: outcome,
            reason: reason,
            counts: counts
        )
    }
}

enum BackgroundRefreshScheduleFailure: String, Codable, Equatable, Sendable {
    case unavailable
    case tooManyPendingRequests
    case notPermitted
    case immediateRunIneligible
    case unknown
}

enum BackgroundRefreshScheduleResult: Codable, Equatable, Sendable {
    case submitted
    case existingRequestKept
    case failed(BackgroundRefreshScheduleFailure)
}

struct BackgroundRefreshScheduleReceipt: Codable, Equatable, Sendable {
    let attemptedAt: Date
    let result: BackgroundRefreshScheduleResult
}

struct SyncActivitySummary: Equatable, Sendable {
    let receipts: [SyncActivityReceipt]
    let schedule: BackgroundRefreshScheduleReceipt?

    static let empty = SyncActivitySummary(receipts: [], schedule: nil)

    var latestAutomatic: SyncActivityReceipt? {
        receipts.first { $0.trigger.operationOrigin == .automatic }
    }

    var latestBackgroundRefresh: SyncActivityReceipt? {
        receipts.first { $0.trigger == .backgroundRefresh }
    }
}

enum SyncActivityStoreError: Error, Equatable, Sendable {
    case unreadableState
    case invalidState
    case unsupportedSchema(Int)
    case receiptNotFound
    case writeFailed
}

enum SyncActivityStoragePolicy {
    static let directoryProtection =
        FileProtectionType.completeUntilFirstUserAuthentication
    static let fileWriteOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication,
    ]
    static let excludesFromBackup = true
}

actor SyncActivityStore {
    private struct PersistedState: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var receipts: [SyncActivityReceipt]
        var schedule: BackgroundRefreshScheduleReceipt?

        static let empty = PersistedState(
            schemaVersion: currentSchemaVersion,
            receipts: [],
            schedule: nil
        )
    }

    private static let maximumReceiptCount = 20

    private let directoryURL: URL
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var state: PersistedState?

    init(
        directoryURL: URL,
        now: @escaping @Sendable () -> Date = { .now },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent(
            "sync-activity.json",
            isDirectory: false
        )
        self.now = now
        self.makeID = makeID
    }

    func snapshot() throws -> SyncActivitySummary {
        let state = try loadState()
        return SyncActivitySummary(
            receipts: state.receipts,
            schedule: state.schedule
        )
    }

    func begin(trigger: SyncTrigger) throws -> UUID {
        var candidate = try loadState()
        let receipt = SyncActivityReceipt(
            id: makeID(),
            startedAt: now(),
            trigger: trigger
        )
        candidate.receipts.append(receipt)
        candidate.receipts = Self.newestReceipts(candidate.receipts)
        try persist(candidate)
        state = candidate
        return receipt.id
    }

    func finish(
        id: UUID,
        outcome: SyncActivityOutcome,
        reason: SyncActivityReason? = nil,
        counts: SyncActivityCounts = .zero
    ) throws {
        guard outcome != .running, counts.isValid else {
            throw SyncActivityStoreError.invalidState
        }
        var candidate = try loadState()
        guard let index = candidate.receipts.firstIndex(where: { $0.id == id }) else {
            throw SyncActivityStoreError.receiptNotFound
        }
        candidate.receipts[index] = candidate.receipts[index].finished(
            at: now(),
            outcome: outcome,
            reason: reason,
            counts: counts
        )
        candidate.receipts = Self.newestReceipts(candidate.receipts)
        try persist(candidate)
        state = candidate
    }

    func recordSchedule(_ result: BackgroundRefreshScheduleResult) throws {
        var candidate = try loadState()
        candidate.schedule = BackgroundRefreshScheduleReceipt(
            attemptedAt: now(),
            result: result
        )
        try persist(candidate)
        state = candidate
    }

    private func loadState() throws -> PersistedState {
        if let state {
            return state
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state = .empty
            return .empty
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SyncActivityStoreError.unreadableState
        }
        let decoded: PersistedState
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try decoder.decode(PersistedState.self, from: data)
        } catch {
            throw SyncActivityStoreError.invalidState
        }
        guard decoded.schemaVersion == PersistedState.currentSchemaVersion else {
            throw SyncActivityStoreError.unsupportedSchema(decoded.schemaVersion)
        }
        guard decoded.receipts.allSatisfy(Self.isValid) else {
            throw SyncActivityStoreError.invalidState
        }

        var recovered = decoded
        let interruptedAt = now()
        var didRecover = false
        recovered.receipts = recovered.receipts.map { receipt in
            guard receipt.outcome == .running else { return receipt }
            didRecover = true
            return receipt.finished(
                at: interruptedAt,
                outcome: .interrupted,
                reason: .processInterrupted,
                counts: receipt.counts
            )
        }
        recovered.receipts = Self.newestReceipts(recovered.receipts)
        if didRecover {
            try persist(recovered)
        }
        state = recovered
        return recovered
    }

    private func persist(_ candidate: PersistedState) throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey:
                        SyncActivityStoragePolicy.directoryProtection
                ]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(candidate).write(
                to: fileURL,
                options: SyncActivityStoragePolicy.fileWriteOptions
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup =
                SyncActivityStoragePolicy.excludesFromBackup
            var mutableURL = fileURL
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw SyncActivityStoreError.writeFailed
        }
    }

    private static func newestReceipts(
        _ receipts: [SyncActivityReceipt]
    ) -> [SyncActivityReceipt] {
        Array(
            receipts.sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.id.uuidString > $1.id.uuidString
                }
                return $0.startedAt > $1.startedAt
            }.prefix(maximumReceiptCount)
        )
    }

    private static func isValid(_ receipt: SyncActivityReceipt) -> Bool {
        guard
            receipt.schemaVersion == SyncActivityReceipt.currentSchemaVersion,
            receipt.counts.isValid
        else {
            return false
        }
        if receipt.outcome == .running {
            return receipt.finishedAt == nil && receipt.reason == nil
        }
        return receipt.finishedAt != nil
    }
}
