import Foundation

public enum CompanionActivationState: Equatable, Sendable {
    case inactive
    case activated
    case failed
}

public enum CompanionSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
    case unknown
}

public enum CompanionStatusHeadline: Equatable, Sendable {
    case waitingForPhone
    case syncing
    case needsAttention
    case finishSetup
    case phoneUnavailable
    case ready
    case statusOutOfDate
    case statusTimeUnavailable
    case upToDate
}

public enum CompanionConnectionStatus: Equatable, Sendable {
    case connecting
    case reachable
    case unreachable
    case waitingForSnapshot
    case stale
    case activationFailed
}

public enum CompanionSyncActionBlock: Equatable, Sendable {
    case activationIncomplete
    case phoneUnreachable
    case snapshotDisallows
    case syncInProgress
    case requestInProgress
}

public enum CompanionDeliveryNote: Equatable, Sendable {
    case none
    case sending
    case accepted
    case failed
}

public struct CompanionStatusModel: Equatable, Sendable {
    // Application context is eventual. Thirty minutes avoids claiming that an
    // old phone state is current while allowing normal background delivery lag.
    public static let currentSnapshotInterval: TimeInterval = 30 * 60

    public let headline: CompanionStatusHeadline
    public let connection: CompanionConnectionStatus
    public let freshness: CompanionSnapshotFreshness
    public let lastSuccessfulSyncAt: Date?
    public let pendingUploadCount: Int
    public let retryableUploadCount: Int
    public let permanentFailureCount: Int
    public let updatedAt: Date?
    public let showsSyncAction: Bool
    public let canRequestSync: Bool
    public let syncActionBlock: CompanionSyncActionBlock?
    public let canRetryConnection: Bool
    public let deliveryNote: CompanionDeliveryNote

    public init(
        snapshot: CompanionSyncSnapshot?,
        activation: CompanionActivationState,
        isReachable: Bool,
        requestState: CompanionRequestDeliveryState,
        now: Date
    ) {
        let freshness = Self.freshness(of: snapshot, now: now)
        self.freshness = freshness
        lastSuccessfulSyncAt = snapshot?.lastSuccessfulSyncAt
        pendingUploadCount = snapshot?.pendingUploadCount ?? 0
        retryableUploadCount = snapshot?.retryableUploadCount ?? 0
        permanentFailureCount = snapshot?.permanentFailureCount ?? 0
        updatedAt = snapshot?.generatedAt
        deliveryNote = Self.deliveryNote(for: requestState)

        connection = Self.connection(
            snapshot: snapshot,
            activation: activation,
            isReachable: isReachable,
            freshness: freshness
        )
        headline = Self.headline(
            snapshot: snapshot,
            connection: connection,
            freshness: freshness
        )

        showsSyncAction = snapshot?.canRequestSync == true
        let actionBlock = Self.actionBlock(
            snapshot: snapshot,
            activation: activation,
            isReachable: isReachable,
            requestState: requestState
        )
        syncActionBlock = actionBlock
        canRequestSync = showsSyncAction && actionBlock == nil
        canRetryConnection = activation == .failed || snapshot == nil
    }

    public static func freshness(
        of snapshot: CompanionSyncSnapshot?,
        now: Date
    ) -> CompanionSnapshotFreshness {
        guard let snapshot else { return .unknown }
        let age = now.timeIntervalSince(snapshot.generatedAt)
        guard age >= 0 else { return .unknown }
        return age <= currentSnapshotInterval ? .current : .stale
    }

    private static func connection(
        snapshot: CompanionSyncSnapshot?,
        activation: CompanionActivationState,
        isReachable: Bool,
        freshness: CompanionSnapshotFreshness
    ) -> CompanionConnectionStatus {
        if activation == .failed {
            return .activationFailed
        }
        guard activation == .activated else {
            return .connecting
        }
        guard isReachable else {
            return .unreachable
        }
        guard snapshot != nil else {
            return .waitingForSnapshot
        }
        guard freshness == .current else {
            return .stale
        }
        return .reachable
    }

