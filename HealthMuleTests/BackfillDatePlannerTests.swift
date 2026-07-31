import Foundation
import HealthMuleCore
import XCTest
@testable import HealthMule

final class BackfillDatePlannerTests: XCTestCase {
    func testThirtyDayRangeIncludesEveryLocalCalendarDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let today = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 23)
            )
        )

        let dates = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2026-06-24"),
            through: today.addingTimeInterval(23 * 60 * 60),
            excluding: [],
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 30)
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2026-06-24")))
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2026-06-25")))
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2026-07-23")))
    }

    func testMissingDayIsRepairedEvenWhenSurroundingDaysExist() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let today = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 23)
            )
        )
        let allDates = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2026-06-24"),
            through: today,
            excluding: [],
            calendar: calendar
        )
        let missing = try LocalDate(rawValue: "2026-06-25")

        let repair = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2026-06-24"),
            through: today,
            excluding: allDates.subtracting([missing]),
            calendar: calendar
        )

        XCTAssertEqual(repair, Set([missing]))
    }

    func testFuturePersistedStartDoesNotMoveBackward() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let today = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 23)
            )
        )

        let dates = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2026-07-24"),
            through: today,
            excluding: [],
            calendar: calendar
        )

        XCTAssertTrue(dates.isEmpty)
    }

    func testRollingWindowNeverPrecedesSelectedStart() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let today = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 23)
            )
        )

        let dates = try BackfillDatePlanner.recentDates(
            through: today,
            count: 3,
            notBefore: LocalDate(rawValue: "2026-07-23"),
            calendar: calendar
        )

        XCTAssertEqual(
            dates,
            Set([try LocalDate(rawValue: "2026-07-23")])
        )
    }

    func testVO2HistoryStartDoesNotReachIntoOlderExistingRecords() throws {
        let requestedStart = Date(timeIntervalSince1970: 2_000)

        let resolved = LiveSyncCoordinator.effectiveHistoryStart(
            requestedStart: requestedStart,
            existingRecordDates: [
                try LocalDate(rawValue: "2026-06-01"),
                try LocalDate(rawValue: "2026-07-01"),
            ]
        )

        XCTAssertEqual(resolved, requestedStart)
    }

    func testVO2HistoryStartAcceptsAnExpandedEarlierSelection() throws {
        let expandedStart = Date(timeIntervalSince1970: 1_000)

        let resolved = LiveSyncCoordinator.effectiveHistoryStart(
            requestedStart: expandedStart,
            existingRecordDates: [
                try LocalDate(rawValue: "2026-07-01")
            ]
        )

        XCTAssertEqual(resolved, expandedStart)
    }

    func testCalendarDayIterationSurvivesDaylightSavingTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let end = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 3, day: 20)
            )
        )

        let dates = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2026-02-19"),
            through: end,
            excluding: [],
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 30)
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2026-03-08")))
    }

    func testCalendarDayIterationSurvivesMidnightDaylightSavingTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        let calendar = LocalDayCalendar.make(timeZone: timeZone)
        let end = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2019,
                    month: 10,
                    day: 7,
                    hour: 12
                )
            )
        )

        let dates = try BackfillDatePlanner.missingDates(
            from: LocalDate(rawValue: "2019-09-08"),
            through: end,
            excluding: [],
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 30)
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2019-09-08")))
        XCTAssertTrue(dates.contains(try LocalDate(rawValue: "2019-10-07")))
    }
}
