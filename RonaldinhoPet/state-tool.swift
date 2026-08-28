import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func string(_ object: [String: Any], _ key: String) -> String? {
    guard let value = object[key] as? String, !value.isEmpty else { return nil }
    return value
}

private func applicationBundleID(host: PetHost, environment: [String: String]) -> String {
    switch environment["TERM_PROGRAM"] ?? "" {
    case "Apple_Terminal": return "com.apple.Terminal"
    case "iTerm.app", "iTerm2": return "com.googlecode.iterm2"
    case "WarpTerminal", "Warp": return "dev.warp.Warp-Stable"
    case "Ghostty", "ghostty": return "com.mitchellh.ghostty"
    case "kitty": return "net.kovidgoyal.kitty"
    case "WezTerm": return "com.github.wez.wezterm"
    case "cmux", "CMux", "cmux.app": return "com.cmuxterm.app"
    case "vscode", "Code": return "com.microsoft.VSCode"
    default:
        return environment["RONALDINHO_SOURCE_BUNDLE_ID"]
            ?? host.defaultBundleID
    }
}

private func withLock<T>(at lockURL: URL, body: () throws -> T) throws -> T {
    let manager = FileManager.default
    try manager.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    for _ in 0..<500 {
        do {
            try manager.createDirectory(at: lockURL, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: lockURL) }
            return try body()
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            usleep(10_000)
        }
    }
    throw NSError(domain: "RonaldinhoPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for session lock"])
}

private func ingest(source: String) {
    guard let adapter = PetHosts.adapter(id: source) else { fail("Unknown host: \(source)") }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sessionID = string(input, "session_id"),
          let event = string(input, "hook_event_name") else {
        FileHandle.standardError.write(Data("Player Companions ignored a hook without session_id/hook_event_name.\n".utf8))
        return
    }

    let root = PetStore.rootURL()
    let url = PetStore.snapshotURL(root: root, source: source, sessionID: sessionID)
    let lock = PetStore.lockURL(root: root, source: source, sessionID: sessionID)
    do {
        try withLock(at: lock) {
            let previous = PetStore.readSnapshot(at: url)
            guard let transition = adapter.transition(event: event, input: input, previous: previous) else { return }
            let state = transition.state
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let turn = event == "UserPromptSubmit" ? (previous?.turn ?? 0) + 1 : (previous?.turn ?? 0)
            let eventID = ["completed", "failed"].contains(state)
                ? PetStore.key(source: source, sessionID: "\(sessionID)\u{0}\(turn)\u{0}\(state)")
                : "\(turn)-\((previous?.revision ?? 0) + 1)"
            let snapshot = PetSnapshot(
                schemaVersion: PetStore.schemaVersion, source: source, sessionID: sessionID,
                turn: turn, revision: (previous?.revision ?? 0) + 1,
                eventID: eventID, event: event, state: state, message: transition.message,
                applicationBundleID: applicationBundleID(host: adapter.host, environment: ProcessInfo.processInfo.environment),
                unread: ["completed", "failed"].contains(state), receivedAt: now, lastActivityAt: now,
                activeSubagentIDs: transition.activeSubagentIDs
            )
            if let previous, previous.eventID == snapshot.eventID, previous.state == snapshot.state { return }
            try PetStore.write(snapshot, to: url)
        }
        PetStore.garbageCollect(root: root, now: Int64(Date().timeIntervalSince1970 * 1_000))
    } catch {
        fail("Unable to update pet state: \(error.localizedDescription)")
    }
}

private func acknowledge(_ arguments: [String]) {
    guard arguments.count == 6, let turn = Int(arguments[4]) else {
        fail("Usage: RonaldinhoPetState ack <source> <session-id> <turn> <event-id>")
    }
    let value = PetAcknowledgement(
        schemaVersion: PetStore.schemaVersion, source: arguments[2], sessionID: arguments[3],
        turn: turn, eventID: arguments[5]
    )
    do {
        try PetStore.write(value, to: PetStore.acknowledgementURL(
            root: PetStore.rootURL(), source: value.source, sessionID: value.sessionID
        ))
    } catch {
        fail("Unable to acknowledge pet state: \(error.localizedDescription)")
    }
}

private func inspect(_ arguments: [String]) {
    guard arguments.count == 4 else { fail("Usage: RonaldinhoPetState inspect <source> <session-id>") }
    let url = PetStore.snapshotURL(root: PetStore.rootURL(), source: arguments[2], sessionID: arguments[3])
    guard PetStore.readSnapshot(at: url) != nil, let data = try? Data(contentsOf: url) else {
        fail("No valid snapshot for the requested session")
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private func validateStore() {
    let root = PetStore.rootURL()
    let directory = PetStore.sessionsURL(root: root)
    let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.pathExtension == "json" {
        guard PetStore.readSnapshot(at: url) != nil else { fail("Invalid snapshot: \(url.lastPathComponent)") }
    }
    print(urls.filter { $0.pathExtension == "json" }.count)
}

@main
private struct StateTool {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { fail("Usage: RonaldinhoPetState ingest <source> | ack ...") }
        switch arguments[1] {
        case "ingest":
            guard arguments.count == 3 else { fail("Usage: RonaldinhoPetState ingest <source>") }
            ingest(source: arguments[2])
        case "ack": acknowledge(arguments)
        case "inspect": inspect(arguments)
        case "validate": validateStore()
        default: fail("Unknown command: \(arguments[1])")
        }
    }
}
