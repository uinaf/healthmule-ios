import Foundation

public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder().encode(value)
        try validateNumericPrecision(in: data)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try validateNumericPrecision(in: data)
        return try decoder().decode(type, from: data)
    }

    static func encodeWithoutTrailingNewline<T: Encodable>(_ value: T) throws -> Data {
        let data = try encoder().encode(value)
        try validateNumericPrecision(in: data)
        return data
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    private static func validateNumericPrecision(in data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Canonical JSON must use UTF-8 encoding."
                )
            )
        }

        let bytes = Array(data)
        var index = 0
        var isInsideString = false
        var isEscaped = false

        while index < bytes.count {
            let byte = bytes[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    isInsideString = false
                }
                index += 1
                continue
            }
            if byte == 0x22 {
                isInsideString = true
                index += 1
                continue
            }
            guard byte == 0x2D || isASCIIDigit(byte) else {
                index += 1
                continue
            }

            var cursor = index
            if bytes[cursor] == 0x2D {
                cursor += 1
            }
            var coefficientDigits: [UInt8] = []
            while cursor < bytes.count, isASCIIDigit(bytes[cursor]) {
                coefficientDigits.append(bytes[cursor])
                cursor += 1
            }
            if cursor < bytes.count, bytes[cursor] == 0x2E {
                cursor += 1
                while cursor < bytes.count, isASCIIDigit(bytes[cursor]) {
                    coefficientDigits.append(bytes[cursor])
                    cursor += 1
                }
            }
            guard !coefficientDigits.isEmpty else {
                index += 1
                continue
            }
            if
                cursor < bytes.count,
                bytes[cursor] == 0x45 || bytes[cursor] == 0x65
            {
                cursor += 1
                if
                    cursor < bytes.count,
                    bytes[cursor] == 0x2B || bytes[cursor] == 0x2D
                {
                    cursor += 1
                }
                while cursor < bytes.count, isASCIIDigit(bytes[cursor]) {
                    cursor += 1
                }
            }

            let firstSignificant = coefficientDigits.firstIndex { $0 != 0x30 }
            let lastSignificant = coefficientDigits.lastIndex { $0 != 0x30 }
            let significantDigitCount: Int
            if let firstSignificant, let lastSignificant {
                significantDigitCount = coefficientDigits.distance(
                    from: firstSignificant,
                    to: lastSignificant
                ) + 1
            } else {
                significantDigitCount = 1
            }
            guard significantDigitCount <= 38 else {
                throw SchemaValidationError.unsupportedJSONNumberPrecision
            }
            index = cursor
        }
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }
}

public enum DailyHealthRecordCodec {
    public static func encode(_ record: DailyHealthRecord) throws -> Data {
        guard record.schemaVersion == 1 else {
            throw SchemaValidationError.unsupportedSchemaVersion(record.schemaVersion)
        }
        return try CanonicalJSON.encode(normalized(record))
    }

    public static func decode(_ data: Data) throws -> DailyHealthRecord {
        let record = try CanonicalJSON.decode(DailyHealthRecord.self, from: data)
        guard record.schemaVersion == 1 else {
            throw SchemaValidationError.unsupportedSchemaVersion(record.schemaVersion)
        }
        return try normalized(record)
    }

    public static func semanticData(for record: DailyHealthRecord) throws -> Data {
        var semanticRecord = try normalized(record)
        semanticRecord.generatedAt = .semanticSentinel
        return try CanonicalJSON.encodeWithoutTrailingNewline(semanticRecord)
    }

    public static func semanticallyEqual(
        _ lhs: DailyHealthRecord,
        _ rhs: DailyHealthRecord
    ) throws -> Bool {
        try semanticData(for: lhs) == semanticData(for: rhs)
    }

    private static func normalized(
        _ record: DailyHealthRecord
    ) throws -> DailyHealthRecord {
        try validateTimeZoneIdentifier(record.timeZone)
        var result = record
        result.metrics.weightKg = ExportDecimal.quantized(
            result.metrics.weightKg
        )
        result.metrics.activeEnergyKcal = ExportDecimal.quantized(
            result.metrics.activeEnergyKcal
        )
        result.metrics.restingEnergyKcal = ExportDecimal.quantized(
            result.metrics.restingEnergyKcal
        )
        result.metrics.restingHeartRateBpm = ExportDecimal.quantized(
            result.metrics.restingHeartRateBpm
        )
        result.metrics.hrvSdnnMs = ExportDecimal.quantized(
            result.metrics.hrvSdnnMs
        )
        result.metrics.vo2MaxMlKgMin = ExportDecimal.quantized(
            result.metrics.vo2MaxMlKgMin
        )
        result.metrics.sleepMinutes = ExportDecimal.quantized(
            result.metrics.sleepMinutes
        )
        result.workouts = try deduplicatedWorkouts(result.workouts).map { workout in
            var normalizedWorkout = workout
            normalizedWorkout.durationMinutes = ExportDecimal.quantized(
                workout.durationMinutes
            )
            normalizedWorkout.activeEnergyKcal = ExportDecimal.quantized(
                workout.activeEnergyKcal
            )
            normalizedWorkout.distanceMeters = ExportDecimal.quantized(
                workout.distanceMeters
            )
            return normalizedWorkout
        }
        result.workouts.sort {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.endedAt != $1.endedAt { return $0.endedAt < $1.endedAt }
            return $0.type < $1.type
        }
        result.totals.workoutMinutes = try ExportDecimal.quantizedSum(
            result.workouts.map(\.durationMinutes)
        )
        result.totals.workoutActiveEnergyKcal = try ExportDecimal.quantizedSum(
            result.workouts.compactMap(\.activeEnergyKcal)
        )
        result.sources.deviceNames = Array(Set(result.sources.deviceNames)).sorted()
        return result
    }

    private static func deduplicatedWorkouts(
        _ workouts: [WorkoutRecord]
    ) throws -> [WorkoutRecord] {
        var uniqueByID: [String: WorkoutRecord] = [:]
        var result: [WorkoutRecord] = []
        for workout in workouts {
            if let existing = uniqueByID[workout.id] {
                guard existing == workout else {
                    throw SchemaValidationError.conflictingWorkoutID(
                        workout.id
                    )
                }
                continue
            }
            uniqueByID[workout.id] = workout
            result.append(workout)
        }
        return result
    }
}

public enum ExportManifestCodec {
    public static func encode(_ manifest: ExportManifest) throws -> Data {
        guard manifest.schemaVersion == 1 else {
            throw SchemaValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        try validateTimeZoneIdentifier(manifest.timeZone)
        return try CanonicalJSON.encode(manifest)
    }

    public static func decode(_ data: Data) throws -> ExportManifest {
        let manifest = try CanonicalJSON.decode(ExportManifest.self, from: data)
        guard manifest.schemaVersion == 1 else {
            throw SchemaValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        try validateTimeZoneIdentifier(manifest.timeZone)
        return manifest
    }
}

private func validateTimeZoneIdentifier(_ identifier: String) throws {
    guard TimeZone(identifier: identifier) != nil else {
        throw SchemaValidationError.invalidTimeZone(identifier)
    }
}
