import Foundation
import HealthMuleCore

enum DayBoundaryStoreError: Error, Equatable {
    case unreadableState
    case invalidState
}

struct StoredDayBoundary: Codable, Equatable, Sendable {
    let date: LocalDate
    let timeZoneIdentifier: String
    let start: Date
    let end: Date
}

final class DayBoundaryStore {
    private let directory: URL
    private let fileURL: URL
    private var boundaries: [String: StoredDayBoundary]?

    init(directoryURL: URL? = nil) {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        directory = directoryURL ?? applicationSupport.appendingPathComponent(
            "HealthMule",
            isDirectory: true
        )
        fileURL = directory.appendingPathComponent("day-boundaries.json")
    }

    func boundary(
        for date: LocalDate,
        currentTimeZone: TimeZone
    ) throws -> StoredDayBoundary {
        let boundaries = try loadBoundaries()
        if let existing = boundaries[date.rawValue] {
            guard let storedTimeZone = TimeZone(
                identifier: existing.timeZoneIdentifier
            ) else {
                throw SchemaValidationError.invalidTimeZone(
                    existing.timeZoneIdentifier
                )
            }
            let normalized = try Self.normalizedBoundary(
                existing,
                timeZone: storedTimeZone
            )
            if normalized != existing {
                var nextBoundaries = boundaries
                nextBoundaries[date.rawValue] = normalized
                try persist(nextBoundaries)
                self.boundaries = nextBoundaries
            }
            return normalized
        }

        let boundary = try Self.makeBoundary(
            for: date,
            timeZone: currentTimeZone
        )
        var nextBoundaries = boundaries
        nextBoundaries[date.rawValue] = boundary
        try persist(nextBoundaries)
        self.boundaries = nextBoundaries
        return boundary
    }

    private static func normalizedBoundary(
        _ boundary: StoredDayBoundary,
        timeZone: TimeZone
    ) throws -> StoredDayBoundary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        guard let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: boundary.start
        ) else {
            throw SchemaValidationError.invalidLocalDate(
                boundary.date.rawValue
            )
        }
        return StoredDayBoundary(
            date: boundary.date,
            timeZoneIdentifier: boundary.timeZoneIdentifier,
            start: boundary.start,
            end: calendar.startOfDay(for: nextDay)
        )
    }

    func dateKeys(
        overlappingStart start: Date,
        end: Date,
        fallbackCalendar: Calendar
    ) throws -> Set<String> {
        let boundaries = try loadBoundaries()
        let endProbe = max(start, end.addingTimeInterval(-0.001))
        let storedMatches = boundaries.values.compactMap { boundary -> String? in
            guard start < boundary.end, endProbe >= boundary.start else {
                return nil
            }
            return boundary.date.rawValue
        }
        if !storedMatches.isEmpty {
            return Set(storedMatches)
        }

        let formatter = DateFormatter()
        formatter.calendar = fallbackCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = fallbackCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return [
            formatter.string(from: start),
            formatter.string(from: endProbe),
        ]
    }

    @discardableResult
    func inspectBoundaries() throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            boundaries = [:]
            return false
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            boundaries = nil
            throw DayBoundaryStoreError.unreadableState
        }
        do {
            let decoded = try JSONDecoder().decode(
                [String: StoredDayBoundary].self,
                from: data
            )
            boundaries = decoded
            return true
        } catch {
            boundaries = nil
            throw DayBoundaryStoreError.invalidState
        }
    }

    @discardableResult
    func rebuild(
        from records: [DailyHealthRecord]
    ) throws -> Int {
        var rebuilt: [String: StoredDayBoundary] = [:]
        for record in records {
            guard let timeZone = TimeZone(identifier: record.timeZone) else {
                throw SchemaValidationError.invalidTimeZone(
                    record.timeZone
                )
            }
            rebuilt[record.date.rawValue] = try Self.makeBoundary(
                for: record.date,
                timeZone: timeZone
            )
        }
        try persist(rebuilt)
        boundaries = rebuilt
        return rebuilt.count
    }

    private func persist(
        _ candidate: [String: StoredDayBoundary]
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(candidate)
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }

    private func loadBoundaries() throws -> [String: StoredDayBoundary] {
        if let boundaries {
            return boundaries
        }
        _ = try inspectBoundaries()
        return boundaries ?? [:]
    }

    private static func makeBoundary(
        for date: LocalDate,
        timeZone: TimeZone
    ) throws -> StoredDayBoundary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let components = date.rawValue.split(separator: "-").compactMap {
            Int($0)
        }
        guard
            components.count == 3,
            let start = calendar.date(
                from: DateComponents(
                    year: components[0],
                    month: components[1],
                    day: components[2]
                )
            ),
            let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: start
            )
        else {
            throw SchemaValidationError.invalidLocalDate(date.rawValue)
        }
        return StoredDayBoundary(
            date: date,
            timeZoneIdentifier: timeZone.identifier,
            start: start,
            end: calendar.startOfDay(for: nextDay)
        )
    }
}
