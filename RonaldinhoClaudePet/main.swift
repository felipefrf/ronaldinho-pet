import Cocoa

private struct CompanionState: Decodable {
    let state: String?
    let message: String?
    let terminalBundleID: String?
    let showNonce: String?
    let unread: Bool?
}

private final class PetView: NSView {
    private let cellWidth: CGFloat = 192
    private let cellHeight: CGFloat = 208
    private let stateFileURL: URL
    private let spriteSheet: NSImage?
    private let animationSpecs: [String: (row: Int, frames: Int)] = [
        "idle": (0, 7),
        "running-right": (1, 8),
        "running-left": (2, 8),
        "waving": (3, 4),
        "jumping": (4, 5),
        "failed": (5, 8),
        "waiting": (6, 6),
        "running": (7, 6),
        "review": (8, 6),
    ]

    private var state = "idle"
    private var frameIndex = 0
    private var dragStart: NSPoint?
    private var isDragging = false
    private var didDrag = false
    private var isHovering = false
    private var interactionState: String?
    private var statusMessage: String?
    private var terminalBundleID: String?
    private var showNonce: String?
    private var statusExpanded = false
    private var statusUnread = false
    private var trackingArea: NSTrackingArea?
    private var animationTimer: Timer?
    private var stateTimer: Timer?
    private let activateClaudeSession: (String?) -> Bool
    private let showCompanion: () -> Void
    private let setStatusPanelExpanded: (Bool) -> Void
    private let acknowledgeStatus: () -> Void

    override var isFlipped: Bool { true }

    init(
        frame: NSRect,
        spriteSheetURL: URL?,
        stateFileURL: URL,
        activateClaudeSession: @escaping (String?) -> Bool,
        showCompanion: @escaping () -> Void,
        setStatusPanelExpanded: @escaping (Bool) -> Void,
        acknowledgeStatus: @escaping () -> Void
    ) {
        self.stateFileURL = stateFileURL
        self.spriteSheet = spriteSheetURL.flatMap(NSImage.init(contentsOf:))
        self.activateClaudeSession = activateClaudeSession
        self.showCompanion = showCompanion
        self.setStatusPanelExpanded = setStatusPanelExpanded
        self.acknowledgeStatus = acknowledgeStatus
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        readState()

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 6.0, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.readState()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
        stateTimer?.invalidate()
    }

    private func normalizedState(_ value: String?) -> String {
        guard let value, animationSpecs[value] != nil else { return "idle" }
        return value
    }

    private var displayedState: String {
        interactionState ?? state
    }

    private var statusAreaHeight: CGFloat {
        statusExpanded ? 36 : 18
    }

