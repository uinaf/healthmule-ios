import Foundation
@testable import HealthMuleCore

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("health-mule-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeRecord(
    date: String = "2026-07-23",
    timeZone: String = "Europe/Istanbul",
    generatedAt: String = "2026-07-23T18:10:00+03:00",
    steps: Int? = 10,
    additionalFields: [String: JSONValue] = [:]
) throws -> DailyHealthRecord {
    DailyHealthRecord(
        date: try LocalDate(rawValue: date),
        timeZone: timeZone,
        generatedAt: try ISO8601Timestamp(rawValue: generatedAt),
        metrics: DailyHealthMetrics(steps: steps),
        workouts: [],
        totals: WorkoutTotals(
            workoutMinutes: 0,
            workoutActiveEnergyKcal: 0
        ),
        sources: HealthRecordSources(
            deviceNames: ["iPhone"],
            sampleCount: 1
        ),
        additionalFields: additionalFields
    )
}

actor TestRecordProvider: DailyRecordProvider {
    private var records: [LocalDate: DailyHealthRecord]

    init(records: [DailyHealthRecord]) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.date, $0) })
    }

    func record(for date: LocalDate) async throws -> DailyHealthRecord {
        guard let record = records[date] else {
            throw TestError.missingRecord
        }
        return record
    }

    func set(_ record: DailyHealthRecord) {
        records[record.date] = record
    }
}

actor TestDestination: ExportArtifactDestination {
    enum FailureMode: Sendable {
        case none
        case transientAfterWriteOnce
        case reauthorization
        case permanent
    }

    private var files: [String: Data] = [:]
    private var callCounts: [String: Int] = [:]
    private var failureModes: [String: FailureMode] = [:]

    func setFailureMode(_ mode: FailureMode, for id: ExportArtifactID) {
        failureModes[id.key] = mode
    }

    func upsert(_ artifact: ExportArtifact) async throws {
        callCounts[artifact.id.key, default: 0] += 1
        switch failureModes[artifact.id.key, default: .none] {
        case .none:
            files[artifact.id.key] = artifact.contents
        case .transientAfterWriteOnce:
            files[artifact.id.key] = artifact.contents
            failureModes[artifact.id.key] = FailureMode.none
            throw ExportDestinationError.transient(code: "connectionLost")
        case .reauthorization:
            throw ExportDestinationError.reauthorizationRequired(code: "401")
        case .permanent:
            throw ExportDestinationError.permanent(code: "400")
        }
    }

    func callCount(for id: ExportArtifactID) -> Int {
        callCounts[id.key, default: 0]
    }

    func fileCount() -> Int {
        files.count
    }

    func contains(_ id: ExportArtifactID) -> Bool {
        files[id.key] != nil
    }

    func contents(for id: ExportArtifactID) -> Data? {
        files[id.key]
    }
}

actor TestClock: SyncClock {
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() async -> Date {
        value
    }

    func advance(by interval: TimeInterval) {
        value = value.addingTimeInterval(interval)
    }
}

struct FixedJitterSource: RetryJitterSource {
    let value: Double

    func nextUnitIntervalValue() async -> Double {
        value
    }
}

enum TestError: Error {
    case missingRecord
}
