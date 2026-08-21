import Cocoa

private final class PetView: NSView {
    private let cellWidth: CGFloat = 192
    private let cellHeight: CGFloat = 208
    private let stateRootURL: URL
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
    private let scoreboardBackground = NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.065, alpha: 0.96)
    private let scoreboardAccent = NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.08, alpha: 0.82)

    private var state = "idle"
    private var frameIndex = 0
    private var dragStart: NSPoint?
    private var isDragging = false
    private var didDrag = false
    private var isHovering = false
    private var interactionState: String?
    private var statusMessage: String?
    private var displayedSnapshot: PetSnapshot?
    private var recentSnapshots: [PetSnapshot] = []
    private var statusExpanded = false
    private var statusUnread = false
    private var trackingArea: NSTrackingArea?
    private var animationTimer: Timer?
    private var stateTimer: Timer?
    private let activateSession: (String) -> Bool
    private let adjustPetScale: (CGFloat) -> Void
    private let setStatusPanelExpanded: (Bool) -> Void
    private let acknowledgeStatus: (PetSnapshot) -> Void

    override var isFlipped: Bool { true }

    init(
        frame: NSRect,
        spriteSheetURL: URL?,
        stateRootURL: URL,
        activateSession: @escaping (String) -> Bool,
        adjustPetScale: @escaping (CGFloat) -> Void,
        setStatusPanelExpanded: @escaping (Bool) -> Void,
        acknowledgeStatus: @escaping (PetSnapshot) -> Void
    ) {
        self.stateRootURL = stateRootURL
        self.spriteSheet = spriteSheetURL.flatMap(NSImage.init(contentsOf:))
        self.activateSession = activateSession
        self.adjustPetScale = adjustPetScale
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
        statusExpanded ? 76 : 26
    }

    private var petRect: NSRect {
        let height = max(0, bounds.height - statusAreaHeight)
        let width = min(bounds.width, height * 240 / 260)
        return NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: height)
    }

    private var statusControlRect: NSRect {
        let height: CGFloat = statusExpanded ? 68 : 20
        let width: CGFloat = statusExpanded ? min(bounds.width - 24, 216) : bounds.width - 16
        return NSRect(
            x: (bounds.width - width) / 2,
            y: petRect.maxY + (statusAreaHeight - height) / 2,
            width: width,
            height: height
        )
    }

    private func hostRowRect(_ index: Int) -> NSRect {
        let badge = statusControlRect
        return NSRect(x: badge.minX + 7, y: badge.minY + 22 + CGFloat(index * 21), width: badge.width - 14, height: 19)
    }

    private func readState() {
        guard let display = PetStore.display(
            from: PetStore.snapshots(root: stateRootURL),
            root: stateRootURL,
            now: Int64(Date().timeIntervalSince1970 * 1_000)
        ) else { return }
        let decoded = display.snapshot
        let terminalIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == decoded.applicationBundleID
        if decoded.unread && terminalIsFrontmost {
            acknowledgeStatus(decoded)
        }
        displayedSnapshot = decoded
        recentSnapshots = PetStore.snapshots(root: stateRootURL)
            .filter { $0.state != "ended" }
            .sorted { $0.receivedAt > $1.receivedAt }

        let nextState = normalizedState(decoded.state == "completed" || decoded.state == "ended" || decoded.state == "stale" ? "idle" : decoded.state)
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

        let message = "Claude: \(hostStatus("claude", compact: true)) · Codex: \(hostStatus("codex", compact: true))"
        let unread = decoded.unread && !terminalIsFrontmost
        if message != statusMessage || unread != statusUnread {
            statusMessage = message
            statusUnread = unread
            needsDisplay = true
        }
    }

    private func snapshotPriority(_ snapshot: PetSnapshot) -> Int {
        let unread = snapshot.unread && !PetStore.isAcknowledged(snapshot, root: stateRootURL)
        switch snapshot.state {
        case "waiting": return 7
        case "failed": return unread ? 6 : 2
        case "completed": return unread ? 5 : 1
        case "running": return 4
        case "stale": return 3
        default: return 0
        }
    }

    private func selectedSnapshot(for source: String) -> PetSnapshot? {
        let snapshots = recentSnapshots.filter { $0.source == source }
        return snapshots.max {
            let left = snapshotPriority($0)
            let right = snapshotPriority($1)
            return left == right ? $0.receivedAt < $1.receivedAt : left < right
        }
    }

    private func hostStatus(_ source: String, compact: Bool) -> String {
        let snapshots = recentSnapshots.filter { $0.source == source }
        guard let selected = selectedSnapshot(for: source) else { return compact ? "—" : "no signal" }
        let acknowledged = PetStore.isAcknowledged(selected, root: stateRootURL)
        let count = snapshots.filter { $0.state == selected.state }.count
        let label: String
        switch selected.state {
        case "running": label = selected.message.contains("waiting for agents") ? (compact ? "agents" : "waiting for agents") : "working"
        case "waiting": label = compact ? "input" : "needs input"
        case "completed": label = acknowledged ? (compact ? "done ✓" : "finished ✓") : (compact ? "done" : "finished")
        case "failed": label = acknowledged ? "failed ✓" : "failed"
        case "stale": label = "unknown"
        default: label = "idle"
        }
        return count > 1 && ["running", "completed"].contains(selected.state) ? "\(label) \(count)" : label
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
        guard statusUnread, let displayedSnapshot else { return }
        statusUnread = false
        acknowledgeStatus(displayedSnapshot)
        needsDisplay = true
    }

    private func activate(_ snapshot: PetSnapshot) {
        if snapshot.unread && !PetStore.isAcknowledged(snapshot, root: stateRootURL) {
            acknowledgeStatus(snapshot)
        }
        guard activateSession(snapshot.applicationBundleID) else {
            statusMessage = "\(snapshot.source == "codex" ? "Codex" : "Claude") is no longer open"
            needsDisplay = true
            return
        }
    }

    private func defaultStatusMessage() -> String {
        switch state {
        case "running":
            return "Work in progress…"
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

    private func statusTint(for snapshot: PetSnapshot?) -> NSColor {
        guard let snapshot else { return .systemGray }
        switch snapshot.state {
        case "running": return NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.42, alpha: 1)
        case "waiting": return .systemOrange
        case "failed": return .systemRed
        case "completed": return NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.08, alpha: 1)
        default: return .systemGray
        }
    }

    private func drawStatusBadge() {
        let badgeRect = statusControlRect
        if statusExpanded {
            drawScoreboard(in: badgeRect)
            return
        }

        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
        let tint = statusTint()
        scoreboardBackground.setFill()
        badgePath.fill()
        scoreboardAccent.setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        let headerY = badgeRect.midY - 3.5
        let dotRect = NSRect(x: badgeRect.minX + 10, y: headerY, width: 7, height: 7)
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
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .paragraphStyle: paragraphStyle,
        ]
        message.draw(in: NSRect(x: dotRect.maxX + 6, y: headerY - 3, width: badgeRect.maxX - dotRect.maxX - 16, height: 14), withAttributes: attributes)
    }

    private func drawScoreboard(in rect: NSRect) {
        let board = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        scoreboardBackground.setFill()
        board.fill()
        scoreboardAccent.setStroke()
        board.lineWidth = 1
        board.stroke()

        let active = recentSnapshots.filter { ["running", "waiting"].contains($0.state) }.count
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .left
        "MATCH CENTER".draw(
            in: NSRect(x: rect.minX + 11, y: rect.minY + 6, width: 110, height: 12),
            withAttributes: [
                .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.08, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold),
                .paragraphStyle: headerStyle,
            ]
        )
        let countStyle = NSMutableParagraphStyle()
        countStyle.alignment = .right
        (active == 0 ? "ALL SEEN" : "\(active) LIVE").draw(
            in: NSRect(x: rect.maxX - 76, y: rect.minY + 6, width: 65, height: 12),
            withAttributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
                .paragraphStyle: countStyle,
            ]
        )

        for (index, source) in ["claude", "codex"].enumerated() {
            let snapshot = selectedSnapshot(for: source)
            let rowRect = hostRowRect(index)
            NSColor.white.withAlphaComponent(index == 0 ? 0.055 : 0.035).setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()

            let dot = NSRect(x: rowRect.minX + 8, y: rowRect.midY - 3, width: 6, height: 6)
            statusTint(for: snapshot).setFill()
            NSBezierPath(ovalIn: dot).fill()

            let name = source == "codex" ? "CODEX" : "CLAUDE"
            name.draw(
                in: NSRect(x: dot.maxX + 7, y: rowRect.minY + 3, width: 66, height: 14),
                withAttributes: [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.94),
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                ]
            )
            let statusStyle = NSMutableParagraphStyle()
            statusStyle.alignment = .right
            statusStyle.lineBreakMode = .byTruncatingTail
            hostStatus(source, compact: false).uppercased().draw(
                in: NSRect(x: rowRect.midX - 1, y: rowRect.minY + 3, width: rowRect.width / 2 - 8, height: 14),
                withAttributes: [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.70),
                    .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium),
                    .paragraphStyle: statusStyle,
                ]
            )
        }
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
            if statusExpanded {
                for (index, source) in ["claude", "codex"].enumerated() where hostRowRect(index).contains(viewLocation) {
                    if let snapshot = selectedSnapshot(for: source) { activate(snapshot) }
                    return
                }
            }
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

    override func scrollWheel(with event: NSEvent) {
        let viewLocation = convert(event.locationInWindow, from: nil)
        guard petRect.contains(viewLocation), event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.0025 : 0.025
        adjustPetScale(max(-0.08, min(0.08, event.scrollingDeltaY * sensitivity)))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        dragStart = nil
        setInteractionState(isHovering ? "jumping" : nil)

        if !didDrag {
            if let displayedSnapshot { activate(displayedSnapshot) }
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
        let sizeMenu = NSMenu()
        for (title, action) in [
            ("Small", #selector(AppDelegate.useSmallSize)),
            ("Medium", #selector(AppDelegate.useMediumSize)),
            ("Large", #selector(AppDelegate.useLargeSize)),
        ] {
            let item = sizeMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = NSApp.delegate as? AppDelegate
        }
        let sizeItem = menu.addItem(withTitle: "Pet size", action: nil, keyEquivalent: "")
        menu.setSubmenu(sizeMenu, for: sizeItem)
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Ronaldinho companion", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        quitItem.target = NSApp.delegate as? AppDelegate
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let companionDirectory = PetStore.rootURL()
    private var panel: NSPanel?
    private var petScale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "petScale")
        return stored == 0 ? 0.60 : CGFloat(stored)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let spriteSheetURL = Bundle.main.url(forResource: "spritesheet", withExtension: "webp")
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
            stateRootURL: companionDirectory,
            activateSession: { [weak self] bundleID in
                self?.activateSession(bundleID: bundleID) ?? false
            },
            adjustPetScale: { [weak self] delta in
                self?.setPetScale((self?.petScale ?? 0.35) + delta)
            },
            setStatusPanelExpanded: { [weak self] expanded in
                self?.setStatusPanelExpanded(expanded)
            },
            acknowledgeStatus: { [weak self] snapshot in
                self?.acknowledgeStatus(snapshot)
            }
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func activateSession(bundleID: String) -> Bool {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }) else { return false }
        return application.activate(options: [])
    }

    private func setStatusPanelExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let targetHeight = panelSize(statusExpanded: expanded).height
        guard panel.frame.height != targetHeight else { return }
        let topEdge = panel.frame.maxY
        var frame = panel.frame
        frame.size.height = targetHeight
        frame.origin.y = topEdge - targetHeight
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) {
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY + 8)
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func acknowledgeStatus(_ snapshot: PetSnapshot) {
        let process = Process()
        process.executableURL = Bundle.main.url(forResource: "RonaldinhoPetState", withExtension: nil)
        process.arguments = ["ack", snapshot.source, snapshot.sessionID, String(snapshot.turn), snapshot.eventID]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func screenForMouse() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    }

    private func panelSize(statusExpanded: Bool) -> NSSize {
        NSSize(width: 240, height: 260 * petScale + (statusExpanded ? 76 : 26))
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

    private func setPetScale(_ scale: CGFloat) {
        guard let panel else { return }
        let scale = min(1.20, max(0.25, scale))
        let expanded = panel.frame.height > 260 * petScale + 26
        UserDefaults.standard.set(Double(scale), forKey: "petScale")
        let topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        var frame = panel.frame
        frame.size = panelSize(statusExpanded: expanded)
        frame.origin = NSPoint(x: topRight.x - frame.width, y: topRight.y - frame.height)
        panel.setFrame(frame, display: true, animate: true)
    }

    @objc func useSmallSize() { setPetScale(0.35) }
    @objc func useMediumSize() { setPetScale(0.80) }
    @objc func useLargeSize() { setPetScale(1.0) }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
