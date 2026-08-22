import Cocoa

final class ConnectionsWindowController: NSWindowController {
    private let background = NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.065, alpha: 1)
    private let accent = NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.08, alpha: 1)
    private var statusLabels: [String: NSTextField] = [:]
    private var buttons: [String: NSButton] = [:]
    private let messageLabel = NSTextField(labelWithString: "")

    var hasConnectedHost: Bool {
        PetHosts.all.contains { status(for: $0) }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ronaldinho Pet"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = background.cgColor

        let title = NSTextField(labelWithString: "CONNECTIONS")
        title.frame = NSRect(x: 24, y: 186, width: 180, height: 20)
        title.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        title.textColor = accent
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Choose which apps Ronaldinho should watch.")
        subtitle.frame = NSRect(x: 24, y: 160, width: 360, height: 20)
        subtitle.textColor = .white.withAlphaComponent(0.72)
        content.addSubview(subtitle)

        for (index, host) in PetHosts.all.enumerated() {
            let y = 103 - CGFloat(index * 54)
            let row = NSView(frame: NSRect(x: 20, y: y, width: 380, height: 46))
            row.wantsLayer = true
            row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
            row.layer?.cornerRadius = 8

            let name = NSTextField(labelWithString: host.name)
            name.frame = NSRect(x: 14, y: 22, width: 150, height: 18)
            name.font = .systemFont(ofSize: 13, weight: .semibold)
            name.textColor = .white
            row.addSubview(name)

            let status = NSTextField(labelWithString: "Checking…")
            status.frame = NSRect(x: 14, y: 5, width: 180, height: 16)
            status.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            row.addSubview(status)
            statusLabels[host.id] = status

            let button = NSButton(title: "Connect", target: self, action: #selector(toggleConnection(_:)))
            button.frame = NSRect(x: 270, y: 9, width: 94, height: 28)
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(host.id)
            button.setAccessibilityLabel("Connect \(host.name)")
            row.addSubview(button)
            buttons[host.id] = button

            content.addSubview(row)
        }

        messageLabel.frame = NSRect(x: 24, y: 12, width: 372, height: 18)
        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .white.withAlphaComponent(0.68)
        messageLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(messageLabel)
    }

    private func refresh() {
        for host in PetHosts.all {
            let connected = status(for: host)
            statusLabels[host.id]?.stringValue = connected ? "● CONNECTED" : "○ NOT CONNECTED"
            statusLabels[host.id]?.textColor = connected ? .systemGreen : .white.withAlphaComponent(0.55)
            buttons[host.id]?.title = connected ? "Disconnect" : "Connect"
            buttons[host.id]?.setAccessibilityLabel("\(connected ? "Disconnect" : "Connect") \(host.name)")
        }
    }

    private func status(for host: PetHost) -> Bool {
        (try? run(host: host, mode: "status")) == "connected"
    }

    @objc private func toggleConnection(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let host = PetHosts.host(id: id) else { return }
        let mode = status(for: host) ? "remove" : "install"
        do {
            _ = try run(host: host, mode: mode)
            messageLabel.stringValue = mode == "install"
                ? "Connected. Restart \(host.name) so it reloads the hooks."
                : "\(host.name) disconnected."
        } catch {
            messageLabel.stringValue = error.localizedDescription
        }
        refresh()
    }

    @discardableResult
    private func run(host: PetHost, mode: String) throws -> String {
        guard let executable = Bundle.main.url(forResource: "RonaldinhoConfigureHooks", withExtension: nil) else {
            throw NSError(domain: "RonaldinhoPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection helper is missing. Reinstall Ronaldinho Pet."])
        }
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = [Bundle.main.bundleURL.deletingLastPathComponent().path, host.id, mode]
        process.standardOutput = output
        process.standardError = error
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "RonaldinhoPet", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
