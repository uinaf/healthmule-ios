import Foundation
import XCTest
@testable import HealthRelayCompanion

final class CompanionSyncContractTests: XCTestCase {
    func testSnapshotRoundTripsThroughPropertyListSafeMessage() throws {
        let lastSync = Date(timeIntervalSince1970: 1_753_300_000)
        let snapshot = CompanionSyncSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_753_300_100),
            readiness: .ready,
            activity: .synced,
            canRequestSync: true,
            lastSuccessfulSyncAt: lastSync,
            pendingUploadCount: 2,
            retryableUploadCount: 1,
            permanentFailureCount: 1
        )

        let message = try CompanionPayloadCodec.message(snapshot: snapshot)

        XCTAssertEqual(Set(message.keys), [CompanionPayloadCodec.snapshotKey])
        XCTAssertTrue(
            PropertyListSerialization.propertyList(
                message,
                isValidFor: .binary
            )
        )
        XCTAssertEqual(
            try CompanionPayloadCodec.snapshot(from: message),
            snapshot
        )
    }

    func testSyncRequestRoundTripsAndAcknowledgementIsExplicit() throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "47E21773-0499-412D-8D30-4E62A767C552")
        )
        let request = CompanionSyncRequest(
            id: id,
            requestedAt: Date(timeIntervalSince1970: 1_753_300_200)
        )

        let message = try CompanionPayloadCodec.message(syncRequest: request)

        XCTAssertEqual(
            try CompanionPayloadCodec.syncRequest(from: message),
            request
        )
        XCTAssertTrue(
            CompanionPayloadCodec.isAccepted(
                CompanionPayloadCodec.acknowledgement(accepted: true)
            )
        )
        XCTAssertFalse(
            CompanionPayloadCodec.isAccepted(
                CompanionPayloadCodec.acknowledgement(accepted: false)
            )
        )

    }

    func testSnapshotDecoderRejectsFutureSchemaAndInvalidCounts() throws {
        let futureSnapshot = CompanionSyncSnapshot(
            schemaVersion: 2,
            generatedAt: .now,
            readiness: .ready,
            activity: .idle,
            canRequestSync: true,
            lastSuccessfulSyncAt: nil,
            pendingUploadCount: 0,
            retryableUploadCount: 0,
            permanentFailureCount: 0
        )
        XCTAssertThrowsError(
            try CompanionPayloadCodec.snapshot(
                from: CompanionPayloadCodec.message(snapshot: futureSnapshot)
            )
        ) { error in
            XCTAssertEqual(
                error as? CompanionPayloadError,
                .unsupportedSchema
            )
        }

        let invalidSnapshot = CompanionSyncSnapshot(
            generatedAt: .now,
            readiness: .ready,
            activity: .idle,
            canRequestSync: true,
            lastSuccessfulSyncAt: nil,
            pendingUploadCount: -1,
            retryableUploadCount: 0,
            permanentFailureCount: 0
        )
        XCTAssertThrowsError(
            try CompanionPayloadCodec.snapshot(
                from: CompanionPayloadCodec.message(snapshot: invalidSnapshot)
            )
        ) { error in
            XCTAssertEqual(error as? CompanionPayloadError, .invalidCounts)
        }
    }
}
