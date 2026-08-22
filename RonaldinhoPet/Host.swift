import Foundation

struct PetHost: Equatable {
    let id: String
    let name: String
    let defaultBundleID: String
    let configDirectory: String
    let settingsFilename: String
    let notificationMatcher: String
    let hookEvents: [String]
}

enum PetHosts {
    static let claude = PetHost(
        id: "claude",
        name: "Claude",
        defaultBundleID: "com.anthropic.claude-code",
        configDirectory: ".claude",
        settingsFilename: "settings.json",
        notificationMatcher: "permission_prompt|idle_prompt|agent_needs_input",
        hookEvents: commonEvents
    )
    static let codex = PetHost(
        id: "codex",
        name: "Codex",
        defaultBundleID: "com.openai.codex",
        configDirectory: ".codex",
        settingsFilename: "hooks.json",
        notificationMatcher: "*",
        hookEvents: commonEvents + ["Elicitation"]
    )
    static let all = [claude, codex]
    static let allHookEvents = Array(Set(all.flatMap(\.hookEvents))).sorted()
    static var expandedStatusHeight: CGFloat { 34 + CGFloat(all.count * 21) }

    static func host(id: String) -> PetHost? { all.first { $0.id == id } }

    private static let commonEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "PostToolBatch", "PermissionRequest", "Notification",
        "SubagentStart", "SubagentStop", "Stop", "StopFailure", "SessionEnd",
    ]
}
