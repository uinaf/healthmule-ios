import Foundation

public enum SchemaValidationError: Error, Equatable, Sendable {
    case invalidLocalDate(String)
    case invalidTimestamp(String)
    case invalidTimeZone(String)
    case conflictingWorkoutID(String)
    case unsupportedJSONNumberPrecision
    case unsupportedSchemaVersion(Int)
}

public struct LocalDate: Codable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw SchemaValidationError.invalidLocalDate(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(year: Int, month: Int, day: Int) throws {
        try self.init(rawValue: String(format: "%04d-%02d-%02d", year, month, day))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(rawValue: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a Gregorian date formatted as YYYY-MM-DD."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10 else { return false }
        guard bytes.enumerated().allSatisfy({ index, byte in
            if index == 4 || index == 7 {
                return byte == 0x2D
            }
            return byte >= 0x30 && byte <= 0x39
        }) else {
            return false
        }

        let yearText = String(decoding: bytes[0...3], as: UTF8.self)
        let monthText = String(decoding: bytes[5...6], as: UTF8.self)
        let dayText = String(decoding: bytes[8...9], as: UTF8.self)
        guard
            let year = Int(yearText),
            let month = Int(monthText),
            let day = Int(dayText)
        else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }
}

public struct ISO8601Timestamp: Codable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard
            Self.hasFourDigitYear(rawValue),
            Self.parse(rawValue) != nil,
            Self.hasExplicitOffset(rawValue)
        else {
            throw SchemaValidationError.invalidTimestamp(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(date: Date, timeZone: TimeZone) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw SchemaValidationError.invalidTimestamp("Date must be finite.")
        }
        var wholeSeconds = date.timeIntervalSince1970.rounded(.down)
        let fractionalSeconds = date.timeIntervalSince1970 - wholeSeconds
        var nanoseconds = Int(
            (fractionalSeconds * 1_000_000_000).rounded()
        )
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withColonSeparatorInTimeZone,
        ]
        formatter.timeZone = timeZone
        let base = formatter.string(
            from: Date(timeIntervalSince1970: wholeSeconds)
        )
        guard nanoseconds > 0 else {
            try self.init(rawValue: base)
            return
        }
        let fraction = String(
            String(format: "%09d", nanoseconds)
                .reversed()
                .drop(while: { $0 == "0" })
                .reversed()
        )
        guard
            let timeStart = base.firstIndex(of: "T"),
            let suffixStart = base[timeStart...].firstIndex(where: {
                $0 == "+" || $0 == "-" || $0 == "Z"
            })
        else {
            throw SchemaValidationError.invalidTimestamp(base)
        }
        try self.init(
            rawValue: base[..<suffixStart]
                + ".\(fraction)"
                + base[suffixStart...]
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(rawValue: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp with an explicit UTC offset."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func date() throws -> Date {
        guard let date = Self.parse(rawValue) else {
            throw SchemaValidationError.invalidTimestamp(rawValue)
        }
        return date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard let lhsDate = Self.parse(lhs.rawValue), let rhsDate = Self.parse(rhs.rawValue) else {
            return lhs.rawValue < rhs.rawValue
        }
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.rawValue < rhs.rawValue
    }

    static let semanticSentinel = try! ISO8601Timestamp(rawValue: "1970-01-01T00:00:00Z")

    private static func parse(_ value: String) -> Date? {
        var format = Date.ISO8601FormatStyle()
        format = format
            .year()
            .month()
            .day()
            .dateSeparator(.dash)
            .time(includingFractionalSeconds: true)
            .timeSeparator(.colon)
            .timeZone(separator: .colon)
        return try? format.parse(value)
    }

    private static func hasFourDigitYear(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= 5, bytes[4] == 0x2D else { return false }
        return bytes[0...3].allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    private static func hasExplicitOffset(_ value: String) -> Bool {
        if value.hasSuffix("Z") {
            return true
        }
        guard value.count >= 6 else { return false }
        let suffix = value.suffix(6)
        let parts = Array(suffix)
        guard
            (parts[0] == "+" || parts[0] == "-"),
            parts[3] == ":"
        else {
            return false
        }
        return parts[1].isNumber
            && parts[2].isNumber
            && parts[4].isNumber
            && parts[5].isNumber
    }
}
