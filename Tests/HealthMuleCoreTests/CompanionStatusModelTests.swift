import Foundation
import XCTest
@testable import HealthMuleCompanion

final class CompanionStatusModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshnessThresholdFutureAndMissingSnapshot() {
        XCTAssertEqual(
            CompanionStatusModel.freshness(
                of: snapshot(age: CompanionStatusModel.currentSnapshotInterval),
                now: now
            ),
            .current
        )
        XCTAssertEqual(
            CompanionStatusModel.freshness(
                of: snapshot(
                    age: CompanionStatusModel.currentSnapshotInterval + 1
                ),
                now: now
            ),
            .stale
        )
        XCTAssertEqual(
            CompanionStatusModel.freshness(
                of: snapshot(age: -1),
                now: now
            ),
            .unknown
        )
        XCTAssertEqual(
            CompanionStatusModel.freshness(of: nil, now: now),
            .unknown
        )
    }

    func testStaleAndUnreachableSnapshotsNeverClaimUpToDate() {
        let stale = status(
            snapshot: snapshot(
                age: CompanionStatusModel.currentSnapshotInterval + 1
            )
        )
        let unreachable = status(isReachable: false)
        let activating = status(
            activation: .inactive,
            isReachable: false
        )

        XCTAssertEqual(stale.freshness, .stale)
        XCTAssertEqual(stale.connection, .stale)
        XCTAssertEqual(stale.headline, .ready)
        XCTAssertEqual(unreachable.connection, .unreachable)
        XCTAssertEqual(unreachable.headline, .phoneUnavailable)
        XCTAssertEqual(activating.connection, .connecting)
        XCTAssertEqual(activating.headline, .waitingForPhone)
    }

    func testEveryActivityProducesTruthfulHeadline() {
        let cases: [
            (CompanionSyncSnapshot.Activity, CompanionStatusHeadline)
        ] = [
            (.idle, .ready),
            (.syncing, .syncing),
            (.synced, .upToDate),
            (.attention, .needsAttention),
        ]

        for (activity, expected) in cases {
            XCTAssertEqual(
                status(snapshot: snapshot(activity: activity)).headline,
                expected
            )
        }
    }

    func testEveryReadinessProducesTruthfulHeadline() {
        let cases: [
            (CompanionSyncSnapshot.Readiness, CompanionStatusHeadline)
        ] = [
            (.checking, .ready),
            (.ready, .upToDate),
            (.setupRequired, .finishSetup),
            (.unavailable, .needsAttention),
            (.attention, .needsAttention),
        ]

        for (readiness, expected) in cases {
            XCTAssertEqual(
                status(snapshot: snapshot(readiness: readiness)).headline,
                expected
            )
        }
    }

    func testLastSuccessAndQueueFactsRemainIndependent() {
        let lastSuccess = now.addingTimeInterval(-600)
        let model = status(
            snapshot: snapshot(
                lastSuccessfulSyncAt: lastSuccess,
                pending: 5,
                retryable: 3,
                blocked: 2
            )
        )

        XCTAssertEqual(model.lastSuccessfulSyncAt, lastSuccess)
        XCTAssertEqual(model.pendingUploadCount, 5)
        XCTAssertEqual(model.retryableUploadCount, 3)
        XCTAssertEqual(model.permanentFailureCount, 2)
        XCTAssertEqual(model.headline, .needsAttention)
    }

    func testMissingSnapshotAndActivationFailureOfferRetry() {
        let waiting = CompanionStatusModel(
            snapshot: nil,
            activation: .activated,
            isReachable: true,
            requestState: .idle,
            now: now
        )
        let failed = CompanionStatusModel(
            snapshot: nil,
            activation: .failed,
            isReachable: false,
            requestState: .idle,
            now: now
        )

        XCTAssertEqual(waiting.connection, .waitingForSnapshot)
        XCTAssertEqual(waiting.freshness, .unknown)
        XCTAssertEqual(waiting.headline, .waitingForPhone)
        XCTAssertTrue(waiting.canRetryConnection)
        XCTAssertEqual(failed.connection, .activationFailed)
        XCTAssertEqual(failed.headline, .phoneUnavailable)
        XCTAssertTrue(failed.canRetryConnection)
    }

    func testSyncActionExplainsEveryBlockedState() {
        XCTAssertEqual(
            status(activation: .inactive).syncActionBlock,
            .activationIncomplete
        )
        XCTAssertEqual(
            status(isReachable: false).syncActionBlock,
            .phoneUnreachable
        )
        XCTAssertEqual(
            status(
                snapshot: snapshot(canRequestSync: false)
            ).syncActionBlock,
            .snapshotDisallows
        )
        XCTAssertEqual(
            status(
                snapshot: snapshot(activity: .syncing)
            ).syncActionBlock,
            .syncInProgress
        )
        XCTAssertEqual(
            status(requestState: .sending).syncActionBlock,
            .requestInProgress
        )
        XCTAssertEqual(
            status(requestState: .accepted).syncActionBlock,
            .requestInProgress
        )
        XCTAssertNil(status(requestState: .failed).syncActionBlock)
        XCTAssertTrue(status().canRequestSync)
    }

    func testDeliveryNoteMapsEveryRequestState() {
        let cases: [
            (CompanionRequestDeliveryState, CompanionDeliveryNote)
        ] = [
            (.idle, .none),
            (.sending, .sending),
            (.accepted, .accepted),
            (.failed, .failed),
        ]
        for (state, expected) in cases {
            XCTAssertEqual(status(requestState: state).deliveryNote, expected)
        }
    }

    func testReplyBeforeSemanticSnapshotCompletesAfterSnapshot() {
        let requestID = UUID()
        let baseline = snapshot()
        var lifecycle = CompanionRequestLifecycle()

        lifecycle.start(requestID: requestID, baseline: baseline)
        lifecycle.receiveReply(requestID: requestID, accepted: true)
        XCTAssertEqual(lifecycle.state, .accepted)

        lifecycle.receive(snapshot: snapshot(pending: 1))
        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.requestID)
    }

    func testSnapshotBeforeReplyCompletesWhenReplyArrives() {
        let requestID = UUID()
        var lifecycle = CompanionRequestLifecycle()

        lifecycle.start(requestID: requestID, baseline: snapshot())
        lifecycle.receive(snapshot: snapshot(activity: .syncing))
        XCTAssertEqual(lifecycle.state, .sending)

        lifecycle.receiveReply(requestID: requestID, accepted: true)
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testGeneratedAtOnlySnapshotDoesNotCompleteAcknowledgement() {
        let requestID = UUID()
        let baseline = snapshot(age: 20)
        var lifecycle = CompanionRequestLifecycle()

        lifecycle.start(requestID: requestID, baseline: baseline)
        lifecycle.receiveReply(requestID: requestID, accepted: true)
        lifecycle.receive(snapshot: snapshot(age: 10))

        XCTAssertEqual(lifecycle.state, .accepted)
        XCTAssertEqual(lifecycle.requestID, requestID)
    }

    func testSendFailureAndStaleRequestIDAreDeterministic() {
        let requestID = UUID()
        var lifecycle = CompanionRequestLifecycle()
        lifecycle.start(requestID: requestID, baseline: snapshot())

        lifecycle.receiveReply(requestID: UUID(), accepted: true)
        XCTAssertEqual(lifecycle.state, .sending)

        lifecycle.receiveReply(requestID: requestID, accepted: false)
        XCTAssertEqual(lifecycle.state, .failed)
        XCTAssertNil(lifecycle.requestID)

        lifecycle.receive(snapshot: snapshot(pending: 1))
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testAcceptedFallbackExpiresOnlyMatchingRequest() {
        let requestID = UUID()
        var lifecycle = CompanionRequestLifecycle()
        lifecycle.start(requestID: requestID, baseline: snapshot())
        lifecycle.receiveReply(requestID: requestID, accepted: true)

        lifecycle.acceptedStateExpired(requestID: UUID())
        XCTAssertEqual(lifecycle.state, .accepted)

        lifecycle.acceptedStateExpired(requestID: requestID)
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testPublicationStateDeduplicatesSemanticsAndCanBeInvalidated() {
        let first = snapshot(age: 20)
        let timestampOnlyUpdate = snapshot(age: 10)
        var state = CompanionSnapshotPublicationState()

        XCTAssertTrue(state.needsPublication(of: first))
        state.didPublish(first)
        XCTAssertFalse(state.needsPublication(of: timestampOnlyUpdate))

        state.invalidate()
        XCTAssertTrue(state.needsPublication(of: timestampOnlyUpdate))
    }

    private func status(
        snapshot: CompanionSyncSnapshot? = nil,
        activation: CompanionActivationState = .activated,
        isReachable: Bool = true,
        requestState: CompanionRequestDeliveryState = .idle
    ) -> CompanionStatusModel {
        CompanionStatusModel(
            snapshot: snapshot ?? self.snapshot(),
            activation: activation,
            isReachable: isReachable,
            requestState: requestState,
            now: now
        )
    }

    private func snapshot(
        age: TimeInterval = 10,
        readiness: CompanionSyncSnapshot.Readiness = .ready,
        activity: CompanionSyncSnapshot.Activity = .synced,
        canRequestSync: Bool = true,
        lastSuccessfulSyncAt: Date? = nil,
        pending: Int = 0,
        retryable: Int = 0,
        blocked: Int = 0
    ) -> CompanionSyncSnapshot {
        CompanionSyncSnapshot(
            generatedAt: now.addingTimeInterval(-age),
            readiness: readiness,
            activity: activity,
            canRequestSync: canRequestSync,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            pendingUploadCount: pending,
            retryableUploadCount: retryable,
            permanentFailureCount: blocked
        )
    }
}
