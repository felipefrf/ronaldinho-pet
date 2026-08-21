import Foundation

typealias JSONDictionary = [String: Any]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func handler(_ command: String) -> JSONDictionary {
    ["type": "command", "command": command, "timeout": 5]
}

private func command(of value: Any) -> String? {
    (value as? JSONDictionary)?["command"] as? String
}

private func groupsRemoving(commands: Set<String>, from value: Any?) -> [JSONDictionary] {
    guard let groups = value as? [Any] else { return [] }
    return groups.compactMap { raw in
        guard var group = raw as? JSONDictionary else { return nil }
        let retained = (group["hooks"] as? [Any] ?? []).filter { rawHandler in
            guard let value = command(of: rawHandler) else { return true }
            return !commands.contains(value)
        }
        guard !retained.isEmpty else { return nil }
        group["hooks"] = retained
        return group
    }
}

private func add(_ event: String, matcher: String? = nil, command: String, hooks: inout JSONDictionary) {
    var groups = (hooks[event] as? [Any] ?? []).compactMap { $0 as? JSONDictionary }
    var group: JSONDictionary = ["hooks": [handler(command)]]
    if let matcher { group["matcher"] = matcher }
    groups.append(group)
    hooks[event] = groups
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fail("Usage: RonaldinhoConfigureHooks <installation-root> <claude|codex> <install|remove>") }
let host = arguments[2]
let mode = arguments[3]
guard ["claude", "codex"].contains(host) else { fail("Host must be claude or codex") }
guard ["install", "remove"].contains(mode) else { fail("Mode must be install or remove") }

let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
let helper = root.appendingPathComponent("RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState").path
let app = root.appendingPathComponent("RonaldinhoPet.app").path
let ingest = "\(shellQuote(helper)) ingest \(host)"

let environment = ProcessInfo.processInfo.environment
let home = environment["RONALDINHO_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let configDirectory = home.appendingPathComponent(host == "claude" ? ".claude" : ".codex", isDirectory: true)
let settingsURL = configDirectory.appendingPathComponent(host == "claude" ? "settings.json" : "hooks.json")
let commandURL = configDirectory.appendingPathComponent("commands/pet.md")

var settings: JSONDictionary = [:]
var originalData: Data?
if FileManager.default.fileExists(atPath: settingsURL.path) {
    do {
        let data = try Data(contentsOf: settingsURL)
        guard let decoded = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            fail("Claude settings must contain a JSON object: \(settingsURL.path)")
        }
        originalData = data
        settings = decoded
    } catch { fail("Unable to read Claude settings: \(error.localizedDescription)") }
}

let legacyRoot = home.appendingPathComponent(".claude/ronaldinho-pet", isDirectory: true)
let legacyUpdate = legacyRoot.appendingPathComponent("update-state.sh").path
let legacyCommands: Set<String> = [
    "\(legacyUpdate) idle 'All caught up' '' true",
    "\(legacyUpdate) idle 'Ready — click to return' '' false",
    "\(legacyUpdate) idle 'Session ended' '' false",
    "\(legacyUpdate) running 'Claude is thinking…' '' false",
    "\(legacyUpdate) running 'Claude is working…' '' false",
    "\(legacyUpdate) waiting 'Needs your approval' '' true",
    "\(legacyUpdate) waiting 'Needs your input' '' true",
]
let ownedCommands = (host == "claude" ? legacyCommands : []).union([ingest])

var hooks = settings["hooks"] as? JSONDictionary ?? [:]
let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
for event in events { hooks[event] = groupsRemoving(commands: ownedCommands, from: hooks[event]) }
if mode == "install" {
    add("SessionStart", command: ingest, hooks: &hooks)
    add("UserPromptSubmit", command: ingest, hooks: &hooks)
    add("PreToolUse", matcher: "*", command: ingest, hooks: &hooks)
    add("PostToolUse", matcher: "*", command: ingest, hooks: &hooks)
    add("PermissionRequest", matcher: "*", command: ingest, hooks: &hooks)
    add("Notification", matcher: host == "claude" ? "permission_prompt|idle_prompt|agent_needs_input" : "*", command: ingest, hooks: &hooks)
    add("Stop", command: ingest, hooks: &hooks)
    add("StopFailure", matcher: "*", command: ingest, hooks: &hooks)
    add("SessionEnd", command: ingest, hooks: &hooks)
}
settings["hooks"] = hooks

let petCommand = """
---
description: Show the Ronaldinho companion pet.
allowed-tools: Bash(/usr/bin/open:*)
---

!`/usr/bin/open -a \(shellQuote(app))`

Ronaldinho companion is ready.
"""

do {
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    if originalData != data {
        let attributes = originalData.flatMap { _ in try? FileManager.default.attributesOfItem(atPath: settingsURL.path) }
        if originalData != nil {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("\(settingsURL.lastPathComponent).ronaldinho-backup-\(formatter.string(from: Date()))")
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try data.write(to: settingsURL, options: [.atomic])
        if let permissions = attributes?[.posixPermissions] { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: settingsURL.path) }
    }
    if host == "claude" && mode == "install" {
        try FileManager.default.createDirectory(at: commandURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? String(contentsOf: commandURL, encoding: .utf8)) != petCommand {
            try petCommand.write(to: commandURL, atomically: true, encoding: .utf8)
        }
    } else if host == "claude", (try? String(contentsOf: commandURL, encoding: .utf8)) == petCommand {
        try FileManager.default.removeItem(at: commandURL)
    }
} catch { fail("Unable to configure Claude: \(error.localizedDescription)") }

print("\(mode == "install" ? "Configured" : "Removed") Ronaldinho hooks for \(host).")
