@preconcurrency import HealthKit
import Foundation
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
            store.dates(forDeletedUUID: sampleID),
            Set([affectedDate])
        )
        XCTAssertEqual(
            store.dates(forDeletedUUID: replayedSampleID),
            Set([replayedDate])
        )

        let reopened = HealthAnchorStore(directoryURL: directory)
        XCTAssertEqual(
            reopened.dates(forDeletedUUID: sampleID),
            Set([affectedDate])
        )
        XCTAssertEqual(
            reopened.dates(forDeletedUUID: replayedSampleID),
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
        let persistedDirectDates = reopened.dates(
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
}
