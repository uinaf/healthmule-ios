import Foundation
import HealthMuleCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum BenchmarkError: Error {
    case invalidSyntheticDate
    case missingStateSize
}

private struct TrialResult {
    let elapsedMilliseconds: Double
    let finalStateBytes: UInt64
    let cumulativeStateBytes: UInt64
}

@main
private struct SyncStoreBenchmark {
    private static let dayCounts = [30, 90, 365, 1_825]
    private static let repetitions = 3
    private static let stateFileName = "sync-state.json"

    static func main() async {
        do {
            let rows = try await benchmarkRows()
            print(rows.joined(separator: "\n"))
        } catch {
            FileHandle.standardError.write(
                Data("error: sync store benchmark failed.\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    private static func benchmarkRows() async throws -> [String] {
        let records = try syntheticRecords(count: dayCounts.max() ?? 0)
        var rows = [
            "days,median_elapsed_ms,final_state_bytes,cumulative_state_bytes"
        ]

        for dayCount in dayCounts {
            var trials: [TrialResult] = []
            for _ in 0..<repetitions {
                trials.append(
                    try await runTrial(records: records.prefix(dayCount))
                )
            }

            let elapsed = median(trials.map(\.elapsedMilliseconds))
            let finalBytes = median(trials.map(\.finalStateBytes))
            let cumulativeBytes = median(trials.map(\.cumulativeStateBytes))
            rows.append(
                "\(dayCount),"
                    + String(
                        format: "%.3f",
                        locale: Locale(identifier: "en_US_POSIX"),
                        elapsed
                    )
                    + ",\(finalBytes),\(cumulativeBytes)"
            )
        }
        return rows
    }

    private static func runTrial(
        records: ArraySlice<DailyHealthRecord>
    ) async throws -> TrialResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "healthmule-sync-benchmark-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = try FileSyncStore(rootDirectory: directory)
        let stateFile = directory.appendingPathComponent(stateFileName)
        let clock = ContinuousClock()
        let start = clock.now
        var cumulativeStateBytes: UInt64 = 0
        var finalStateBytes: UInt64 = 0

        for record in records {
            _ = try await store.stageDaily(record)
            finalStateBytes = try fileSize(at: stateFile)
            cumulativeStateBytes += finalStateBytes
        }

        return TrialResult(
            elapsedMilliseconds: milliseconds(
                from: start.duration(to: clock.now)
            ),
            finalStateBytes: finalStateBytes,
            cumulativeStateBytes: cumulativeStateBytes
        )
    }

    private static func syntheticRecords(
        count: Int
    ) throws -> [DailyHealthRecord] {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            throw BenchmarkError.invalidSyntheticDate
        }
        calendar.timeZone = utc
        guard
            let start = calendar.date(
                from: DateComponents(year: 2020, month: 1, day: 1)
            )
        else {
            throw BenchmarkError.invalidSyntheticDate
        }

        return try (0..<count).map { offset in
            guard
                let date = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: start
                )
            else {
                throw BenchmarkError.invalidSyntheticDate
            }
            let components = calendar.dateComponents(
                [.year, .month, .day],
                from: date
            )
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                throw BenchmarkError.invalidSyntheticDate
            }
            return DailyHealthRecord(
                date: try LocalDate(year: year, month: month, day: day),
                timeZone: "UTC",
                generatedAt: try ISO8601Timestamp(date: date, timeZone: utc),
                metrics: DailyHealthMetrics(),
                workouts: [],
                totals: WorkoutTotals(
                    workoutMinutes: 0,
                    workoutActiveEnergyKcal: 0
                ),
                sources: HealthRecordSources(
                    deviceNames: [],
                    sampleCount: 0
                )
            )
        }
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let size = attributes[.size] as? NSNumber else {
            throw BenchmarkError.missingStateSize
        }
        return size.uint64Value
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func median(_ values: [UInt64]) -> UInt64 {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
