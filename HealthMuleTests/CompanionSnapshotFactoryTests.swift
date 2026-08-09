import Foundation
import HealthMuleCompanion
import XCTest
@testable import HealthMule

final class CompanionSnapshotFactoryTests: XCTestCase {
    func testFactorySemanticsIgnoreGenerationTime() {
        let first = CompanionSnapshotFactory.make(
            readiness: .ready,
            operationState: .idle,
            summary: .empty,
            now: Date(timeIntervalSince1970: 1_753_300_400)
        )
        let second = CompanionSnapshotFactory.make(
            readiness: .ready,
            operationState: .idle,
            summary: .empty,
            now: Date(timeIntervalSince1970: 1_753_300_500)
        )

        XCTAssertNotEqual(first.generatedAt, second.generatedAt)
        XCTAssertEqual(first.semantics, second.semantics)
    }

    func testFactoryPublishesOnlySanitizedSyncStatus() throws {
        let lastSync = Date(timeIntervalSince1970: 1_753_300_300)
        let summary = SyncSummary(
            lastSuccessfulSyncAt: lastSync,
            latestExportedDate: "2026-07-25",
            pendingUploadCount: 3,
            retryableUploadCount: 2,
            permanentFailureCount: 1
        )

        let snapshot = CompanionSnapshotFactory.make(
            readiness: .ready,
            operationState: .working(.sync, "Uploading private record body"),
            summary: summary,
            now: Date(timeIntervalSince1970: 1_753_300_400)
        )

        XCTAssertEqual(snapshot.readiness, .ready)
        XCTAssertEqual(snapshot.activity, .syncing)
        XCTAssertFalse(snapshot.canRequestSync)
        XCTAssertEqual(snapshot.lastSuccessfulSyncAt, lastSync)
        XCTAssertEqual(snapshot.pendingUploadCount, 3)
        XCTAssertEqual(snapshot.retryableUploadCount, 2)
        XCTAssertEqual(snapshot.permanentFailureCount, 1)

        let message = try CompanionPayloadCodec.message(snapshot: snapshot)
        let data = try XCTUnwrap(
            message[CompanionPayloadCodec.snapshotKey] as? Data
        )
        let payload = try XCTUnwrap(
            String(data: data, encoding: .utf8)
        )
        XCTAssertFalse(payload.contains("Uploading private record body"))
        XCTAssertFalse(payload.contains("2026-07-25"))
    }

    func testFactoryKeepsRecoverableAdvisorySyncable() {
        let snapshot = CompanionSnapshotFactory.make(
            readiness: .healthReviewRecommended,
            operationState: .idle,
            summary: .empty
        )

        XCTAssertEqual(snapshot.readiness, .attention)
        XCTAssertTrue(snapshot.canRequestSync)
    }
}
