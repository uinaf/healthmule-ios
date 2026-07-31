import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

@MainActor
final class DayBoundaryStoreTests: XCTestCase {
    func testMidnightDSTBoundaryEndsAtTheNextLocalDayStart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-day-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayBoundaryStore(directoryURL: directory)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        let first = try store.boundary(
            for: LocalDate(rawValue: "2026-09-06"),
            currentTimeZone: timeZone
        )
        let second = try store.boundary(
            for: LocalDate(rawValue: "2026-09-07"),
            currentTimeZone: timeZone
        )

        XCTAssertEqual(first.end, second.start)
        XCTAssertEqual(first.end.timeIntervalSince(first.start), 23 * 60 * 60)
    }

    func testLegacyMidnightDSTBoundaryIsNormalizedAndPersisted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-legacy-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try LocalDate(rawValue: "2026-09-06")
        let start = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 6)
            )
        )
        let legacyEnd = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: start)
        )
        let legacy = StoredDayBoundary(
            date: date,
            timeZoneIdentifier: timeZone.identifier,
            start: start,
            end: legacyEnd
        )
        let fileURL = directory.appendingPathComponent("day-boundaries.json")
        try JSONEncoder().encode([date.rawValue: legacy]).write(
            to: fileURL,
            options: .atomic
        )

        let store = DayBoundaryStore(directoryURL: directory)
        let normalized = try store.boundary(
            for: date,
            currentTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        let persisted = try JSONDecoder().decode(
            [String: StoredDayBoundary].self,
            from: Data(contentsOf: fileURL)
        )

        XCTAssertEqual(
            normalized.end,
            calendar.startOfDay(for: legacyEnd)
        )
        XCTAssertEqual(persisted[date.rawValue], normalized)
    }

    func testFailedWriteDoesNotPublishBoundaryInMemory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-failed-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent(
            "day-boundaries.json",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: fileURL,
            withIntermediateDirectories: false
        )
        let store = DayBoundaryStore(directoryURL: directory)
        let date = try LocalDate(rawValue: "2026-07-23")
        let firstTimeZone = try XCTUnwrap(
            TimeZone(identifier: "Europe/Istanbul")
        )

        XCTAssertThrowsError(
            try store.boundary(
                for: date,
                currentTimeZone: firstTimeZone
            )
        )

        try FileManager.default.removeItem(at: fileURL)
        let retryTimeZone = try XCTUnwrap(
            TimeZone(identifier: "America/New_York")
        )
        let retry = try store.boundary(
            for: date,
            currentTimeZone: retryTimeZone
        )
        let persisted = try JSONDecoder().decode(
            [String: StoredDayBoundary].self,
            from: Data(contentsOf: fileURL)
        )

        XCTAssertEqual(
            retry.timeZoneIdentifier,
            retryTimeZone.identifier
        )
        XCTAssertEqual(persisted[date.rawValue], retry)
    }

    func testMissingBoundaryFileIsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-missing-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayBoundaryStore(directoryURL: directory)

        XCTAssertFalse(try store.inspectBoundaries())
    }

    func testInvalidBoundaryFileIsSurfaced() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-invalid-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("day-boundaries.json"),
            options: .atomic
        )
        let store = DayBoundaryStore(directoryURL: directory)

        XCTAssertThrowsError(try store.inspectBoundaries()) { error in
            XCTAssertEqual(
                error as? DayBoundaryStoreError,
                .invalidState
            )
        }
        XCTAssertThrowsError(
            try store.boundary(
                for: LocalDate(rawValue: "2026-07-23"),
                currentTimeZone: TimeZone(secondsFromGMT: 0)!
            )
        ) { error in
            XCTAssertEqual(
                error as? DayBoundaryStoreError,
                .invalidState
            )
        }
    }

    func testRebuildUsesDurableRecordTimezoneAcrossDST() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "health-relay-rebuilt-boundary-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("day-boundaries.json"),
            options: .atomic
        )
        let store = DayBoundaryStore(directoryURL: directory)
        let record = try boundaryTestRecord(
            date: "2026-09-06",
            timeZone: "America/Santiago"
        )

        XCTAssertThrowsError(try store.inspectBoundaries())
        XCTAssertEqual(try store.rebuild(from: [record]), 1)
        let boundary = try store.boundary(
            for: record.date,
            currentTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(
            boundary.timeZoneIdentifier,
            record.timeZone
        )
        XCTAssertEqual(
            boundary.end.timeIntervalSince(boundary.start),
            23 * 60 * 60
        )
        XCTAssertTrue(try store.inspectBoundaries())
    }
}

private func boundaryTestRecord(
    date: String,
    timeZone: String
) throws -> DailyHealthRecord {
    let localDate = try LocalDate(rawValue: date)
    return DailyHealthRecord(
        date: localDate,
        timeZone: timeZone,
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