    private var petRect: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - statusAreaHeight))
    }

    private var statusControlRect: NSRect {
        let height: CGFloat = statusExpanded ? 26 : 10
        let width: CGFloat = statusExpanded ? bounds.width - 38 : 42
        return NSRect(
            x: (bounds.width - width) / 2,
            y: petRect.maxY + (statusAreaHeight - height) / 2,
            width: width,
            height: height
        )
    }

    private func readState() {
        guard
            let data = try? Data(contentsOf: stateFileURL),
            let decoded = try? JSONDecoder().decode(CompanionState.self, from: data)
        else { return }

        let nextState = normalizedState(decoded.state)
        if nextState != state {
            state = nextState
            if interactionState == nil {
                frameIndex = 0
            }
            if nextState == "idle" {
                setStatusExpanded(false)
            } else if nextState == "waiting" {
                setStatusExpanded(true)
            }
            needsDisplay = true
        }

        if decoded.message != statusMessage || decoded.terminalBundleID != terminalBundleID || (decoded.unread ?? false) != statusUnread {
            statusMessage = decoded.message
            terminalBundleID = decoded.terminalBundleID
            statusUnread = decoded.unread ?? false
            needsDisplay = true
        }

        if decoded.showNonce != showNonce {
            showNonce = decoded.showNonce
            if let showNonce, !showNonce.isEmpty {
                showCompanion()
            }
        }
    }

    private func advanceFrame() {
        guard let animation = animationSpecs[displayedState] else { return }
        frameIndex = (frameIndex + 1) % animation.frames
        needsDisplay = true
    }

    private func setInteractionState(_ nextState: String?) {
        guard nextState != interactionState else { return }
        interactionState = nextState
        frameIndex = 0
        needsDisplay = true
    }

    private func setStatusExpanded(_ expanded: Bool) {
        guard statusExpanded != expanded else { return }
        statusExpanded = expanded
        setStatusPanelExpanded(expanded)
        needsDisplay = true
    }

    private func acknowledgeUnreadStatus() {
        guard statusUnread else { return }
        statusUnread = false
        acknowledgeStatus()
        needsDisplay = true
    }

    private func defaultStatusMessage() -> String {
        switch state {
        case "running":
            return "Claude is working…"
        case "waiting":
            return "Input needed — click to return"
        case "review":
            return "Reviewing…"
        case "failed":
            return "Something needs attention"
        default:
            return "Ready — click to return"
        }
    }

    private func statusTint() -> NSColor {
        if state == "idle" && !statusUnread {
            return .systemGray
        }
        switch state {
        case "running", "review":
            return .systemBlue
        case "waiting":
            return .systemOrange
        case "failed":
            return .systemRed
        default:
            return .systemGreen
        }
    }

    private func drawStatusBadge() {
        let badgeRect = statusControlRect
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
        let tint = statusTint()

        if !statusExpanded {
            let tuckedFill = state == "idle" && !statusUnread
                ? NSColor.white.withAlphaComponent(0.14)
                : tint.withAlphaComponent(0.82)
            tuckedFill.setFill()
            badgePath.fill()
            NSColor.white.withAlphaComponent(state == "idle" && !statusUnread ? 0.18 : 0.35).setStroke()
            badgePath.lineWidth = 1
            badgePath.stroke()
            return
        }

        NSColor.white.withAlphaComponent(0.74).setFill()
        badgePath.fill()
        tint.withAlphaComponent(0.20).setFill()
        badgePath.fill()
        NSColor.white.withAlphaComponent(0.80).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        let dotRect = NSRect(x: badgeRect.minX + 10, y: badgeRect.midY - 3.5, width: 7, height: 7)
        tint.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let message: String
        if let statusMessage, !statusMessage.isEmpty {
            message = statusMessage
        } else {
            message = defaultStatusMessage()
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.black.withAlphaComponent(0.82),
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .paragraphStyle: paragraphStyle,
        ]
        message.draw(in: NSRect(x: dotRect.maxX + 6, y: badgeRect.minY + 6, width: badgeRect.maxX - dotRect.maxX - 16, height: 14), withAttributes: attributes)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let spriteSheet, let animation = animationSpecs[displayedState] else {
            let label = "Ronaldinho pet asset missing"
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
            label.draw(in: bounds.insetBy(dx: 16, dy: 16), withAttributes: attributes)
            return
        }

        let sheetHeight = spriteSheet.size.height
        let sourceRect = NSRect(
            x: CGFloat(frameIndex) * cellWidth,
            y: sheetHeight - CGFloat(animation.row + 1) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        spriteSheet.draw(
            in: petRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        drawStatusBadge()
    }

    override func mouseDown(with event: NSEvent) {
        let viewLocation = convert(event.locationInWindow, from: nil)
        if statusControlRect.contains(viewLocation) {
            acknowledgeUnreadStatus()
            setStatusExpanded(!statusExpanded)
            return
        }
        guard petRect.contains(viewLocation) else { return }
        dragStart = event.locationInWindow
        isDragging = true
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let location = event.locationInWindow
        let horizontalDelta = location.x - dragStart.x
        let verticalDelta = location.y - dragStart.y
        if abs(horizontalDelta) > 1 || abs(verticalDelta) > 1 {
            didDrag = true
            setInteractionState(horizontalDelta >= 0 ? "running-right" : "running-left")
        }
        let origin = NSPoint(
            x: window.frame.origin.x + location.x - dragStart.x,
            y: window.frame.origin.y + location.y - dragStart.y
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        dragStart = nil
        setInteractionState(isHovering ? "jumping" : nil)

        if !didDrag {
            acknowledgeUnreadStatus()
            if !activateClaudeSession(terminalBundleID) {
                statusMessage = "Open a Claude terminal to return"
                needsDisplay = true
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: petRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        if !isDragging {
            setInteractionState("jumping")
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isDragging {
            setInteractionState(nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let resetItem = menu.addItem(withTitle: "Reset position", action: #selector(AppDelegate.resetPosition), keyEquivalent: "")
        resetItem.target = NSApp.delegate as? AppDelegate
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Ronaldinho companion", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        quitItem.target = NSApp.delegate as? AppDelegate
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let companionDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/ronaldinho-pet", isDirectory: true)
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let spriteSheetURL = Bundle.main.url(forResource: "spritesheet", withExtension: "webp")
        let stateFileURL = companionDirectory.appendingPathComponent("state.json")
        let rect = initialFrame()
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.contentView = PetView(
            frame: NSRect(origin: .zero, size: rect.size),
            spriteSheetURL: spriteSheetURL,
            stateFileURL: stateFileURL,
            activateClaudeSession: { [weak self] bundleID in
                self?.activateClaudeTerminal(bundleID: bundleID) ?? false
            },
            showCompanion: { [weak self] in
                self?.showCompanion()
            },
            setStatusPanelExpanded: { [weak self] expanded in
                self?.setStatusPanelExpanded(expanded)
            },
            acknowledgeStatus: { [weak self] in
                self?.acknowledgeStatus()
            }
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func activateClaudeTerminal(bundleID: String?) -> Bool {
        let fallbacks = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "com.cmuxterm.app",
            "com.microsoft.VSCode",
        ]
        let candidates = [bundleID].compactMap { $0 } + fallbacks
        let runningApplications = NSWorkspace.shared.runningApplications
        for candidate in candidates {
            if let application = runningApplications.first(where: { $0.bundleIdentifier == candidate && !$0.isTerminated }) {
                return application.activate(options: [])
            }
        }
        return false
    }

    private func showCompanion() {
        guard let panel else { return }
        if let screen = screenForMouse(), !screen.visibleFrame.intersects(panel.frame) {
            panel.setFrame(
                initialFrame(on: screen, statusExpanded: panel.frame.height > panelSize(statusExpanded: false).height),
                display: true,
                animate: false
            )
        }
        panel.orderFrontRegardless()
    }

    private func setStatusPanelExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let targetHeight = panelSize(statusExpanded: expanded).height
        guard panel.frame.height != targetHeight else { return }
        let topEdge = panel.frame.maxY
        var frame = panel.frame
        frame.size.height = targetHeight
        frame.origin.y = topEdge - targetHeight
        panel.setFrame(frame, display: true, animate: true)
    }

    private func acknowledgeStatus() {
        let process = Process()
        process.executableURL = companionDirectory.appendingPathComponent("acknowledge-state.sh")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func screenForMouse() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    }

    private func panelSize(statusExpanded: Bool) -> NSSize {
        NSSize(width: 240, height: statusExpanded ? 296 : 278)
    }

    private func initialFrame(on preferredScreen: NSScreen? = nil, statusExpanded: Bool = false) -> NSRect {
        let size = panelSize(statusExpanded: statusExpanded)
        guard let screen = preferredScreen ?? screenForMouse() ?? NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        return NSRect(x: visible.maxX - size.width - 26, y: visible.minY + 26, width: size.width, height: size.height)
    }

    @objc func resetPosition() {
        let expanded = panel.map { $0.frame.height > panelSize(statusExpanded: false).height } ?? false
        panel?.setFrame(initialFrame(statusExpanded: expanded), display: true, animate: true)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
