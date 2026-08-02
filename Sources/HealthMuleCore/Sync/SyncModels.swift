import Foundation

public struct ExportArtifactID: Codable, Hashable, Comparable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case daily
        case manifest
    }

    public let kind: Kind
    public let date: LocalDate?

    public static let manifest = ExportArtifactID(kind: .manifest, date: nil)

    public static func daily(_ date: LocalDate) -> ExportArtifactID {
        ExportArtifactID(kind: .daily, date: date)
    }

    public init(kind: Kind, date: LocalDate?) {
        precondition(
            (kind == .daily && date != nil) || (kind == .manifest && date == nil),
            "Daily artifacts require a date; manifest artifacts must not have one."
        )
        self.kind = kind
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let date = try container.decodeIfPresent(LocalDate.self, forKey: .date)
        guard
            (kind == .daily && date != nil)
                || (kind == .manifest && date == nil)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Daily artifacts require a date; manifests must not have one."
            )
        }
        self.kind = kind
        self.date = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(date, forKey: .date)
    }

    public var key: String {
        switch kind {
        case .daily:
            "daily:\(date!.rawValue)"
        case .manifest:
            "manifest"
        }
    }

    public var relativePath: String {
        switch kind {
        case .daily:
            "daily/\(date!.rawValue).json"
        case .manifest:
            "manifest.json"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == .daily
        }
        return lhs.key < rhs.key
    }
}

public struct ExportArtifact: Equatable, Sendable {
    public let id: ExportArtifactID
    public let revision: Int
    public let contents: Data

    public init(id: ExportArtifactID, revision: Int, contents: Data) {
        self.id = id
        self.revision = revision
        self.contents = contents
    }
}

public enum RetryBlockReason: String, Codable, Equatable, Sendable {
    case reauthorizationRequired
    case permanentFailure
}

public struct RetryQueueItem: Codable, Equatable, Sendable {
    public let artifactID: ExportArtifactID
    public let revision: Int
    public var attemptCount: Int
    public var notBefore: Date
    public var blockReason: RetryBlockReason?
    public var lastErrorCode: String?

    public init(
        artifactID: ExportArtifactID,
        revision: Int,
        attemptCount: Int = 0,
        notBefore: Date = Date(timeIntervalSince1970: 0),
        blockReason: RetryBlockReason? = nil,
        lastErrorCode: String? = nil
    ) {
        self.artifactID = artifactID
        self.revision = revision
        self.attemptCount = attemptCount
        self.notBefore = notBefore
        self.blockReason = blockReason
        self.lastErrorCode = lastErrorCode
    }
}

public enum StageResult: Equatable, Sendable {
    case unchanged(ExportArtifactID, revision: Int)
    case staged(ExportArtifactID, revision: Int)
}

public struct RetryPolicy: Equatable, Sendable {
    public var initialDelay: TimeInterval
    public var maximumDelay: TimeInterval
    public var jitterRatio: Double

    public init(
        initialDelay: TimeInterval = 5,
        maximumDelay: TimeInterval = 6 * 60 * 60,
        jitterRatio: Double = 0.2
    ) {
        precondition(initialDelay >= 0)
        precondition(maximumDelay >= initialDelay)
        precondition((0...1).contains(jitterRatio))
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.jitterRatio = jitterRatio
    }

    public func delay(afterFailure attemptCount: Int, randomUnit: Double) -> TimeInterval {
        let exponent = max(0, min(attemptCount - 1, 30))
        let exponential = min(maximumDelay, initialDelay * pow(2, Double(exponent)))
        let clampedRandom = min(1, max(0, randomUnit))
        let jitterMultiplier = 1 + jitterRatio * ((2 * clampedRandom) - 1)
        return min(maximumDelay, max(0, exponential * jitterMultiplier))
    }
}

public enum ExportDestinationError: Error, Equatable, Sendable {
    case transient(code: String, retryAfter: Date? = nil)
    case reauthorizationRequired(code: String)
    case permanent(code: String)
}

public protocol ExportArtifactDestination: Sendable {
    /// This operation must upsert by stable remote identity, making retries safe.
    func upsert(_ artifact: ExportArtifact) async throws
}

public protocol DailyRecordProvider: Sendable {
    func record(for date: LocalDate) async throws -> DailyHealthRecord
}

public protocol SyncClock: Sendable {
    func now() async -> Date
}

public struct SystemSyncClock: SyncClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }
}

public protocol ManifestTimeZoneProvider: Sendable {
    func currentIdentifier() async -> String
}

public struct SystemManifestTimeZoneProvider: ManifestTimeZoneProvider {
    public init() {}

    public func currentIdentifier() async -> String {
        TimeZone.autoupdatingCurrent.identifier
    }
}

public protocol RetryJitterSource: Sendable {
    func nextUnitIntervalValue() async -> Double
}

public struct SystemRetryJitterSource: RetryJitterSource {
    public init() {}

    public func nextUnitIntervalValue() async -> Double {
        Double.random(in: 0...1)
    }
}

public struct SyncFailureSummary: Equatable, Sendable {
    public let artifactID: ExportArtifactID
    public let code: String
    public let blocked: Bool

    public init(artifactID: ExportArtifactID, code: String, blocked: Bool) {
        self.artifactID = artifactID
        self.code = code
        self.blocked = blocked
    }
}

public struct SyncReport: Equatable, Sendable {
    public var stagedDailyCount = 0
    public var unchangedDailyCount = 0
    public var uploadedDailyCount = 0
    public var manifestUploaded = false
    public var failures: [SyncFailureSummary] = []
    public var pendingUploadCount = 0

    public init() {}
}

public struct UploadProgress: Equatable, Sendable {
    public let settledArtifacts: Int
    public let totalArtifacts: Int

    public init(settledArtifacts: Int, totalArtifacts: Int) {
        self.settledArtifacts = settledArtifacts
        self.totalArtifacts = totalArtifacts
    }
}

public typealias UploadProgressObserver =
    @Sendable (UploadProgress) async -> Void

public enum FileSyncStoreError: Error, Equatable, Sendable {
    case unsupportedStateVersion(Int)
    case missingArtifact(String)
    case invalidArtifact(String)
}
