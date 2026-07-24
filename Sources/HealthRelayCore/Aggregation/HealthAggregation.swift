import Foundation

public enum AggregationError: Error, Equatable, Sendable {
    case invalidTimeZone(String)
    case nonFiniteValue(sampleID: String)
    case invalidInterval(sampleID: String)
    case conflictingDuplicateSample(sampleID: String)
}

public struct TimedQuantitySample: Equatable, Sendable {
    public var id: String
    public var measuredAt: Date
    public var value: Double

    public init(id: String, measuredAt: Date, value: Double) {
        self.id = id
        self.measuredAt = measuredAt
        self.value = value
    }
}

public enum SleepStage: String, Codable, Equatable, Sendable {
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
    case inBed

    var contributesToSleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            true
        case .awake, .inBed:
            false
        }
    }
}

public struct SleepSample: Equatable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var stage: SleepStage

    public init(id: String, start: Date, end: Date, stage: SleepStage) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
    }
}

public struct WorkoutSample: Equatable, Sendable {
    public var id: String
    public var type: String
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?

    public init(
        id: String,
        type: String,
        start: Date,
        end: Date,
        activeEnergyKcal: Double?,
        distanceMeters: Double?
    ) {
        self.id = id
        self.type = type
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
    }
}

public struct DailyAggregationInput: Equatable, Sendable {
    public var date: LocalDate
    public var timeZoneIdentifier: String
    public var weightSamples: [TimedQuantitySample]
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var restingEnergyKcal: Double?
    public var restingHeartRateSamples: [TimedQuantitySample]
    public var hrvSamples: [TimedQuantitySample]
    public var vo2MaxSamples: [TimedQuantitySample]
    /// `nil` means no readable sleep result. An empty array is an authorized zero.
    public var sleepSamples: [SleepSample]?
    public var workouts: [WorkoutSample]
    public var sourceDeviceNames: [String]
    public var sampleCount: Int

    public init(
        date: LocalDate,
        timeZoneIdentifier: String,
        weightSamples: [TimedQuantitySample] = [],
        steps: Int? = nil,
        activeEnergyKcal: Double? = nil,
        restingEnergyKcal: Double? = nil,
        restingHeartRateSamples: [TimedQuantitySample] = [],
        hrvSamples: [TimedQuantitySample] = [],
        vo2MaxSamples: [TimedQuantitySample] = [],
        sleepSamples: [SleepSample]? = nil,
        workouts: [WorkoutSample] = [],
        sourceDeviceNames: [String] = [],
        sampleCount: Int = 0
    ) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.weightSamples = weightSamples
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.restingHeartRateSamples = restingHeartRateSamples
        self.hrvSamples = hrvSamples
        self.vo2MaxSamples = vo2MaxSamples
        self.sleepSamples = sleepSamples
        self.workouts = workouts
        self.sourceDeviceNames = sourceDeviceNames
        self.sampleCount = sampleCount
    }
}

public enum DailyHealthRecordAggregator {
    public static func aggregate(
        _ input: DailyAggregationInput,
        generatedAt: Date
    ) throws -> DailyHealthRecord {
        guard let timeZone = TimeZone(identifier: input.timeZoneIdentifier) else {
            throw AggregationError.invalidTimeZone(input.timeZoneIdentifier)
        }
        try validate(input)

        let workoutRecords = try aggregateWorkouts(input.workouts, timeZone: timeZone)
        let workoutMinutes = try derivedSum(
            workoutRecords.map(\.durationMinutes),
            fieldID: "workoutMinutes"
        )
        let workoutEnergy = try derivedSum(
            workoutRecords.compactMap(\.activeEnergyKcal),
            fieldID: "workoutActiveEnergyKcal"
        )

        let metrics = DailyHealthMetrics(
            weightKg: ExportDecimal.quantized(latest(input.weightSamples)?.value),
            steps: input.steps,
            activeEnergyKcal: ExportDecimal.quantized(input.activeEnergyKcal),
            restingEnergyKcal: ExportDecimal.quantized(input.restingEnergyKcal),
            restingHeartRateBpm: ExportDecimal.quantized(
                try arithmeticMean(
                    input.restingHeartRateSamples,
                    fieldID: "restingHeartRateBpm"
                )
            ),
            hrvSdnnMs: ExportDecimal.quantized(
                try arithmeticMean(
                    input.hrvSamples,
                    fieldID: "hrvSdnnMs"
                )
            ),
            vo2MaxMlKgMin: ExportDecimal.quantized(
                latest(input.vo2MaxSamples)?.value
            ),
            sleepMinutes: try ExportDecimal.quantized(
                input.sleepSamples.map(sleepMinutes)
            )
        )

        return DailyHealthRecord(
            date: input.date,
            timeZone: input.timeZoneIdentifier,
            generatedAt: try ISO8601Timestamp(date: generatedAt, timeZone: timeZone),
            metrics: metrics,
            workouts: workoutRecords,
            totals: WorkoutTotals(
                workoutMinutes: workoutMinutes,
                workoutActiveEnergyKcal: workoutEnergy
            ),
            sources: HealthRecordSources(
                deviceNames: Array(Set(input.sourceDeviceNames)).sorted(),
                sampleCount: input.sampleCount
            )
        )
    }

    public static func sleepMinutes(from samples: [SleepSample]) throws -> Double {
        try samples.forEach(validate)
        let intervals = samples
            .filter { $0.stage.contributesToSleep && $0.end > $0.start }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.id < $1.id
            }

        guard var current = intervals.first.map({ ($0.start, $0.end) }) else {
            return 0
        }

