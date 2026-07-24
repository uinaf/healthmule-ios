import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

final class FixtureContractTests: XCTestCase {
    @MainActor
    func testLateWorkoutMapsBackToPersistedLocalDay() throws {
        let fixture = try decode(
            LateWorkoutFixture.self,
            named: "late-workout"
        )
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayBoundaryStore(directoryURL: directory)
        let exportedDate = try LocalDate(
            rawValue: fixture.initiallyExportedDate
        )
        _ = try store.boundary(
            for: exportedDate,
            currentTimeZone: try XCTUnwrap(
                TimeZone(identifier: "Europe/Istanbul")
            )
        )
        var fallbackCalendar = Calendar(identifier: .gregorian)
        fallbackCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/New_York")
        )

        let affectedDates = store.dateKeys(
            overlappingStart: fixture.changedSample.startedAt,
            end: fixture.changedSample.endedAt,
            fallbackCalendar: fallbackCalendar
        )

        XCTAssertEqual(affectedDates, Set(fixture.expectedAffectedDates))
    }

    @MainActor
    func testExistingDateKeepsOriginalTimezoneAndFilename() throws {
        let fixture = try decode(
            TimezoneChangeFixture.self,
            named: "timezone-change"
        )
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayBoundaryStore(directoryURL: directory)
        let localDate = try LocalDate(rawValue: fixture.existing.date)
        _ = try store.boundary(
            for: localDate,
            currentTimeZone: try XCTUnwrap(
                TimeZone(identifier: fixture.existing.timeZone)
            )
        )

        let restored = try store.boundary(
            for: localDate,
            currentTimeZone: try XCTUnwrap(
                TimeZone(identifier: fixture.currentTimeZone)
            )
        )

        XCTAssertEqual(restored.date.rawValue, fixture.expected.date)
        XCTAssertEqual(
            restored.timeZoneIdentifier,
            fixture.expected.timeZone
        )
        XCTAssertEqual(
            "\(restored.date.rawValue).json",
            fixture.expected.fileName
        )
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        named name: String
    ) throws -> Value {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "json")
        let data = try Data(contentsOf: XCTUnwrap(url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "health-relay-fixture-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private struct LateWorkoutFixture: Decodable {
    struct ChangedSample: Decodable {
        let startedAt: Date
        let endedAt: Date
    }

    let initiallyExportedDate: String
    let changedSample: ChangedSample
    let expectedAffectedDates: [String]
}

private struct TimezoneChangeFixture: Decodable {
    struct Day: Decodable {
        let date: String
        let timeZone: String
        let fileName: String
    }

    let existing: Day
    let currentTimeZone: String
    let expected: Day
}
