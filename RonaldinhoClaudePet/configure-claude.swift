import Foundation

typealias JSONDictionary = [String: Any]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func commandHandler(_ command: String, asynchronous: Bool = false) -> JSONDictionary {
    var handler: JSONDictionary = [
        "type": "command",
        "command": command,
        "timeout": 5,
    ]
    if asynchronous {
        handler["async"] = true
    }
    return handler
}

private func isRonaldinhoHandler(_ value: Any) -> Bool {
    guard
        let handler = value as? JSONDictionary,
        let command = handler["command"] as? String
    else { return false }
    return command.contains("ronaldinho-pet/")
}

private func groupsWithoutRonaldinho(_ value: Any?) -> [JSONDictionary] {
    guard let groups = value as? [Any] else { return [] }
    return groups.compactMap { value in
        guard var group = value as? JSONDictionary else { return nil }
        let handlers = group["hooks"] as? [Any] ?? []
        let retained = handlers.filter { !isRonaldinhoHandler($0) }
        guard !retained.isEmpty else { return nil }
        group["hooks"] = retained
        return group
    }
}

private func addPetHook(
    hooks: inout JSONDictionary,
    event: String,
    matcher: String? = nil,
    handler: JSONDictionary
) {
    let rawGroups = hooks[event] as? [Any] ?? []
    var groups = rawGroups.compactMap { $0 as? JSONDictionary }
    var group: JSONDictionary = ["hooks": [handler]]
    if let matcher {
        group["matcher"] = matcher
    }
    groups.append(group)
    hooks[event] = groups
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fail("Usage: configure-claude <absolute-companion-directory>")
}

let companionDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
let claudeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    .appendingPathComponent(".claude", isDirectory: true)
let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
let commandURL = claudeDirectory
    .appendingPathComponent("commands", isDirectory: true)
    .appendingPathComponent("pet.md")

var settings: JSONDictionary = [:]
if FileManager.default.fileExists(atPath: settingsURL.path) {
    do {
        let data = try Data(contentsOf: settingsURL)
        guard let decoded = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            fail("Claude settings must contain a JSON object: \(settingsURL.path)")
        }
        settings = decoded
    } catch {
        fail("Unable to read Claude settings: \(error.localizedDescription)")
    }
}

var hooks = settings["hooks"] as? JSONDictionary ?? [:]
let petHookEvents = [
    "PermissionRequest",
    "PostToolUse",
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "Notification",
    "Stop",
    "SessionEnd",
]
for event in petHookEvents {
    hooks[event] = groupsWithoutRonaldinho(hooks[event])
}
let updateState = companionDirectory.appendingPathComponent("update-state.sh").path
func updateCommand(_ state: String, _ message: String, unread: Bool) -> String {
    "\(updateState) \(state) '\(message)' '' \(unread ? "true" : "false")"
}

addPetHook(
    hooks: &hooks,
    event: "PermissionRequest",
    handler: commandHandler(updateCommand("waiting", "Needs your approval", unread: true))
)
addPetHook(
    hooks: &hooks,
    event: "PostToolUse",
    handler: commandHandler(updateCommand("running", "Claude is working…", unread: false))
)
addPetHook(
    hooks: &hooks,
    event: "SessionStart",
    handler: commandHandler(updateCommand("idle", "Ready — click to return", unread: false))
)
addPetHook(
    hooks: &hooks,
    event: "UserPromptSubmit",
    handler: commandHandler(updateCommand("running", "Claude is thinking…", unread: false))
)
addPetHook(
    hooks: &hooks,
    event: "PreToolUse",
    matcher: "",
    handler: commandHandler(updateCommand("running", "Claude is working…", unread: false))
)
addPetHook(
    hooks: &hooks,
    event: "Notification",
    matcher: "agent_needs_input",
    handler: commandHandler(updateCommand("waiting", "Needs your input", unread: true), asynchronous: true)
)
addPetHook(
    hooks: &hooks,
    event: "Notification",
    matcher: "agent_completed",
    handler: commandHandler(updateCommand("idle", "All caught up", unread: true), asynchronous: true)
)
addPetHook(
    hooks: &hooks,
    event: "Stop",
    handler: commandHandler(updateCommand("idle", "All caught up", unread: true), asynchronous: true)
)
addPetHook(
    hooks: &hooks,
    event: "SessionEnd",
    handler: commandHandler(updateCommand("idle", "Session ended", unread: false), asynchronous: true)
)
settings["hooks"] = hooks

let petCommand = """
---
description: Show the Ronaldinho companion pet for this Claude Code session.
allowed-tools: Bash(\(companionDirectory.path)/show-pet.sh)
---

Show the Ronaldinho companion now and report the command result in one short sentence.

!`\(companionDirectory.path)/show-pet.sh`
"""

do {
    try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
    let settingsData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    try settingsData.write(to: settingsURL, options: .atomic)
    try FileManager.default.createDirectory(at: commandURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try petCommand.write(to: commandURL, atomically: true, encoding: .utf8)
} catch {
    fail("Unable to configure Claude Code: \(error.localizedDescription)")
}

print("Configured \(settingsURL.path) and \(commandURL.path).")
