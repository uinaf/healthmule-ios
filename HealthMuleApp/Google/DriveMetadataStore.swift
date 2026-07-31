import CryptoKit
import Foundation

struct DriveFolderSet: Codable, Equatable, Sendable {
    var rootID: String?
    var dailyID: String?
}

enum DriveFileIDStatus: String, Codable, Equatable, Sendable {
    case pendingCreate
    case committed
}

struct DriveFileIDSnapshot: Equatable, Sendable {
    let fileID: String?
    let status: DriveFileIDStatus?
    let destinationGeneration: UInt64
}

actor DriveMetadataStore {
    private struct State: Codable {
        var folders = DriveFolderSet()
        var fileIDs: [String: String] = [:]
        var fileIDStatuses: [String: DriveFileIDStatus]?
        var folderTransitionPending: Bool?
        var destinationGeneration: UInt64?
    }

    private static let stateKeyPrefix = "drive.metadata.v2"

    private let defaults: UserDefaults
    private let successfulConditionalWriteBarrier:
        (@Sendable () async -> Void)?
    private var states: [String: State] = [:]

    init(
        defaults: UserDefaults = .standard,
        successfulConditionalWriteBarrier:
            (@Sendable () async -> Void)? = nil
    ) {
        self.defaults = defaults
        self.successfulConditionalWriteBarrier =
            successfulConditionalWriteBarrier
    }

    func folders(for accountID: String) -> DriveFolderSet {
        state(for: accountID).folders
    }

    func setRootID(_ id: String, for accountID: String) {
        var state = state(for: accountID)
        if state.folders.rootID != id {
            state.folderTransitionPending = true
        }
        state.folders.rootID = id
        persist(state, for: accountID)
    }

    func setDailyID(_ id: String, for accountID: String) {
        var state = state(for: accountID)
        if state.folders.dailyID != id {
            state.folderTransitionPending = true
        }
        state.folders.dailyID = id
        persist(state, for: accountID)
    }

    func removeRootID(for accountID: String) {
        var state = state(for: accountID)
        if state.folders.rootID != nil {
            state.folderTransitionPending = true
        }
        state.folders.rootID = nil
        persist(state, for: accountID)
    }

    func removeDailyID(for accountID: String) {
        var state = state(for: accountID)
        if state.folders.dailyID != nil {
            state.folderTransitionPending = true
        }
        state.folders.dailyID = nil
        persist(state, for: accountID)
    }

    func commitFolders(
        rootID: String,
        dailyID: String,
        for accountID: String
    ) {
        var state = state(for: accountID)
        let folders = DriveFolderSet(rootID: rootID, dailyID: dailyID)
        if state.folderTransitionPending == true || state.folders != folders {
            state.fileIDs.removeAll()
            state.fileIDStatuses?.removeAll()
            state.destinationGeneration = (
                state.destinationGeneration ?? 0
            ) &+ 1
        }
        state.folders = folders
        state.folderTransitionPending = false
        persist(state, for: accountID)
    }

    func fileID(for key: String, accountID: String) -> String? {
        state(for: accountID).fileIDs[key]
    }

    func fileIDSnapshot(
        for key: String,
        accountID: String
    ) -> DriveFileIDSnapshot {
        let state = state(for: accountID)
        return DriveFileIDSnapshot(
            fileID: state.fileIDs[key],
            status: state.fileIDs[key].map { _ in
                state.fileIDStatuses?[key] ?? .committed
            },
            destinationGeneration: state.destinationGeneration ?? 0
        )
    }

    func setFileID(_ id: String, for key: String, accountID: String) {
        var state = state(for: accountID)
        state.fileIDs[key] = id
        state.fileIDStatuses?[key] = .committed
        if state.fileIDStatuses == nil {
            state.fileIDStatuses = [key: .committed]
        }
        persist(state, for: accountID)
    }

    func reserveFileID(_ id: String, for key: String, accountID: String) {
        var state = state(for: accountID)
        state.fileIDs[key] = id
        state.fileIDStatuses?[key] = .pendingCreate
        if state.fileIDStatuses == nil {
            state.fileIDStatuses = [key: .pendingCreate]
        }
        persist(state, for: accountID)
    }

    @discardableResult
    func setFileID(
        _ id: String,
        for key: String,
        accountID: String,
        ifDestinationGeneration generation: UInt64
    ) async -> Bool {
        var state = state(for: accountID)
        guard (state.destinationGeneration ?? 0) == generation else {
            return false
        }
        state.fileIDs[key] = id
        state.fileIDStatuses?[key] = .committed
        if state.fileIDStatuses == nil {
            state.fileIDStatuses = [key: .committed]
        }
        persist(state, for: accountID)
        if let successfulConditionalWriteBarrier {
            await successfulConditionalWriteBarrier()
        }
        return true
    }

    @discardableResult
    func reserveFileID(
        _ id: String,
        for key: String,
        accountID: String,
        ifDestinationGeneration generation: UInt64
    ) async -> Bool {
        var state = state(for: accountID)
        guard (state.destinationGeneration ?? 0) == generation else {
            return false
        }
        state.fileIDs[key] = id
        state.fileIDStatuses?[key] = .pendingCreate
        if state.fileIDStatuses == nil {
            state.fileIDStatuses = [key: .pendingCreate]
        }
        persist(state, for: accountID)
        if let successfulConditionalWriteBarrier {
            await successfulConditionalWriteBarrier()
        }
        return true
    }

    func removeFileID(for key: String, accountID: String) {
        var state = state(for: accountID)
        state.fileIDs.removeValue(forKey: key)
        state.fileIDStatuses?.removeValue(forKey: key)
        persist(state, for: accountID)
    }

    @discardableResult
    func removeFileID(
        for key: String,
        accountID: String,
        ifDestinationGeneration generation: UInt64
    ) -> Bool {
        var state = state(for: accountID)
        guard (state.destinationGeneration ?? 0) == generation else {
            return false
        }
        state.fileIDs.removeValue(forKey: key)
        state.fileIDStatuses?.removeValue(forKey: key)
        persist(state, for: accountID)
        return true
    }

    func isCurrentDestinationGeneration(
        _ generation: UInt64,
        for accountID: String
    ) -> Bool {
        (state(for: accountID).destinationGeneration ?? 0) == generation
    }

    private func state(for accountID: String) -> State {
        let key = Self.stateKey(for: accountID)
        if let state = states[key] {
            return state
        }
        let state: State
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(State.self, from: data)
        {
            state = decoded
        } else {
            state = State()
        }
        states[key] = state
        return state
    }

    private func persist(_ state: State, for accountID: String) {
        let key = Self.stateKey(for: accountID)
        states[key] = state
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    static func accountNamespace(for accountID: String) -> String {
        SHA256.hash(data: Data(accountID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func destinationNamespace(
        for accountID: String,
        rootID: String,
        dailyID: String
    ) -> String {
        let values = [accountID, rootID, dailyID]
        let payload = values
            .map { value in "\(Data(value.utf8).count):\(value)" }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func stateKey(for accountID: String) -> String {
        "\(stateKeyPrefix).\(accountNamespace(for: accountID))"
    }
}
