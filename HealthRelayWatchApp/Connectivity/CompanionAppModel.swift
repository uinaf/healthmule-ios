import Foundation
import HealthRelayCompanion
import Observation
@preconcurrency import WatchConnectivity

@MainActor
@Observable
final class CompanionAppModel: NSObject {
    enum DeliveryState: Equatable {
        case idle
        case sending
        case accepted
        case failed
    }

    private(set) var snapshot: CompanionSyncSnapshot?
    private(set) var deliveryState: DeliveryState = .idle
    private(set) var isReachable = false

    private let session: WCSession?
    private var outstandingRequestID: UUID?
    private var acceptedRequestID: UUID?
    private var requestBaselineSnapshot: CompanionSyncSnapshot?
    private var receivedPostRequestSnapshot = false
    private var isActivated = false

    init(
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) {
        self.session = session
        super.init()
        session?.delegate = self
    }

    var canRequestSync: Bool {
        snapshot?.canRequestSync == true
            && snapshot?.activity != .syncing
            && outstandingRequestID == nil
            && deliveryState != .accepted
            && isActivated
            && isReachable
    }

    func activate() {
        guard let session else {
            deliveryState = .failed
            return
        }
        receiveSnapshot(from: session.receivedApplicationContext)
        isActivated = session.activationState == .activated
        isReachable = session.isReachable
        session.activate()
    }

    func requestSync() {
        guard canRequestSync, let session else { return }
        let request = CompanionSyncRequest()
        guard
            let message = try? CompanionPayloadCodec.message(
                syncRequest: request
            )
        else {
            deliveryState = .failed
            return
        }

        outstandingRequestID = request.id
        acceptedRequestID = nil
        requestBaselineSnapshot = snapshot
        receivedPostRequestSnapshot = false
        deliveryState = .sending
        session.sendMessage(
            message,
            replyHandler: { [weak self] reply in
                let accepted = CompanionPayloadCodec.isAccepted(reply)
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        outstandingRequestID == request.id
                    else {
                        return
                    }
                    outstandingRequestID = nil
                    if accepted {
                        deliveryState = receivedPostRequestSnapshot
                            ? .idle
                            : .accepted
                        if deliveryState == .accepted {
                            acceptedRequestID = request.id
                            resetAcceptedStateIfNeeded(for: request.id)
                        }
                    } else {
                        deliveryState = .failed
                    }
                    if deliveryState != .accepted {
                        acceptedRequestID = nil
                        requestBaselineSnapshot = nil
                        receivedPostRequestSnapshot = false
                    }
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        outstandingRequestID == request.id
                    else {
                        return
                    }
                    outstandingRequestID = nil
                    acceptedRequestID = nil
                    deliveryState = .failed
                    requestBaselineSnapshot = nil
                    receivedPostRequestSnapshot = false
                }
            }
        )
    }

    private func resetAcceptedStateIfNeeded(for requestID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                acceptedRequestID == requestID,
                deliveryState == .accepted
            else {
                return
            }
            acceptedRequestID = nil
            deliveryState = .idle
            requestBaselineSnapshot = nil
            receivedPostRequestSnapshot = false
        }
    }

    private func receiveSnapshot(from message: [String: Any]) {
        guard
            let snapshot = try? CompanionPayloadCodec.snapshot(from: message)
        else {
            return
        }
        apply(snapshot)
    }

    private func apply(_ snapshot: CompanionSyncSnapshot) {
        let changed = snapshot != self.snapshot
        self.snapshot = snapshot
        if
            changed,
            requestBaselineSnapshot != nil,
            snapshot != requestBaselineSnapshot
        {
            receivedPostRequestSnapshot = true
            if deliveryState == .accepted {
                acceptedRequestID = nil
                deliveryState = .idle
                requestBaselineSnapshot = nil
                receivedPostRequestSnapshot = false
            }
        }
    }
}

extension CompanionAppModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let isActivated = activationState == .activated && error == nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActivated = isActivated
            isReachable = isActivated && self.session?.isReachable == true
            if isActivated, let context = self.session?.receivedApplicationContext {
                receiveSnapshot(from: context)
            } else if !isActivated {
                deliveryState = .failed
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard
            let snapshot = try? CompanionPayloadCodec.snapshot(
                from: applicationContext
            )
        else {
            return
        }
        Task { @MainActor [weak self] in
            self?.apply(snapshot)
        }
    }
}
