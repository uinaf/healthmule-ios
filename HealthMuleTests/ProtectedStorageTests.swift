import Foundation
import HealthMuleCore
import XCTest
@testable import HealthMule
@preconcurrency import HealthKit

final class ProtectedStorageTests: XCTestCase {
    func testFileSyncStoreUsesProtectedStorageAndSkipsBackup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileSyncStore(rootDirectory: directory)
        _ = try await store.stageDaily(try makeEmptyDailyRecord())

        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("daily/2026-07-23.json")
        )
        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("sync-state.json")
        )
    }

    @MainActor
    func testHealthAnchorStoreUsesProtectedStorageAndSkipsBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthAnchorStore(directoryURL: directory)
        try store.commit(
            metric: .stepCount,
            anchor: HKQueryAnchor(fromValue: 1),
            queryStart: Date(timeIntervalSince1970: 1_000),
            sampleDates: [:],
            deletedUUIDs: []
        )

        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("sample-index.json")
        )
        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("stepCount.anchor")
        )
    }

    @MainActor
    func testDayBoundaryStoreUsesProtectedStorageAndSkipsBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayBoundaryStore(directoryURL: directory)
        _ = try store.boundary(
            for: LocalDate(rawValue: "2026-07-23"),
            currentTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("day-boundaries.json")
        )
    }

    func testDriveUploadBodyStoreUsesProtectedStorageAndSkipsBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackgroundDriveUploadBodyStore(directoryURL: directory)
        let fileURL = try store.stage(Data("healthmule-upload-body".utf8))
        try assertProtectedAndExcludedFromBackup(fileURL)
    }

    func testDriveMetadataStoreUsesProtectedStorageAndMigratesLegacyDefaults()
        async throws
    {
        let directory = temporaryDirectory()
        let suiteName = "ProtectedStorageTests.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let accountID = "google-user-protection"
        let key = "drive.metadata.v2.\(DriveMetadataStore.accountNamespace(for: accountID))"
        let legacyState = try JSONSerialization.data(
            withJSONObject: [
                "folders": [
                    "rootID": "root-a",
                    "dailyID": "daily-a",
                ],
                "fileIDs": ["manifest": "manifest-a"],
            ]
        )
        defaults.set(legacyState, forKey: key)

        let store = DriveMetadataStore(
            directoryURL: directory,
            defaults: defaults
        )
        let folders = await store.folders(for: accountID)
        let storedFileID = await store.fileID(
            for: "manifest",
            accountID: accountID
        )
        XCTAssertEqual(
            folders,
            DriveFolderSet(rootID: "root-a", dailyID: "daily-a")
        )
        XCTAssertEqual(storedFileID, "manifest-a")
        XCTAssertNil(UserDefaults(suiteName: suiteName)?.data(forKey: key))
        try assertProtectedAndExcludedFromBackup(
            directory.appendingPathComponent("\(key).json")
        )
    }

    func testStorageAssertionRejectsMismatchedProtection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var fileURL = directory.appendingPathComponent("protected.txt")
        try Data("test".utf8).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try fileURL.setResourceValues(values)
        fileURL.removeAllCachedResourceValues()

        XCTAssertEqual(
            try fileURL.resourceValues(forKeys: [.fileProtectionKey])
                .fileProtection,
            .completeUntilFirstUserAuthentication
        )
        let assertionLine: UInt = #line
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { issue in
            issue.type == .assertionFailure
                && issue.sourceCodeContext.location?.lineNumber == Int(assertionLine)
                && issue.compactDescription.hasPrefix("XCTAssertEqual failed")
                && issue.compactDescription.contains("NSURLFileProtection")
        }
        try XCTExpectFailure(
            "The storage assertion must reject a different requested protection class.",
            options: options
        ) {
            XCTAssertNoThrow(
                try PersistedStorageAssertions.assertProtectedAndExcludedFromBackup(
                    fileURL,
                    expectedProtection: .complete,
                    file: #filePath,
                    line: assertionLine
                )
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "healthmule-protection-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func makeEmptyDailyRecord() throws -> DailyHealthRecord {
        DailyHealthRecord(
            date: try LocalDate(rawValue: "2026-07-23"),
            timeZone: "UTC",
            generatedAt: try ISO8601Timestamp(rawValue: "2026-07-23T18:10:00Z"),
            metrics: DailyHealthMetrics(steps: 0),
            workouts: [],
            totals: WorkoutTotals(
                workoutMinutes: 0,
                workoutActiveEnergyKcal: 0
            ),
            sources: HealthRecordSources(
                deviceNames: ["iPhone"],
                sampleCount: 1
            )
        )
    }

    private func assertProtectedAndExcludedFromBackup(_ url: URL) throws {
        try PersistedStorageAssertions.assertProtectedAndExcludedFromBackup(url)
    }
}
