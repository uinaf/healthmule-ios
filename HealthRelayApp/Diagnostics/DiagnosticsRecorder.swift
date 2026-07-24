import Foundation
import OSLog

struct DiagnosticEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let event: String
    let fields: [String: String]

    init(
        timestamp: Date = .now,
        category: String,
        event: String,
        fields: [String: String] = [:]
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.category = category
        self.event = event
        self.fields = fields
    }
}

struct DiagnosticsExport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let systemVersion: String
    let events: [DiagnosticEvent]
}

actor DiagnosticsRecorder {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.uinaf.healthrelay",
        category: "sync"
    )
    private var events: [DiagnosticEvent] = []
    private let maximumEventCount = 200

    func record(
        category: String,
        event: String,
        fields: [String: String] = [:]
    ) {
        let safeFields = fields.filter { key, _ in
            !Self.prohibitedFieldNames.contains(key.lowercased())
        }
        let diagnosticEvent = DiagnosticEvent(
            category: category,
            event: event,
            fields: safeFields
        )
        events.append(diagnosticEvent)
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }

        logger.info(
            "\(category, privacy: .public).\(event, privacy: .public) metadata=\(safeFields.description, privacy: .private(mask: .hash))"
        )
    }

    func export() throws -> URL {
        let export = DiagnosticsExport(
            schemaVersion: 1,
            generatedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? "unknown",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthRelayDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("health-relay-diagnostics.json")
        try encoder.encode(export).write(to: url, options: [.atomic])
        return url
    }

    private static let prohibitedFieldNames: Set<String> = [
        "access_token",
        "accesstoken",
        "authorization",
        "body",
        "contents",
        "healthvalue",
        "oauth",
        "record",
        "refreshtoken",
        "refresh_token",
        "token",
    ]
}
