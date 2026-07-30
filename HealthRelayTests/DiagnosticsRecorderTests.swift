import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

final class DiagnosticsRecorderTests: XCTestCase {
    func testExportContainsOnlyTypedAllowlistedPayloads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(
                from: "2026-07-30T00:00:00Z"
            )
        )
        let recorder = DiagnosticsRecorder(
            now: { fixedDate },
            appVersion: "test-app",
            systemVersion: "test-system",
            exportDirectory: directory
        )
        var report = SyncReport()
        report.stagedDailyCount = 2
        report.unchangedDailyCount = 3
        report.uploadedDailyCount = 1
        report.pendingUploadCount = 4
        report.failures = [
            SyncFailureSummary(
                artifactID: .manifest,
                code: "drive_503_private-server-reason",
                blocked: false
            )
        ]
        let secretDescription =
            "sentinel-token-account-file-folder-path-record-health-body"

        await recorder.record(.bootstrapStarted)
        await recorder.record(.syncCoreReport(DiagnosticCoreReport(report)))
        await recorder.record(
            .syncFailed(
                DiagnosticErrorCode(
                    capturing: LeakyTestError(
                        description: secretDescription
                    )
                )
            )
        )

        let url = try await recorder.export()
        let data = try Data(contentsOf: url)
        let export = try decodeExport(data)

        XCTAssertEqual(export.schemaVersion, 1)
        XCTAssertEqual(export.generatedAt, fixedDate)
        XCTAssertEqual(export.appVersion, "test-app")
        XCTAssertEqual(export.systemVersion, "test-system")
        XCTAssertEqual(export.events.count, 3)
        XCTAssertEqual(export.events[0].category, "lifecycle")
        XCTAssertEqual(export.events[0].event, "bootstrap-started")
        XCTAssertTrue(export.events[0].fields.isEmpty)
        XCTAssertEqual(
            export.events[1].fields,
            [
                "failedCount": "1",
                "failureCodes": "drive_remote",
                "pendingCount": "4",
                "stagedCount": "2",
                "unchangedCount": "3",
                "uploadedCount": "1",
            ]
        )
        XCTAssertEqual(
            export.events[2].fields.keys.sorted(),
            ["errorCode"]
        )
        XCTAssertTrue(
            export.events[2].fields["errorCode"]?
                .contains("LeakyTestError") == true
        )

        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains(secretDescription))
        XCTAssertFalse(json.contains("private-server-reason"))

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        var keys: Set<String> = []
        collectKeys(from: jsonObject, into: &keys)
        let forbiddenKeys: Set<String> = [
            "token",
            "accountid",
            "fileid",
            "folderid",
            "path",
            "record",
            "healthvalue",
            "metadata",
            "body",
        ]
        XCTAssertTrue(
            forbiddenKeys.isDisjoint(
                with: Set(keys.map { $0.lowercased() })
            )
        )
    }

    func testExportEvictsOldestEventAtTwoHundred() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = DiagnosticsRecorder(
            appVersion: "test-app",
            systemVersion: "test-system",
            exportDirectory: directory
        )

        await recorder.record(.healthRequestCompleted)
        for _ in 0..<200 {
            await recorder.record(.bootstrapStarted)
        }

        let export = try decodeExport(
            Data(contentsOf: try await recorder.export())
        )

        XCTAssertEqual(export.events.count, 200)
        XCTAssertTrue(
            export.events.allSatisfy {
                $0.event == "bootstrap-started"
            }
        )
    }

    private func decodeExport(_ data: Data) throws -> DiagnosticsExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DiagnosticsExport.self, from: data)
    }

    private func collectKeys(
        from value: Any,
        into keys: inout Set<String>
    ) {
        if let dictionary = value as? [String: Any] {
            keys.formUnion(dictionary.keys)
            for nestedValue in dictionary.values {
                collectKeys(from: nestedValue, into: &keys)
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                collectKeys(from: nestedValue, into: &keys)
            }
        }
    }
}

private struct LeakyTestError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}