        var totalSeconds = 0.0
        for interval in intervals.dropFirst() {
            if interval.start <= current.1 {
                current.1 = max(current.1, interval.end)
            } else {
                try addSleepDuration(
                    from: current.0,
                    to: current.1,
                    totalSeconds: &totalSeconds
                )
                current = (interval.start, interval.end)
            }
        }
        try addSleepDuration(
            from: current.0,
            to: current.1,
            totalSeconds: &totalSeconds
        )
        return normalizedZero(totalSeconds / 60)
    }

    private static func validate(_ input: DailyAggregationInput) throws {
        for sample in input.weightSamples
            + input.restingHeartRateSamples
            + input.hrvSamples
            + input.vo2MaxSamples
        {
            guard
                sample.value.isFinite,
                sample.measuredAt.timeIntervalSinceReferenceDate.isFinite
            else {
                throw AggregationError.nonFiniteValue(sampleID: sample.id)
            }
        }
        for (id, value) in [
            ("activeEnergyKcal", input.activeEnergyKcal),
            ("restingEnergyKcal", input.restingEnergyKcal),
        ] {
            if let value, !value.isFinite {
                throw AggregationError.nonFiniteValue(sampleID: id)
            }
        }
        try input.sleepSamples?.forEach(validate)
        try input.workouts.forEach { workout in
            let duration = workout.end.timeIntervalSince(workout.start)
            guard
                workout.start.timeIntervalSinceReferenceDate.isFinite,
                workout.end.timeIntervalSinceReferenceDate.isFinite,
                duration.isFinite
            else {
                throw AggregationError.nonFiniteValue(sampleID: workout.id)
            }
            guard duration >= 0 else {
                throw AggregationError.invalidInterval(sampleID: workout.id)
            }
            for value in [workout.activeEnergyKcal, workout.distanceMeters] {
                if let value, !value.isFinite {
                    throw AggregationError.nonFiniteValue(sampleID: workout.id)
                }
            }
        }
    }

    private static func validate(_ sample: SleepSample) throws {
        let duration = sample.end.timeIntervalSince(sample.start)
        guard
            sample.start.timeIntervalSinceReferenceDate.isFinite,
            sample.end.timeIntervalSinceReferenceDate.isFinite,
            duration.isFinite
        else {
            throw AggregationError.nonFiniteValue(sampleID: sample.id)
        }
        guard duration >= 0 else {
            throw AggregationError.invalidInterval(sampleID: sample.id)
        }
    }

    private static func addSleepDuration(
        from start: Date,
        to end: Date,
        totalSeconds: inout Double
    ) throws {
        let duration = end.timeIntervalSince(start)
        guard
            duration.isFinite,
            duration >= 0,
            totalSeconds <= Double.greatestFiniteMagnitude - duration
        else {
            throw AggregationError.nonFiniteValue(sampleID: "sleepMinutes")
        }
        totalSeconds += duration
    }

    private static func latest(_ samples: [TimedQuantitySample]) -> TimedQuantitySample? {
        samples.max {
            if $0.measuredAt != $1.measuredAt {
                return $0.measuredAt < $1.measuredAt
            }
            return $0.id < $1.id
        }
    }

    private static func arithmeticMean(
        _ samples: [TimedQuantitySample],
        fieldID: String
    ) throws -> Double? {
        guard !samples.isEmpty else { return nil }
        let orderedValues = samples
            .sorted {
                if $0.measuredAt != $1.measuredAt {
                    return $0.measuredAt < $1.measuredAt
                }
                return $0.id < $1.id
            }
            .map(\.value)
        let total: Double
        do {
            total = try ExportDecimal.sum(orderedValues)
        } catch {
            throw AggregationError.nonFiniteValue(sampleID: fieldID)
        }
        let mean = total / Double(orderedValues.count)
        guard mean.isFinite else {
            throw AggregationError.nonFiniteValue(sampleID: fieldID)
        }
        return normalizedZero(mean)
    }

    private static func aggregateWorkouts(
        _ samples: [WorkoutSample],
        timeZone: TimeZone
    ) throws -> [WorkoutRecord] {
        var uniqueSamples: [String: WorkoutSample] = [:]
        for sample in samples {
            if let existing = uniqueSamples[sample.id], existing != sample {
                throw AggregationError.conflictingDuplicateSample(
                    sampleID: sample.id
                )
            }
            uniqueSamples[sample.id] = sample
        }

        let ordered = uniqueSamples.values.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.end != $1.end { return $0.end > $1.end }
            if $0.start != $1.start { return $0.start > $1.start }
            return $0.type < $1.type
        }

        var records: [WorkoutRecord] = []
        for sample in ordered {
            records.append(
                WorkoutRecord(
                    id: sample.id,
                    type: sample.type,
                    startedAt: try ISO8601Timestamp(
                        date: sample.start,
                        timeZone: timeZone
                    ),
                    endedAt: try ISO8601Timestamp(
                        date: sample.end,
                        timeZone: timeZone
                    ),
                    durationMinutes: ExportDecimal.quantized(
                        sample.end.timeIntervalSince(sample.start) / 60
                    ),
                    activeEnergyKcal: ExportDecimal.quantized(
                        sample.activeEnergyKcal
                    ),
                    distanceMeters: ExportDecimal.quantized(
                        sample.distanceMeters
                    )
                )
            )
        }
        return records.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
    }

    private static func derivedSum(
        _ values: [Double],
        fieldID: String
    ) throws -> Double {
        do {
            return try ExportDecimal.quantizedSum(values)
        } catch {
            throw AggregationError.nonFiniteValue(sampleID: fieldID)
        }
    }

    private static func normalizedZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }

    private static func normalizedZero(_ value: Double?) -> Double? {
        value.map(normalizedZero)
    }

}
