import Foundation
import HealthRelayCore

enum BackfillDatePlanner {
    static func recentDates(
        through endDate: Date,
        count: Int,
        notBefore startDate: LocalDate,
        calendar: Calendar
    ) throws -> Set<LocalDate> {
        guard count > 0 else { return [] }
        let endDay = calendar.startOfDay(for: endDate)
        let dates = try (0..<count).map { offset in
            let date = calendar.date(
                byAdding: .day,
                value: -offset,
                to: endDay
            ) ?? endDay
            return try localDate(from: date, calendar: calendar)
        }
        return Set(dates.filter { $0 >= startDate })
    }

    static func missingDates(
        from startDate: LocalDate,
        through endDate: Date,
        excluding existingDates: Set<LocalDate>,
        calendar: Calendar
    ) throws -> Set<LocalDate> {
        let endComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: endDate
        )
        guard
            let endYear = endComponents.year,
            let endMonth = endComponents.month,
            let endDay = endComponents.day
        else {
            throw HealthKitClientError.queryFailed
        }
        let endLocalDate = try LocalDate(
            year: endYear,
            month: endMonth,
            day: endDay
        )

        guard startDate <= endLocalDate else {
            return []
        }

        var cursor = startDate
        var dates: Set<LocalDate> = []

        while cursor <= endLocalDate {
            if !existingDates.contains(cursor) {
                dates.insert(cursor)
            }
            cursor = try nextDate(after: cursor)
        }
        return dates
    }

    private static func nextDate(after date: LocalDate) throws -> LocalDate {
        let components = date.rawValue
            .split(separator: "-")
            .compactMap { Int($0) }
        guard components.count == 3 else {
            throw SchemaValidationError.invalidLocalDate(date.rawValue)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard
            let instant = calendar.date(
                from: DateComponents(
                    year: components[0],
                    month: components[1],
                    day: components[2]
                )
            ),
            let next = calendar.date(byAdding: .day, value: 1, to: instant)
        else {
            throw HealthKitClientError.queryFailed
        }
        let nextComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: next
        )
        guard
            let year = nextComponents.year,
            let month = nextComponents.month,
            let day = nextComponents.day
        else {
            throw HealthKitClientError.queryFailed
        }
        return try LocalDate(year: year, month: month, day: day)
    }

    private static func localDate(
        from date: Date,
        calendar: Calendar
    ) throws -> LocalDate {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            throw HealthKitClientError.queryFailed
        }
        return try LocalDate(year: year, month: month, day: day)
    }
}
