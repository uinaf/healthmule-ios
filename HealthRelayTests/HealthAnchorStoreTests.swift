@preconcurrency import HealthKit
import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

@MainActor
final class HealthAnchorStoreTests: XCTestCase {
    func testDeletionMappingSurvivesAnchorWriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-anchor-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthAnchorStore(directoryURL: directory)
        let sampleID = UUID()
        let affectedDate = "2026-07-23"
        let replayedSampleID = UUID()
        let replayedDate = "2026-07-24"

        try store.commit(
            metric: .stepCount,
            anchor: HKQueryAnchor(fromValue: 1),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [sampleID: [affectedDate]],
            deletedUUIDs: []
        )

        let anchorURL = directory.appendingPathComponent(
            "stepCount.anchor",
            isDirectory: false
        )
        try FileManager.default.removeItem(at: anchorURL)
        try FileManager.default.createDirectory(
            at: anchorURL,
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(
            try store.commit(
                metric: .stepCount,
                anchor: HKQueryAnchor(fromValue: 2),
                queryStart: Date(timeIntervalSince1970: 2_000),
                sampleDates: [replayedSampleID: [replayedDate]],
                deletedUUIDs: [sampleID]
            )
        )
        XCTAssertEqual(
            try store.dates(forDeletedUUID: sampleID),
            Set([affectedDate])
        )
        XCTAssertEqual(
            try store.dates(forDeletedUUID: replayedSampleID),
            Set([replayedDate])
        )

        let reopened = HealthAnchorStore(directoryURL: directory)
        XCTAssertEqual(
            try reopened.dates(forDeletedUUID: sampleID),
            Set([affectedDate])
        )
        XCTAssertEqual(
            try reopened.dates(forDeletedUUID: replayedSampleID),
            Set([replayedDate])
        )
    }

    func testStoredSleepMappingRebuildsPlausibleSessionEndingDate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-sleep-anchor-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthAnchorStore(directoryURL: directory)
        let sampleID = UUID()

        try store.commit(
            metric: .sleep,
            anchor: HKQueryAnchor(fromValue: 1),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [sampleID: ["2026-07-23"]],
            deletedUUIDs: []
        )

        let reopened = HealthAnchorStore(directoryURL: directory)
        let persistedDirectDates = try reopened.dates(
            forDeletedUUID: sampleID
        )