    private static func headline(
        snapshot: CompanionSyncSnapshot?,
        connection: CompanionConnectionStatus,
        freshness: CompanionSnapshotFreshness
    ) -> CompanionStatusHeadline {
        switch connection {
        case .activationFailed, .unreachable:
            return .phoneUnavailable
        case .connecting, .waitingForSnapshot:
            return .waitingForPhone
        case .reachable, .stale:
            break
        }
        guard let snapshot else { return .waitingForPhone }
        if snapshot.activity == .syncing, freshness == .current {
            return .syncing
        }
        if
            snapshot.activity == .attention
                || snapshot.readiness == .attention
                || snapshot.readiness == .unavailable
                || snapshot.permanentFailureCount > 0
        {
            return .needsAttention
        }
        if snapshot.readiness == .setupRequired {
            return .finishSetup
        }
        if freshness == .stale {
            return .statusOutOfDate
        }
        if freshness == .unknown {
            return .statusTimeUnavailable
        }
        if
            snapshot.readiness == .ready,
            snapshot.activity == .synced,
            snapshot.pendingUploadCount == 0,
            snapshot.retryableUploadCount == 0,
            snapshot.permanentFailureCount == 0
        {
            return .upToDate
        }
        return .ready
    }

    private static func actionBlock(
        snapshot: CompanionSyncSnapshot?,
        activation: CompanionActivationState,
        isReachable: Bool,
        requestState: CompanionRequestDeliveryState
    ) -> CompanionSyncActionBlock? {
        guard let snapshot, snapshot.canRequestSync else {
            return .snapshotDisallows
        }
        guard activation == .activated else {
            return .activationIncomplete
        }
        guard isReachable else {
            return .phoneUnreachable
        }
        guard snapshot.activity != .syncing else {
            return .syncInProgress
        }
        guard requestState != .sending, requestState != .accepted else {
            return .requestInProgress
        }
        return nil
    }

    private static func deliveryNote(
        for state: CompanionRequestDeliveryState
    ) -> CompanionDeliveryNote {
        switch state {
        case .idle:
            .none
        case .sending:
            .sending
        case .accepted:
            .accepted
        case .failed:
            .failed
        }
    }
}

public enum CompanionRequestDeliveryState: Equatable, Sendable {
    case idle
    case sending
    case accepted
    case failed
}

public struct CompanionRequestLifecycle: Equatable, Sendable {
    public private(set) var state: CompanionRequestDeliveryState = .idle
    public private(set) var requestID: UUID?

    private var baseline: CompanionSyncSnapshot.Semantics?
    private var receivedSemanticChange = false

    public init() {}

    public mutating func start(
        requestID: UUID,
        baseline snapshot: CompanionSyncSnapshot?
    ) {
        state = .sending
        self.requestID = requestID
        baseline = snapshot?.semantics
        receivedSemanticChange = false
    }

    public mutating func receiveReply(
        requestID: UUID,
        accepted: Bool
    ) {
        guard self.requestID == requestID else { return }
        if accepted, !receivedSemanticChange {
            state = .accepted
            return
        }
        reset(to: accepted ? .idle : .failed)
    }

    public mutating func receive(
        snapshot: CompanionSyncSnapshot
    ) {
        if state == .failed {
            reset(to: .idle)
            return
        }
        guard requestID != nil else { return }
        let changed = baseline.map { snapshot.semantics != $0 } ?? true
        guard changed else { return }
        receivedSemanticChange = true
        if state == .accepted {
            reset(to: .idle)
        }
    }

    public mutating func acceptedStateExpired(requestID: UUID) {
        guard self.requestID == requestID, state == .accepted else { return }
        reset(to: .idle)
    }

    private mutating func reset(to state: CompanionRequestDeliveryState) {
        self.state = state
        requestID = nil
        baseline = nil
        receivedSemanticChange = false
    }
}

public struct CompanionSnapshotPublicationState: Equatable, Sendable {
    private var lastPublishedSemantics: CompanionSyncSnapshot.Semantics?

    public init() {}

    public func needsPublication(
        of snapshot: CompanionSyncSnapshot
    ) -> Bool {
        snapshot.semantics != lastPublishedSemantics
    }

    public mutating func didPublish(_ snapshot: CompanionSyncSnapshot) {
        lastPublishedSemantics = snapshot.semantics
    }

    public mutating func invalidate() {
        lastPublishedSemantics = nil
    }
}
