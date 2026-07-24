@preconcurrency import HealthKit
import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

final class SleepSessionSelectorTests: XCTestCase {
    func testPriorSessionIsExcludedFromCurrentDayProvenance() throws {
        let sleepType = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        )
        let boundary = StoredDayBoundary(
            date: try LocalDate(rawValue: "2026-07-23"),
            timeZoneIdentifier: "Europe/Istanbul",
            start: Date(timeIntervalSince1970: 1_753_219_200),
            end: Date(timeIntervalSince1970: 1_753_305_600)
        )
        let priorSession = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: boundary.start.addingTimeInterval(-14 * 60 * 60),
            end: boundary.start.addingTimeInterval(-13 * 60 * 60)
        )
        let selectedSession = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: boundary.start.addingTimeInterval(-60 * 60),
            end: boundary.start.addingTimeInterval(7 * 60 * 60)
        )

        let selectedUUIDs = SleepSessionSelector.sampleUUIDs(
            [priorSession, selectedSession],
            endingIn: boundary,
            completeThrough: boundary.end.addingTimeInterval(12 * 60 * 60)
        )

        XCTAssertEqual(selectedUUIDs, Set([selectedSession.uuid]))
    }

    func testPreMidnightFragmentWaitsForCanonicalSessionEnd() throws {
        let sleepType = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        )
        let boundary = StoredDayBoundary(
            date: try LocalDate(rawValue: "2026-07-23"),
            timeZoneIdentifier: "Europe/Istanbul",
            start: Date(timeIntervalSince1970: 1_753_219_200),
            end: Date(timeIntervalSince1970: 1_753_305_600)
        )
        let fragment = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: boundary.end.addingTimeInterval(-2 * 60 * 60),
            end: boundary.end.addingTimeInterval(-60 * 60)
        )

        let incomplete = SleepSessionSelector.sampleUUIDs(
            [fragment],
            endingIn: boundary,
            completeThrough: boundary.end.addingTimeInterval(2 * 60 * 60)
        )
        let complete = SleepSessionSelector.sampleUUIDs(
            [fragment],
            endingIn: boundary,
            completeThrough: boundary.end.addingTimeInterval(4 * 60 * 60)
        )

        XCTAssertTrue(incomplete.isEmpty)
        XCTAssertEqual(complete, Set([fragment.uuid]))
    }

    func testCrossMidnightFragmentsExportOnlyOnSessionEndingDay() throws {
        let sleepType = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        )
        let firstBoundary = StoredDayBoundary(
            date: try LocalDate(rawValue: "2026-07-23"),
            timeZoneIdentifier: "Europe/Istanbul",
            start: Date(timeIntervalSince1970: 1_753_219_200),
            end: Date(timeIntervalSince1970: 1_753_305_600)
        )
        let nextBoundary = StoredDayBoundary(
            date: try LocalDate(rawValue: "2026-07-24"),
            timeZoneIdentifier: "Europe/Istanbul",
            start: firstBoundary.end,
            end: firstBoundary.end.addingTimeInterval(24 * 60 * 60)
        )
        let earlyFragment = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: firstBoundary.end.addingTimeInterval(-2 * 60 * 60),
            end: firstBoundary.end.addingTimeInterval(-60 * 60)
        )
        let continuingFragment = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: firstBoundary.end.addingTimeInterval(30 * 60),
            end: firstBoundary.end.addingTimeInterval(7 * 60 * 60)
        )
        let samples = [earlyFragment, continuingFragment]
        let completeThrough = firstBoundary.end.addingTimeInterval(12 * 60 * 60)

        XCTAssertTrue(
            SleepSessionSelector.sampleUUIDs(
                samples,
                endingIn: firstBoundary,
                completeThrough: completeThrough
            ).isEmpty
        )
        XCTAssertEqual(
            SleepSessionSelector.sampleUUIDs(
                samples,
                endingIn: nextBoundary,
                completeThrough: completeThrough
            ),
            Set([earlyFragment.uuid, continuingFragment.uuid])
        )
    }

    func testSleepChangeInvalidatesDirectAndFollowingEndingDates() throws {
        XCTAssertEqual(
            try HealthChangeDateMapper.reconciliationDates(
                for: .sleep,
                directlyAffectedDates: ["2026-07-31"]
            ),
            ["2026-07-31", "2026-08-01"]
        )
        XCTAssertEqual(
            try HealthChangeDateMapper.reconciliationDates(
                for: .sleep,
                directlyAffectedDates: ["2024-02-29"]
            ),
            ["2024-02-29", "2024-03-01"]
        )
    }

    func testNonSleepChangeKeepsOnlyDirectlyAffectedDates() throws {
        XCTAssertEqual(
            try HealthChangeDateMapper.reconciliationDates(
                for: .stepCount,
                directlyAffectedDates: ["2026-07-23"]
            ),
            ["2026-07-23"]
        )
    }
}
