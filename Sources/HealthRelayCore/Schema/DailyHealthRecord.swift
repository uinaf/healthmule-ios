import Foundation

public struct DailyHealthMetrics: Codable, Equatable, Sendable {
    public var weightKg: Double?
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var restingEnergyKcal: Double?
    public var restingHeartRateBpm: Double?
    public var hrvSdnnMs: Double?
    public var vo2MaxMlKgMin: Double?
    public var sleepMinutes: Double?
    public var additionalFields: [String: JSONValue]

    public init(
        weightKg: Double? = nil,
        steps: Int? = nil,
        activeEnergyKcal: Double? = nil,
        restingEnergyKcal: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        hrvSdnnMs: Double? = nil,
        vo2MaxMlKgMin: Double? = nil,
        sleepMinutes: Double? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.weightKg = weightKg
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvSdnnMs = hrvSdnnMs
        self.vo2MaxMlKgMin = vo2MaxMlKgMin
        self.sleepMinutes = sleepMinutes
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case weightKg
        case steps
        case activeEnergyKcal
        case restingEnergyKcal
        case restingHeartRateBpm
        case hrvSdnnMs
        case vo2MaxMlKgMin
        case sleepMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        activeEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
        restingEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .restingEnergyKcal)
        restingHeartRateBpm = try container.decodeIfPresent(
            Double.self,
            forKey: .restingHeartRateBpm
        )
        hrvSdnnMs = try container.decodeIfPresent(Double.self, forKey: .hrvSdnnMs)
        vo2MaxMlKgMin = try container.decodeIfPresent(Double.self, forKey: .vo2MaxMlKgMin)
        sleepMinutes = try container.decodeIfPresent(Double.self, forKey: .sleepMinutes)
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(steps, forKey: .steps)
        try container.encode(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encode(restingEnergyKcal, forKey: .restingEnergyKcal)
        try container.encode(restingHeartRateBpm, forKey: .restingHeartRateBpm)
        try container.encode(hrvSdnnMs, forKey: .hrvSdnnMs)
        try container.encode(vo2MaxMlKgMin, forKey: .vo2MaxMlKgMin)
        try container.encode(sleepMinutes, forKey: .sleepMinutes)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}

public struct WorkoutRecord: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var startedAt: ISO8601Timestamp
    public var endedAt: ISO8601Timestamp
    public var durationMinutes: Double
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var additionalFields: [String: JSONValue]

    public init(
        id: String,
        type: String,
        startedAt: ISO8601Timestamp,
        endedAt: ISO8601Timestamp,
        durationMinutes: Double,
        activeEnergyKcal: Double?,
        distanceMeters: Double?,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case type
        case startedAt
        case endedAt
        case durationMinutes
        case activeEnergyKcal
        case distanceMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        startedAt = try container.decode(ISO8601Timestamp.self, forKey: .startedAt)
        endedAt = try container.decode(ISO8601Timestamp.self, forKey: .endedAt)
        durationMinutes = try container.decode(Double.self, forKey: .durationMinutes)
        activeEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}

public struct WorkoutTotals: Codable, Equatable, Sendable {
    public var workoutMinutes: Double
    public var workoutActiveEnergyKcal: Double
    public var additionalFields: [String: JSONValue]

    public init(
        workoutMinutes: Double,
        workoutActiveEnergyKcal: Double,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.workoutMinutes = workoutMinutes
        self.workoutActiveEnergyKcal = workoutActiveEnergyKcal
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case workoutMinutes
        case workoutActiveEnergyKcal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workoutMinutes = try container.decode(Double.self, forKey: .workoutMinutes)
        workoutActiveEnergyKcal = try container.decode(
            Double.self,
            forKey: .workoutActiveEnergyKcal
        )
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workoutMinutes, forKey: .workoutMinutes)
        try container.encode(workoutActiveEnergyKcal, forKey: .workoutActiveEnergyKcal)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}

public struct HealthRecordSources: Codable, Equatable, Sendable {
    public var deviceNames: [String]
    public var sampleCount: Int
    public var additionalFields: [String: JSONValue]

    public init(
        deviceNames: [String],
        sampleCount: Int,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.deviceNames = deviceNames
        self.sampleCount = sampleCount
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case deviceNames
        case sampleCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceNames = try container.decode([String].self, forKey: .deviceNames)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceNames, forKey: .deviceNames)
        try container.encode(sampleCount, forKey: .sampleCount)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}

public struct DailyHealthRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var date: LocalDate
    public var timeZone: String
    public var generatedAt: ISO8601Timestamp
    public var metrics: DailyHealthMetrics
    public var workouts: [WorkoutRecord]
    public var totals: WorkoutTotals
    public var sources: HealthRecordSources
    public var additionalFields: [String: JSONValue]

    public init(
        schemaVersion: Int = 1,
        date: LocalDate,
        timeZone: String,
        generatedAt: ISO8601Timestamp,
        metrics: DailyHealthMetrics,
        workouts: [WorkoutRecord],
        totals: WorkoutTotals,
        sources: HealthRecordSources,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.timeZone = timeZone
        self.generatedAt = generatedAt
        self.metrics = metrics
        self.workouts = workouts
        self.totals = totals
        self.sources = sources
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case date
        case timeZone
        case generatedAt
        case metrics
        case workouts
        case totals
        case sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        date = try container.decode(LocalDate.self, forKey: .date)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        generatedAt = try container.decode(ISO8601Timestamp.self, forKey: .generatedAt)
        metrics = try container.decode(DailyHealthMetrics.self, forKey: .metrics)
        workouts = try container.decode([WorkoutRecord].self, forKey: .workouts)
        totals = try container.decode(WorkoutTotals.self, forKey: .totals)
        sources = try container.decode(HealthRecordSources.self, forKey: .sources)
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(date, forKey: .date)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(totals, forKey: .totals)
        try container.encode(sources, forKey: .sources)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func preservingUnknownFields(from prior: DailyHealthRecord) -> DailyHealthRecord {
        var result = self
        result.additionalFields = mergedUnknownFields(
            prior: prior.additionalFields,
            current: additionalFields
        )
        result.metrics.additionalFields = mergedUnknownFields(
            prior: prior.metrics.additionalFields,
            current: metrics.additionalFields
        )
        result.totals.additionalFields = mergedUnknownFields(
            prior: prior.totals.additionalFields,
            current: totals.additionalFields
        )
        result.sources.additionalFields = mergedUnknownFields(
            prior: prior.sources.additionalFields,
            current: sources.additionalFields
        )

        var priorWorkouts: [String: WorkoutRecord] = [:]
        for workout in prior.workouts where priorWorkouts[workout.id] == nil {
            priorWorkouts[workout.id] = workout
        }
        result.workouts = workouts.map { workout in
            guard let priorWorkout = priorWorkouts[workout.id] else { return workout }
            var merged = workout
            merged.additionalFields = mergedUnknownFields(
                prior: priorWorkout.additionalFields,
                current: workout.additionalFields
            )
            return merged
        }
        return result
    }
}
