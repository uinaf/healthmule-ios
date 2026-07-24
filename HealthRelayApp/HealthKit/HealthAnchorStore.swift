@preconcurrency import HealthKit
import Foundation

@MainActor
final class HealthAnchorStore {
    private struct SampleIndex: Codable {
        var datesByUUID: [String: [String]] = [:]
    }

    private let directory: URL
    private var index: SampleIndex

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        directory = directoryURL ?? applicationSupport
            .appendingPathComponent("HealthRelay", isDirectory: true)
            .appendingPathComponent("Anchors", isDirectory: true)

        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(resourceValues)

        let indexURL = directory.appendingPathComponent("sample-index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(SampleIndex.self, from: data)
        {
            index = decoded
        } else {
            index = SampleIndex()
        }
    }

    func anchor(for metric: HealthMetric) -> HKQueryAnchor? {
        let url = anchorURL(for: metric)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: data
        )
    }

    func queryStart(for metric: HealthMetric) -> Date? {
        let url = queryStartURL(for: metric)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    func dates(forDeletedUUID uuid: UUID) -> Set<String> {
        Set(index.datesByUUID[uuid.uuidString] ?? [])
    }

    func commit(
        metric: HealthMetric,
        anchor: HKQueryAnchor,
        queryStart: Date,
        sampleDates: [UUID: Set<String>],
        deletedUUIDs: Set<UUID>
    ) throws {
        var nextIndex = index
        for (uuid, dates) in sampleDates {
            nextIndex.datesByUUID[uuid.uuidString] = dates.sorted()
        }

        try persist(nextIndex)
        // Publish exactly what is now durable so a same-process retry can
        // resolve deletions even if writing the query boundary or anchor fails.
        index = nextIndex

        let queryStartData = try JSONEncoder().encode(queryStart)
        try protectedAtomicWrite(
            queryStartData,
            to: queryStartURL(for: metric)
        )

        let anchorData = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
        try protectedAtomicWrite(anchorData, to: anchorURL(for: metric))

        // Keep deletion mappings until the matching anchor is durable. A stale
        // mapping after cleanup failure is harmless; deleting it before the
        // anchor can permanently lose the affected day.
        guard !deletedUUIDs.isEmpty else {
            return
        }
        var cleanedIndex = nextIndex
        for uuid in deletedUUIDs {
            cleanedIndex.datesByUUID.removeValue(forKey: uuid.uuidString)
        }
        try persist(cleanedIndex)
        index = cleanedIndex
    }

    func reset() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        index = SampleIndex()
    }

    func reset(metric: HealthMetric) throws {
        let fileManager = FileManager.default
        for url in [anchorURL(for: metric), queryStartURL(for: metric)]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func anchorURL(for metric: HealthMetric) -> URL {
        directory.appendingPathComponent("\(metric.rawValue).anchor")
    }

    private func queryStartURL(for metric: HealthMetric) -> URL {
        directory.appendingPathComponent("\(metric.rawValue).query-start")
    }

    private func protectedAtomicWrite(_ data: Data, to url: URL) throws {
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    private func persist(_ candidate: SampleIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(candidate)
        try protectedAtomicWrite(
            data,
            to: directory.appendingPathComponent("sample-index.json")
        )
    }
}
