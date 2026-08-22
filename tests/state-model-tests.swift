import Foundation

private func snapshot(source: String, session: String, state: String, unread: Bool, time: Int64) -> PetSnapshot {
    PetSnapshot(
        schemaVersion: 1, source: source, sessionID: session, turn: 1, revision: 1,
        eventID: "\(source)-\(session)-\(state)", event: state, state: state,
        message: state, applicationBundleID: "test", unread: unread,
        receivedAt: time, lastActivityAt: time, activeSubagentIDs: nil
    )
}

@main
private struct StateModelTests {
    static func main() throws {
        precondition(PetStore.key(source: "claude", sessionID: "same") != PetStore.key(source: "codex", sessionID: "same"))
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RONALDINHO_PET_ROOT"]!, isDirectory: true)
        let values = [
            snapshot(source: "claude", session: "done", state: "completed", unread: true, time: 10),
            snapshot(source: "claude", session: "run", state: "running", unread: false, time: 20),
            snapshot(source: "claude", session: "wait", state: "waiting", unread: false, time: 5),
        ]
        let display = PetStore.display(from: values, root: root, now: 20)!
        precondition(display.snapshot.sessionID == "wait")
        precondition(display.pendingCount == 1)

        let failed = snapshot(source: "claude", session: "failed", state: "failed", unread: true, time: 30)
        precondition(PetStore.display(from: values + [failed], root: root, now: 30)!.snapshot.sessionID == "wait")

        let withoutWaiting = values.filter { $0.sessionID != "wait" }
        precondition(PetStore.display(from: withoutWaiting, root: root, now: 30)!.snapshot.sessionID == "done")
        try PetStore.write(
            PetAcknowledgement(schemaVersion: 1, source: "claude", sessionID: "done", turn: 1, eventID: "claude-done-completed"),
            to: PetStore.acknowledgementURL(root: root, source: "claude", sessionID: "done")
        )
        precondition(PetStore.display(from: withoutWaiting, root: root, now: 30)!.snapshot.sessionID == "run")
        print("state model tests passed")
    }
}