        XCTAssertEqual(persistedDirectDates, ["2026-07-23"])
        XCTAssertEqual(
            try HealthChangeDateMapper.reconciliationDates(
                for: .sleep,
                directlyAffectedDates: persistedDirectDates
            ),
            ["2026-07-23", "2026-07-24"]
        )
    }

    func testMissingSampleIndexIsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-missing-index-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthAnchorStore(directoryURL: directory)

        XCTAssertFalse(try store.inspectSampleIndex())
        XCTAssertTrue(
            try store.dates(forDeletedUUID: UUID()).isEmpty
        )
    }

    func testMissingSampleIndexWithAnchorDomainIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-partial-index-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(
            to: directory.appendingPathComponent("stepCount.anchor")
        )
        try JSONEncoder().encode(Date(timeIntervalSince1970: 1_000)).write(
            to: directory.appendingPathComponent(
                "stepCount.query-start"
            )
        )
        let store = HealthAnchorStore(directoryURL: directory)

        XCTAssertThrowsError(try store.inspectSampleIndex()) { error in
            XCTAssertEqual(
                error as? HealthAnchorStoreError,
                .invalidSampleIndex
            )
        }
        XCTAssertThrowsError(
            try store.dates(forDeletedUUID: UUID())
        ) { error in
            XCTAssertEqual(
                error as? HealthAnchorStoreError,
                .invalidSampleIndex
            )
        }
    }

    func testInvalidSampleIndexIsSurfacedWithoutCachingEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-invalid-index-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("sample-index.json"),
            options: .atomic
        )
        let store = HealthAnchorStore(directoryURL: directory)

        XCTAssertThrowsError(try store.inspectSampleIndex()) { error in
            XCTAssertEqual(
                error as? HealthAnchorStoreError,
                .invalidSampleIndex
            )
        }
        XCTAssertThrowsError(
            try store.dates(forDeletedUUID: UUID())
        ) { error in
            XCTAssertEqual(
                error as? HealthAnchorStoreError,
                .invalidSampleIndex
            )
        }
    }

    func testCorruptIndexRecoveryResetsAllAnchorsBeforeReplay() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-reset-index-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthAnchorStore(directoryURL: directory)
        let originalID = UUID()
        try store.commit(
            metric: .stepCount,
            anchor: HKQueryAnchor(fromValue: 1),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [originalID: ["2026-07-23"]],
            deletedUUIDs: []
        )
        try store.commit(
            metric: .bodyMass,
            anchor: HKQueryAnchor(fromValue: 2),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [:],
            deletedUUIDs: []
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("sample-index.json"),
            options: .atomic
        )

        XCTAssertThrowsError(try store.inspectSampleIndex())
        try store.reset()

        XCTAssertNil(store.anchor(for: .stepCount))
        XCTAssertNil(store.anchor(for: .bodyMass))
        XCTAssertNil(store.queryStart(for: .stepCount))
        XCTAssertTrue(
            try store.dates(forDeletedUUID: originalID).isEmpty
        )

        let replayedID = UUID()
        try store.commit(
            metric: .stepCount,
            anchor: HKQueryAnchor(fromValue: 3),
            queryStart: Date(timeIntervalSince1970: 2_000),
            sampleDates: [replayedID: ["2026-07-24"]],
            deletedUUIDs: []
        )
        XCTAssertEqual(
            try store.dates(forDeletedUUID: replayedID),
            ["2026-07-24"]
        )
    }

    func testClientRecoversCorruptAuxiliaryStateFromDurableRecords() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-client-recovery-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let anchorDirectory = root.appendingPathComponent(
            "anchors",
            isDirectory: true
        )
        let boundaryDirectory = root.appendingPathComponent(
            "boundaries",
            isDirectory: true
        )
        let anchorStore = HealthAnchorStore(
            directoryURL: anchorDirectory
        )
        try anchorStore.commit(
            metric: .stepCount,
            anchor: HKQueryAnchor(fromValue: 1),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [UUID(): ["2026-09-06"]],
            deletedUUIDs: []
        )
        try Data("not-json".utf8).write(
            to: anchorDirectory.appendingPathComponent(
                "sample-index.json"
            ),
            options: .atomic
        )
        try FileManager.default.createDirectory(
            at: boundaryDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: boundaryDirectory.appendingPathComponent(
                "day-boundaries.json"
            ),
            options: .atomic
        )
        let record = try auxiliaryRecoveryRecord()
        let client = HealthKitClient(
            anchorDirectoryURL: anchorDirectory,
            dayBoundaryDirectoryURL: boundaryDirectory,
            defaultsSuiteName: "HealthAnchorStoreTests.\(UUID().uuidString)"
        )

        let summary = try await client.recoverAuxiliaryState(
            from: [record]
        )

        XCTAssertEqual(
            summary,
            HealthAuxiliaryRecoverySummary(
                resetAnchors: true,
                rebuiltBoundaryCount: 1
            )
        )
        XCTAssertNil(
            HealthAnchorStore(
                directoryURL: anchorDirectory
            ).anchor(for: .stepCount)
        )
        let rebuilt = try DayBoundaryStore(
            directoryURL: boundaryDirectory
        ).boundary(
            for: record.date,
            currentTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(rebuilt.timeZoneIdentifier, record.timeZone)
        XCTAssertEqual(
            rebuilt.end.timeIntervalSince(rebuilt.start),
            23 * 60 * 60
        )
    }
}

private func auxiliaryRecoveryRecord() throws -> DailyHealthRecord {
    DailyHealthRecord(
        date: try LocalDate(rawValue: "2026-09-06"),
        timeZone: "America/Santiago",
        generatedAt: try ISO8601Timestamp(
            rawValue: "2026-09-06T12:00:00-03:00"
        ),
        metrics: DailyHealthMetrics(),
        workouts: [],
        totals: WorkoutTotals(
            workoutMinutes: 0,
            workoutActiveEnergyKcal: 0
        ),
        sources: HealthRecordSources(
            deviceNames: [],
            sampleCount: 0
        )
    )
}
