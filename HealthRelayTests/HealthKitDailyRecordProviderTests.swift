@preconcurrency import HealthKit
import XCTest
@testable import HealthRelay

final class HealthKitDailyRecordProviderTests: XCTestCase {
    func testStatisticsResultPreservesValueWhenQuerySucceeds() throws {
        XCTAssertEqual(
            try HealthKitCumulativeResult.resolve(42, error: nil),
            42
        )
        XCTAssertNil(
            try HealthKitCumulativeResult.resolve(nil, error: nil)
        )
    }

    func testStatisticsNoDataResolvesToMissingMetric() throws {
        let noData = NSError(
            domain: HKErrorDomain,
            code: HKError.errorNoData.rawValue
        )

        XCTAssertNil(
            try HealthKitCumulativeResult.resolve(42, error: noData)
        )
    }

    func testStatisticsErrorsOtherThanNoDataRemainFailures() {
        let databaseUnavailable = NSError(
            domain: HKErrorDomain,
            code: HKError.errorDatabaseInaccessible.rawValue
        )
        let unrelatedErrorWithMatchingCode = NSError(
            domain: "HealthRelayTests",
            code: HKError.errorNoData.rawValue
        )

        XCTAssertThrowsError(
            try HealthKitCumulativeResult.resolve(
                42,
                error: databaseUnavailable
            )
        )
        XCTAssertThrowsError(
            try HealthKitCumulativeResult.resolve(
                42,
                error: unrelatedErrorWithMatchingCode
            )
        )
    }

    func testDirectSourceMetricsExcludeSeparatelyAggregatedTypes() {
        XCTAssertEqual(
            HealthSourceSamplePlanner.directMetrics(
                from: Set(HealthMetric.allCases)
            ),
            Set([
                .bodyMass,
                .stepCount,
                .activeEnergy,
                .restingEnergy,
                .restingHeartRate,
                .hrvSDNN,
            ])
        )
    }
}
