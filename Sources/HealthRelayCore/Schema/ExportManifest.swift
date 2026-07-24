import Foundation

public struct ExportManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exporterVersion: String
    public var timeZone: String
    public var lastSuccessfulSyncAt: ISO8601Timestamp
    public var earliestDate: LocalDate
    public var latestDate: LocalDate
    public var recordCount: Int
    public var additionalFields: [String: JSONValue]

    public init(
        schemaVersion: Int = 1,
        exporterVersion: String,
        timeZone: String,
        lastSuccessfulSyncAt: ISO8601Timestamp,
        earliestDate: LocalDate,
        latestDate: LocalDate,
        recordCount: Int,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.exporterVersion = exporterVersion
        self.timeZone = timeZone
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.earliestDate = earliestDate
        self.latestDate = latestDate
        self.recordCount = recordCount
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case exporterVersion
        case timeZone
        case lastSuccessfulSyncAt
        case earliestDate
        case latestDate
        case recordCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exporterVersion = try container.decode(String.self, forKey: .exporterVersion)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        lastSuccessfulSyncAt = try container.decode(
            ISO8601Timestamp.self,
            forKey: .lastSuccessfulSyncAt
        )
        earliestDate = try container.decode(LocalDate.self, forKey: .earliestDate)
        latestDate = try container.decode(LocalDate.self, forKey: .latestDate)
        recordCount = try container.decode(Int.self, forKey: .recordCount)
        additionalFields = try decodeUnknownFields(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exporterVersion, forKey: .exporterVersion)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(lastSuccessfulSyncAt, forKey: .lastSuccessfulSyncAt)
        try container.encode(earliestDate, forKey: .earliestDate)
        try container.encode(latestDate, forKey: .latestDate)
        try container.encode(recordCount, forKey: .recordCount)
        try encodeUnknownFields(
            additionalFields,
            to: encoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }

    public func preservingUnknownFields(from prior: ExportManifest) -> ExportManifest {
        var result = self
        result.additionalFields = mergedUnknownFields(
            prior: prior.additionalFields,
            current: additionalFields
        )
        return result
    }
}
