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
                .stepCount,
                .activeEnergy,
                .restingEnergy,
            ])
        )
    }

    func testReusedQuantitySamplesPreserveProvenanceWithoutDuplicates() throws {
        let phone = HKDevice(
            name: "Phone",
            manufacturer: nil,
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let watch = HKDevice(
            name: "Watch",
            manufacturer: nil,
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let weight = try quantitySample(
            identifier: .bodyMass,
            value: 70,
            unit: .gramUnit(with: .kilo),
            device: phone
        )
        let steps = try quantitySample(
            identifier: .stepCount,
            value: 1_000,
            unit: .count(),
            device: watch
        )
        let restingHeartRate = try quantitySample(
            identifier: .restingHeartRate,
            value: 60,
            unit: .count().unitDivided(by: .minute()),
            device: watch
        )
        let hrv = try quantitySample(
            identifier: .heartRateVariabilitySDNN,
            value: 40,
            unit: .secondUnit(with: .milli),
            device: watch
        )
        let oldSamples = HealthSourceProvenance.uniqueSamples(
            directSamples: [weight, steps, restingHeartRate, hrv],
            reusedQuantitySamples: [],
            selectedSamples: []
        )
        let newSamples = HealthSourceProvenance.uniqueSamples(
            directSamples: [steps],
            reusedQuantitySamples: HealthSourceProvenance.reusedQuantitySamples(
                enabledMetrics: [.bodyMass, .restingHeartRate, .hrvSDNN],
                bodyMass: [weight, weight],
                restingHeartRate: [restingHeartRate],
                hrv: [hrv]
            ),
            selectedSamples: []
        )

        XCTAssertEqual(Set(newSamples.keys), Set(oldSamples.keys))
        XCTAssertEqual(newSamples.count, oldSamples.count)
        XCTAssertEqual(
            Set(newSamples.values.compactMap(\.device?.name)),
            Set(["Phone", "Watch"])
        )
    }

    func testReusedQuantitySamplesOmitDisabledMetrics() throws {
        let weight = try quantitySample(
            identifier: .bodyMass,
            value: 70,
            unit: .gramUnit(with: .kilo),
            device: HKDevice.local()
        )
        let restingHeartRate = try quantitySample(
            identifier: .restingHeartRate,
            value: 60,
            unit: .count().unitDivided(by: .minute()),
            device: HKDevice.local()
        )

        let samples = HealthSourceProvenance.reusedQuantitySamples(
            enabledMetrics: [.restingHeartRate],
            bodyMass: [weight],
            restingHeartRate: [restingHeartRate],
            hrv: []
        )

        XCTAssertEqual(samples.map(\.uuid), [restingHeartRate.uuid])
        XCTAssertFalse(samples.contains { $0.uuid == weight.uuid })
    }

    private func quantitySample(
        identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        device: HKDevice
    ) throws -> HKQuantitySample {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: identifier)
        )
        return HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 1_001),
            device: device,
            metadata: nil
        )
    }
}
