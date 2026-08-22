import Foundation

struct PetTransition {
    let state: String
    let message: String
    let activeSubagentIDs: [String]
}

protocol PetHostAdapter {
    var host: PetHost { get }
    func transition(event: String, input: [String: Any], previous: PetSnapshot?) -> PetTransition?
}

extension PetHosts {
    static func adapter(id: String) -> PetHostAdapter? {
        switch id {
        case claude.id: return ClaudeHostAdapter()
        case codex.id: return CodexHostAdapter()
        default: return nil
        }
    }
}

private func stringValue(_ input: [String: Any], _ key: String) -> String? {
    guard let value = input[key] as? String, !value.isEmpty else { return nil }
    return value
}

private func commonTransition(
    host: PetHost,
    event: String,
    input: [String: Any],
    previous: PetSnapshot?
) -> PetTransition? {
    var agents = previous?.activeSubagentIDs ?? []
    switch event {
    case "SessionStart":
        return PetTransition(state: "idle", message: "\(host.name) is ready", activeSubagentIDs: [])
    case "UserPromptSubmit":
        return PetTransition(state: "running", message: "\(host.name) is thinking…", activeSubagentIDs: agents)
    case "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch":
        if let previous, ["completed", "failed", "ended"].contains(previous.state) { return nil }
        return PetTransition(state: "running", message: "\(host.name) is working…", activeSubagentIDs: agents)
    case "SubagentStart":
        if let agentID = stringValue(input, "agent_id"), !agents.contains(agentID) { agents.append(agentID) }
        return PetTransition(state: "running", message: "\(host.name) is waiting for agents…", activeSubagentIDs: agents)
    case "SubagentStop":
        if let agentID = stringValue(input, "agent_id") { agents.removeAll { $0 == agentID } }
        return PetTransition(state: "running", message: "\(host.name) is working…", activeSubagentIDs: agents)
    case "Elicitation":
        return PetTransition(state: "waiting", message: "\(host.name) needs your input", activeSubagentIDs: agents)
    case "Notification":
        let type = stringValue(input, "notification_type") ?? ""
        guard ["permission_prompt", "idle_prompt", "agent_needs_input"].contains(type) else { return nil }
        return PetTransition(state: "waiting", message: "\(host.name) needs your input", activeSubagentIDs: agents)
    case "Stop":
        let payloadHasAgents = !(input["background_tasks"] as? [Any] ?? []).isEmpty
        if payloadHasAgents || !agents.isEmpty {
            return PetTransition(state: "running", message: "\(host.name) is waiting for agents…", activeSubagentIDs: agents)
        }
        return PetTransition(state: "completed", message: "\(host.name) finished", activeSubagentIDs: [])
    case "StopFailure":
        return PetTransition(state: "failed", message: "\(host.name) stopped with an error", activeSubagentIDs: agents)
    case "SessionEnd":
        return PetTransition(state: "ended", message: "\(host.name) session ended", activeSubagentIDs: [])
    default:
        return nil
    }
}

private struct ClaudeHostAdapter: PetHostAdapter {
    let host = PetHosts.claude

    func transition(event: String, input: [String: Any], previous: PetSnapshot?) -> PetTransition? {
        if event == "PermissionRequest" {
            return PetTransition(
                state: "waiting",
                message: "Claude needs your input",
                activeSubagentIDs: previous?.activeSubagentIDs ?? []
            )
        }
        return commonTransition(host: host, event: event, input: input, previous: previous)
    }
}

private struct CodexHostAdapter: PetHostAdapter {
    let host = PetHosts.codex

    func transition(event: String, input: [String: Any], previous: PetSnapshot?) -> PetTransition? {
        if event == "PermissionRequest" {
            if let previous, ["completed", "failed", "ended"].contains(previous.state) { return nil }
            return PetTransition(
                state: "running",
                message: "Codex is checking permission…",
                activeSubagentIDs: previous?.activeSubagentIDs ?? []
            )
        }
        return commonTransition(host: host, event: event, input: input, previous: previous)
    }
}
