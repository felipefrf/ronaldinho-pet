import CryptoKit
import Foundation

struct PetSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let source: String
    let sessionID: String
    var turn: Int
    var revision: Int
    var eventID: String
    var event: String
    var state: String
    var message: String
    var applicationBundleID: String
    var unread: Bool
    var receivedAt: Int64
    var lastActivityAt: Int64
}

struct PetAcknowledgement: Codable {
    let schemaVersion: Int
    let source: String
    let sessionID: String
    let turn: Int
    let eventID: String
}

struct PetDisplay {
    let snapshot: PetSnapshot
    let pendingCount: Int
}

enum PetStore {
    static let schemaVersion = 1
    static let staleAfterSeconds: Int64 = 6 * 60 * 60
    static let retentionSeconds: Int64 = 30 * 24 * 60 * 60
    static let maximumRecords = 200

    static func rootURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["RONALDINHO_PET_ROOT"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RonaldinhoPet", isDirectory: true)
    }

    static func key(source: String, sessionID: String) -> String {
        let digest = SHA256.hash(data: Data("\(source)\u{0}\(sessionID)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sessionsURL(root: URL) -> URL { root.appendingPathComponent("sessions", isDirectory: true) }
    static func acknowledgementsURL(root: URL) -> URL { root.appendingPathComponent("acknowledgements", isDirectory: true) }
    static func snapshotURL(root: URL, source: String, sessionID: String) -> URL {
        sessionsURL(root: root).appendingPathComponent("\(key(source: source, sessionID: sessionID)).json")
    }
    static func acknowledgementURL(root: URL, source: String, sessionID: String) -> URL {
        acknowledgementsURL(root: root).appendingPathComponent("\(key(source: source, sessionID: sessionID)).json")
    }
    static func lockURL(root: URL, source: String, sessionID: String) -> URL {
        root.appendingPathComponent("locks", isDirectory: true)
            .appendingPathComponent(key(source: source, sessionID: sessionID), isDirectory: true)
    }

    static func readSnapshot(at url: URL) -> PetSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PetSnapshot.self, from: data),
              value.schemaVersion == schemaVersion else { return nil }
        return value
    }

    static func readAcknowledgement(at url: URL) -> PetAcknowledgement? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PetAcknowledgement.self, from: data),
              value.schemaVersion == schemaVersion else { return nil }
        return value
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    static func isAcknowledged(_ snapshot: PetSnapshot, root: URL) -> Bool {
        guard let acknowledgement = readAcknowledgement(
            at: acknowledgementURL(root: root, source: snapshot.source, sessionID: snapshot.sessionID)
        ) else { return false }
        return acknowledgement.turn == snapshot.turn && acknowledgement.eventID == snapshot.eventID
    }

    static func snapshots(root: URL) -> [PetSnapshot] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sessionsURL(root: root), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap(readSnapshot)
    }

    static func display(from snapshots: [PetSnapshot], root: URL, now: Int64) -> PetDisplay? {
        let values = snapshots.map { snapshot -> PetSnapshot in
            var value = snapshot
            if value.state == "running", now - value.lastActivityAt > staleAfterSeconds * 1_000 {
                value.state = "stale"
                value.message = "Session status is unknown"
            }
            if ["completed", "failed"].contains(value.state), isAcknowledged(value, root: root) {
                value.unread = false
            }
            return value
        }
        let pendingCount = values.filter { ["completed", "failed"].contains($0.state) && $0.unread }.count
        let priority = ["waiting": 5, "failed": 4, "running": 3, "completed": 2, "stale": 1, "idle": 0, "ended": 0]
        guard let selected = values.max(by: {
            let left = priority[$0.state] ?? -1
            let right = priority[$1.state] ?? -1
            return left == right ? $0.receivedAt < $1.receivedAt : left < right
        }) else { return nil }
        return PetDisplay(snapshot: selected, pendingCount: pendingCount)
    }

    static func garbageCollect(root: URL, now: Int64) {
        let manager = FileManager.default
        let all = snapshots(root: root)
        var removable = all.filter {
            let old = now - $0.lastActivityAt > retentionSeconds * 1_000
            return old && (["completed", "failed", "ended", "stale"].contains($0.state) || $0.state == "running")
        }.sorted { $0.lastActivityAt < $1.lastActivityAt }
        if all.count - removable.count > maximumRecords {
            let already = Set(removable.map { key(source: $0.source, sessionID: $0.sessionID) })
            removable += all.filter {
                !already.contains(key(source: $0.source, sessionID: $0.sessionID)) &&
                !["running", "waiting"].contains($0.state)
            }.sorted { $0.lastActivityAt < $1.lastActivityAt }
                .prefix(all.count - removable.count - maximumRecords)
        }
        for snapshot in removable {
            try? manager.removeItem(at: snapshotURL(root: root, source: snapshot.source, sessionID: snapshot.sessionID))
            try? manager.removeItem(at: acknowledgementURL(root: root, source: snapshot.source, sessionID: snapshot.sessionID))
        }
    }
}
