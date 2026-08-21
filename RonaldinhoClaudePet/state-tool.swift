import Foundation

private struct CompanionState: Codable {
    var state: String
    var message: String
    var terminalBundleID: String
    var showNonce: String
    var unread: Bool
    var updatedAt: Int
}

private let companionDirectory = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".claude/ronaldinho-pet", isDirectory: true)
private let stateFileURL = companionDirectory.appendingPathComponent("state.json")

private func detectedTerminalBundleID() -> String {
    switch ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "" {
    case "Apple_Terminal":
        return "com.apple.Terminal"
    case "iTerm.app", "iTerm2":
        return "com.googlecode.iterm2"
    case "WarpTerminal", "Warp":
        return "dev.warp.Warp-Stable"
    case "Ghostty":
        return "com.mitchellh.ghostty"
    case "kitty":
        return "net.kovidgoyal.kitty"
    case "WezTerm":
        return "com.github.wez.wezterm"
    case "cmux", "CMux", "cmux.app":
        return "com.cmuxterm.app"
    case "vscode", "Code":
        return "com.microsoft.VSCode"
    default:
        return ProcessInfo.processInfo.environment["CLAUDE_TERMINAL_BUNDLE_ID"] ?? ""
    }
}

private func readState() -> CompanionState? {
    guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
    return try? JSONDecoder().decode(CompanionState.self, from: data)
}

private func writeState(_ state: CompanionState) throws {
    try FileManager.default.createDirectory(at: companionDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(state)
    try data.write(to: stateFileURL, options: .atomic)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("Usage: RonaldinhoPetState update <state> <message> [show-nonce] [unread] | ack")
}

switch arguments[1] {
case "update":
    guard arguments.count >= 4 else {
        fail("update requires a state and message")
    }
    let previous = readState()
    let explicitUnread = arguments.count >= 6 ? arguments[5] : nil
    let unread: Bool
    switch explicitUnread {
    case "true": unread = true
    case "false": unread = false
    default: unread = previous?.unread ?? false
    }
    let detectedBundleID = detectedTerminalBundleID()
    let state = CompanionState(
        state: arguments[2],
        message: arguments[3],
        terminalBundleID: detectedBundleID.isEmpty ? (previous?.terminalBundleID ?? "") : detectedBundleID,
        showNonce: arguments.count >= 5 ? arguments[4] : "",
        unread: unread,
        updatedAt: Int(Date().timeIntervalSince1970)
    )
    do {
        try writeState(state)
    } catch {
        fail("Unable to write Ronaldinho pet state: \(error.localizedDescription)")
    }

case "ack":
    guard var state = readState() else { exit(0) }
    state.unread = false
    state.updatedAt = Int(Date().timeIntervalSince1970)
    do {
        try writeState(state)
    } catch {
        fail("Unable to acknowledge Ronaldinho pet state: \(error.localizedDescription)")
    }

default:
    fail("Unknown Ronaldinho pet state command: \(arguments[1])")
}
