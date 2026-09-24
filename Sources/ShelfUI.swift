import AppKit
import QuartzCore

enum BallStyle {
    static let sizeOptions: [(title: String, value: CGFloat)] = [("小", 58), ("中", 76), ("大", 98)]
    static let opacityOptions: [(title: String, value: Int)] = [("较透", 45), ("标准", 72), ("较实", 90)]

    static var size: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "ballSize")
            return stored > 0 ? stored : 76
        }
        set { UserDefaults.standard.set(newValue, forKey: "ballSize") }
    }

    static var opacity: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: "ballOpacity") != nil else { return 0.72 }
            return CGFloat(UserDefaults.standard.double(forKey: "ballOpacity"))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "ballOpacity") }
    }
}

enum Metrics {
    static var ball: CGFloat { BallStyle.size }
    static let shadow: CGFloat = 22
    static let cardWidth: CGFloat = 300
    static let rowHeight: CGFloat = 46
    static let header: CGFloat = 78
    static let footerBase: CGFloat = 12
    static let footerWithAll: CGFloat = 50
    static let maxRows: CGFloat = 5
    static let gap: CGFloat = 10

    static func cardHeight(count: Int) -> CGFloat {
        if count == 0 { return header + 72 }
        let rows = min(CGFloat(count), maxRows) * rowHeight
        let footer = count >= 2 ? footerWithAll : footerBase
        return header + rows + footer
    }
}

enum BallArtwork {
    private static var symbols: [Int: NSImage] = [:]

    static func draw(
        in bounds: NSRect,
        count: Int,
        importing: Bool,
        targeted: Bool,
        pressed: Bool,
        pulse: CGFloat,
        spin: CGFloat
    ) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        if pressed {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            bounds.fill()
        }
        if pulse > 0 {
            NSColor.controlAccentColor.withAlphaComponent(pulse).setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if targeted {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2.5, dy: 2.5))
            ring.lineWidth = 3
            ring.stroke()
        } else {
            NSColor.separatorColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.2, dy: 1.2))
            ring.lineWidth = 1
            ring.stroke()
        }

        if importing {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
                radius: bounds.width * 0.2,
                startAngle: spin,
                endAngle: spin + 280,
                clockwise: false
            )
            NSColor.labelColor.setStroke()
            arc.lineWidth = max(2.5, bounds.width * 0.045)
            arc.lineCapStyle = .round
            arc.stroke()
            return
        }

        if count > 0 {
            drawCount(count, in: bounds)
        } else if let symbol = symbolImage(pointSize: bounds.width * 0.36) {
            let size = symbol.size
            let rect = NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            NSColor.labelColor.setFill()
            NSRect(origin: rect.origin, size: size).fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        }
    }

    static func savePreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samples: [(String, Int, Bool)] = [("empty", 0, false), ("count", 3, false), ("target", 3, true)]
        for sample in samples {
            let image = NSImage(size: NSSize(width: 160, height: 160))
            image.lockFocus()
            NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 160, height: 160).fill()
            draw(in: NSRect(x: 20, y: 20, width: 120, height: 120), count: sample.1, importing: false, targeted: sample.2, pressed: false, pulse: 0, spin: 30)
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appendingPathComponent("ball-\(sample.0).png"))
        }
    }

    private static func drawCount(_ count: Int, in bounds: NSRect) {
        let title = (count > 99 ? "99+" : "\(count)") as NSString
        let fontSize: CGFloat = count > 99 ? bounds.width * 0.26 : bounds.width * 0.34
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bounds.width * 0.13, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let caption = "文件" as NSString
        let numberSize = title.size(withAttributes: numberAttrs)
        let captionSize = caption.size(withAttributes: captionAttrs)
        let total = numberSize.height + captionSize.height - 1
        let bottom = bounds.midY - total / 2
        caption.draw(in: NSRect(x: 0, y: bottom, width: bounds.width, height: captionSize.height), withAttributes: captionAttrs.merging([
            .paragraphStyle: centered
        ]) { $1 })
        title.draw(in: NSRect(x: 0, y: bottom + captionSize.height - 1, width: bounds.width, height: numberSize.height), withAttributes: numberAttrs.merging([
            .paragraphStyle: centered
        ]) { $1 })
    }

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    private static func symbolImage(pointSize: CGFloat) -> NSImage? {
        let key = Int(pointSize.rounded())
        if let cached = symbols[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = true
        symbols[key] = image
        return image
    }
}

final class TransferPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ShelfController: NSObject {
    let store: StagingStore
    let panel: TransferPanel
    private let root: RootDropView
    private let ball: BallView
    private let card: CardView
    private var ballCenter: CGPoint
    private var isExpanded = false
    private var animToken = 0
    private var hideToken = 0
    private var displayedCount = 0
    private var dragOriginCenter = CGPoint.zero
    private var dragOriginMouse = CGPoint.zero
    private var didMove = false
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?

    init(store: StagingStore) {
        self.store = store
        ballCenter = Self.defaultCenter()
        root = RootDropView(frame: .zero)
        ball = BallView(frame: .zero)
        card = CardView(frame: .zero)
        panel = TransferPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        loadCenter()
        root.controller = self
        panel.contentView = root
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "中转球"
        panel.sharingType = .none
        panel.acceptsMouseMovedEvents = true
        root.addSubview(card)
        root.addSubview(ball)
        card.isHidden = true
        wireGestures()
        installOutsideMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        sync(pulse: false)
    }

    deinit {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localOutsideMonitor { NSEvent.removeMonitor(localOutsideMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func applyStyle() {
        ball.applyStyle()
        ballCenter = clamp(ballCenter)
        if panel.isVisible { applyPlacement() }
    }

    func show(expanded: Bool, animated: Bool) {
        hideToken += 1
        isExpanded = expanded
        card.isHidden = !expanded
        card.alphaValue = expanded ? 1 : 1
        applyPlacement()
        panel.orderFrontRegardless()
        if animated {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    func hide() {
        hideToken += 1
        let token = hideToken
        animToken += 1
        isExpanded = false
        card.isHidden = true
        card.alphaValue = 1
        applyPlacement()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard token == self.hideToken else { return }
            self.panel.orderOut(nil)
        })
    }

    func sync(pulse: Bool) {
        let count = store.items.count
        if pulse && count > displayedCount {
            ball.pulse()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        displayedCount = count
        ball.count = count
        ball.isImporting = store.isImporting
        card.update(items: store.items, error: store.lastError) { [weak store] id in
            store?.remove(id: id)
        }
        if panel.isVisible {
            applyPlacement()
            if store.lastError != nil && !isExpanded {
                expand()
            }
        }
    }

    func consume(pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            store.importFileURLs(urls)
            return true
        }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                store.importFileURLs(urls)
                return true
            }
        }
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promises.isEmpty {
            store.receive(promises)
            return true
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            store.importImageData(data)
            return true
        }
        return false
    }

    func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: options) { return true }
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true { return true }
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        if let types = pasteboard.types, types.contains(where: { promiseTypes.contains($0) }) { return true }
        if pasteboard.types?.contains(.png) == true || pasteboard.types?.contains(.tiff) == true { return true }
        return false
    }

    private func installOutsideMonitor() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapseIfClickedOutside()
        }
        localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.collapseIfClickedOutside()
            return event
        }
    }

    private func collapseIfClickedOutside() {
        guard isExpanded, panel.isVisible else { return }
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        collapse()
    }

    private func wireGestures() {
        ball.onMouseDown = { [weak self] in self?.beginMove() }
        ball.onMouseDragged = { [weak self] in self?.continueMove() }
        ball.onMouseUp = { [weak self] in self?.endMove(toggle: true) }
        card.header.onMouseDown = { [weak self] in self?.beginMove() }
        card.header.onMouseDragged = { [weak self] in self?.continueMove() }
        card.header.onMouseUp = { [weak self] in self?.endMove(toggle: false) }
    }

    private func beginMove() {
        dragOriginCenter = ballCenter
        dragOriginMouse = NSEvent.mouseLocation
        didMove = false
    }

    private func continueMove() {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragOriginMouse.x
        let dy = mouse.y - dragOriginMouse.y
        if hypot(dx, dy) > 2.5 { didMove = true }
        guard didMove else { return }
        ballCenter = clamp(CGPoint(x: dragOriginCenter.x + dx, y: dragOriginCenter.y + dy))
        applyPlacement()
    }

    private func endMove(toggle: Bool) {
        if didMove {
            saveCenter()
        } else if toggle {
            toggleExpanded()
        }
    }

    private func toggleExpanded() {
        if isExpanded { collapse() } else { expand() }
    }

    private func expand() {
        guard !isExpanded else { return }
        animToken += 1
        let token = animToken
        isExpanded = true
        card.isHidden = false
        card.alphaValue = 0
        applyPlacement()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            card.animator().alphaValue = 1
        }, completionHandler: {
            guard self.animToken == token else { return }
            self.card.alphaValue = 1
        })
    }

    private func collapse() {
        guard isExpanded else { return }
        animToken += 1
        let token = animToken
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            card.animator().alphaValue = 0
        }, completionHandler: {
            guard self.animToken == token else { return }
            self.isExpanded = false
            self.card.isHidden = true
            self.card.alphaValue = 1
            self.applyPlacement()
        })
    }

    private func applyPlacement() {
        let placement = makePlacement()
        panel.setFrame(placement.window, display: true)
        if ball.frame != placement.ball { ball.frame = placement.ball }
        if card.frame != placement.card { card.frame = placement.card }
        card.isHidden = !isExpanded && card.alphaValue == 0 ? true : card.isHidden
        if !isExpanded { card.isHidden = true }
        root.layoutSubtreeIfNeeded()
    }

    private func makePlacement() -> (window: NSRect, ball: NSRect, card: NSRect) {
        let ballScreen = NSRect(
            x: ballCenter.x - Metrics.ball / 2,
            y: ballCenter.y - Metrics.ball / 2,
            width: Metrics.ball,
            height: Metrics.ball
        )
        var union = ballScreen
        var cardScreen = NSRect.zero
        if isExpanded {
            let screen = (screenContaining(ballCenter) ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let size = NSSize(width: Metrics.cardWidth, height: Metrics.cardHeight(count: store.items.count))
            var cardX = ballCenter.x - size.width / 2
            cardX = min(max(cardX, screen.minX + 8), max(screen.minX + 8, screen.maxX - size.width - 8))
            let above = ballScreen.maxY + Metrics.gap
            let below = ballScreen.minY - Metrics.gap - size.height
            let cardY: CGFloat
            if above + size.height <= screen.maxY - 8 {
                cardY = above
            } else if below >= screen.minY + 8 {
                cardY = below
            } else {
                cardY = min(max(screen.minY + 8, below), screen.maxY - 8 - size.height)
            }
            cardScreen = NSRect(origin: NSPoint(x: cardX, y: cardY), size: size)
            union = ballScreen.union(cardScreen)
        }
        let window = union.insetBy(dx: -Metrics.shadow, dy: -Metrics.shadow)
        func convert(_ rect: NSRect) -> NSRect {
            NSRect(x: rect.minX - window.minX, y: rect.minY - window.minY, width: rect.width, height: rect.height)
        }
        return (window, convert(ballScreen), isExpanded ? convert(cardScreen) : .zero)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        let screen = screenContaining(point) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return point }
        let radius = Metrics.ball / 2
        return CGPoint(
            x: min(max(point.x, frame.minX + radius + 4), frame.maxX - radius - 4),
            y: min(max(point.y, frame.minY + radius + 4), frame.maxY - radius - 4)
        )
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private static func defaultCenter() -> CGPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return CGPoint(x: frame.maxX - 36 - Metrics.ball / 2, y: frame.midY)
    }

    private func loadCenter() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "ballCenterX") != nil else {
            ballCenter = clamp(Self.defaultCenter())
            return
        }
        ballCenter = clamp(CGPoint(x: defaults.double(forKey: "ballCenterX"), y: defaults.double(forKey: "ballCenterY")))
    }

    private func saveCenter() {
        UserDefaults.standard.set(ballCenter.x, forKey: "ballCenterX")
        UserDefaults.standard.set(ballCenter.y, forKey: "ballCenterY")
    }

    @objc private func screensChanged() {
        ballCenter = clamp(ballCenter)
        if panel.isVisible { applyPlacement() }
    }
}

final class RootDropView: NSView {
    weak var controller: ShelfController?
    private var ball: BallView? { subviews.compactMap { $0 as? BallView }.first }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL, .png, .tiff, NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dragOperation(for: sender)
        ball?.isTargeted = operation == .copy
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        ball?.isTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        ball?.isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragOperation(for: sender) == .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ball?.isTargeted = false
        guard dragOperation(for: sender) == .copy else { return false }
        return controller?.consume(pasteboard: sender.draggingPasteboard) ?? false
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource is FileDragView { return [] }
        guard let controller, controller.canAccept(sender.draggingPasteboard) else { return [] }
        return .copy
    }
}

class DragMoveView: NSView {
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        onMouseDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        onMouseUp?()
    }
}

final class BallView: DragMoveView {
    var count = 0 { didSet { if count != oldValue { face.needsDisplay = true; updateAccessibility() } } }
    var isImporting = false { didSet { if isImporting != oldValue { updateSpinner(); updateAccessibility() } } }
    var isTargeted = false { didSet { if isTargeted != oldValue { face.needsDisplay = true } } }
    fileprivate var isPressed = false { didSet { face.needsDisplay = true } }
    fileprivate var pulseAlpha: CGFloat = 0
    fileprivate var spin: CGFloat = 0
    private var spinTimer: Timer?
    private var pulseTimer: Timer?
    private let glass = NSVisualEffectView()
    private let face = BallFaceView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 12
        self.shadow = shadow
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        face.source = self
        addSubview(glass)
        addSubview(face)
        toolTip = "把文件拖进来。点击展开后可拖出。拖动可移动位置。"
        applyStyle()
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        spinTimer?.invalidate()
        pulseTimer?.invalidate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let distance = hypot(local.x - bounds.midX, local.y - bounds.midY)
        return distance <= bounds.width / 2 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        super.mouseUp(with: event)
    }

    override func layout() {
        super.layout()
        let disk = bounds.insetBy(dx: 1, dy: 1)
        glass.frame = disk
        glass.layer?.cornerRadius = disk.width / 2
        glass.layer?.masksToBounds = true
        face.frame = bounds
    }

    func applyStyle() {
        glass.alphaValue = BallStyle.opacity
        face.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {}

    func pulse() {
        pulseAlpha = 0.45
        pulseTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.pulseAlpha -= 0.05
            if self.pulseAlpha <= 0 {
                self.pulseAlpha = 0
                timer.invalidate()
                self.pulseTimer = nil
            }
            self.face.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
        face.needsDisplay = true
    }

    private func updateSpinner() {
        if isImporting {
            guard spinTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.spin = (self.spin + 8).truncatingRemainder(dividingBy: 360)
                self.face.needsDisplay = true
            }
            RunLoop.main.add(timer, forMode: .common)
            spinTimer = timer
        } else {
            spinTimer?.invalidate()
            spinTimer = nil
        }
        face.needsDisplay = true
    }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if isImporting {
            setAccessibilityLabel("正在放入文件")
        } else if count == 0 {
            setAccessibilityLabel("悬浮球，将文件拖到这里")
        } else {
            setAccessibilityLabel("悬浮球，\(count) 个文件，点击后可拖出")
        }
    }
}

final class BallFaceView: NSView {
    weak var source: BallView?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let source else { return }
        BallArtwork.draw(
            in: bounds,
            count: source.count,
            importing: source.isImporting,
            targeted: source.isTargeted,
            pressed: source.isPressed,
            pulse: source.pulseAlpha,
            spin: source.spin
        )
    }
}

final class CardView: NSView {
    let header = DragMoveView()
    private let effect = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "中转区")
    private let countLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "按住文件拖到目标位置。关闭开关只清空副本，不删除原文件。")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "把文件拖到悬浮球上\n再从列表里拖出去")
    private let scroll = NSScrollView()
    private let list = ListDocument()
    private let dragAll = DragAllView()
    private var itemCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = 16
        self.shadow = shadow

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        addSubview(effect)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        header.addSubview(titleLabel)
        header.addSubview(countLabel)
        header.addSubview(subtitle)
        effect.addSubview(header)
        effect.addSubview(emptyLabel)

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        scroll.contentView.drawsBackground = false
        effect.addSubview(scroll)
        effect.addSubview(dragAll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    func update(items: [StagedItem], error: String?, onRemove: @escaping (UUID) -> Void) {
        itemCount = items.count
        countLabel.stringValue = items.isEmpty ? "" : "\(items.count) 项"
        if let error {
            subtitle.stringValue = error
            subtitle.textColor = .systemRed
        } else {
            subtitle.stringValue = "按住文件拖到目标位置。关闭开关只清空副本，不删除原文件。"
            subtitle.textColor = .secondaryLabelColor
        }
        list.reload(items: items, onRemove: onRemove)
        dragAll.files = items
        needsLayout = true
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        header.frame = NSRect(x: 0, y: bounds.height - Metrics.header, width: bounds.width, height: Metrics.header)
        titleLabel.frame = NSRect(x: 14, y: Metrics.header - 30, width: header.bounds.width - 88, height: 18)
        countLabel.frame = NSRect(x: header.bounds.width - 74, y: Metrics.header - 30, width: 58, height: 18)
        subtitle.frame = NSRect(x: 14, y: 10, width: header.bounds.width - 28, height: 36)
        subtitle.preferredMaxLayoutWidth = subtitle.frame.width

        let footer: CGFloat = itemCount >= 2 ? Metrics.footerWithAll : (itemCount == 0 ? 0 : Metrics.footerBase)
        emptyLabel.isHidden = itemCount != 0
        scroll.isHidden = itemCount == 0
        dragAll.isHidden = itemCount < 2
        if itemCount == 0 {
            emptyLabel.frame = NSRect(x: 16, y: 12, width: bounds.width - 32, height: bounds.height - Metrics.header - 16)
        } else {
            scroll.frame = NSRect(x: 6, y: footer, width: bounds.width - 12, height: max(0, bounds.height - Metrics.header - footer))
            let width = scroll.contentView.bounds.width
            if abs(list.frame.width - width) > 0.5 {
                list.frame.size.width = width
            }
            list.layoutSubtreeIfNeeded()
        }
        dragAll.frame = NSRect(x: 12, y: 8, width: bounds.width - 24, height: 34)
    }
}

final class ListDocument: NSView {
    override var isFlipped: Bool { true }

    func reload(items: [StagedItem], onRemove: @escaping (UUID) -> Void) {
        subviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let row = FileRowView(item: item)
            row.onRemove = { onRemove(item.id) }
            addSubview(row)
        }
        let height = max(CGFloat(items.count) * Metrics.rowHeight, 1)
        frame.size.height = height
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for view in subviews {
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: Metrics.rowHeight)
            y += Metrics.rowHeight
        }
    }
}

class FileDragView: NSView, NSDraggingSource {
    private var armed = false
    private var origin = NSPoint.zero

    func fileURLs() -> [URL] { [] }
    func mouseDownHook() {}
    func dragDidEnd() {}

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        armed = false
        mouseDownHook()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !armed, hypot(point.x - origin.x, point.y - origin.y) > 4 else { return }
        let urls = fileURLs()
        guard !urls.isEmpty else { return }
        armed = true
        window?.makeKey()
        let local = convert(event.locationInWindow, from: nil)
        let side: CGFloat = 64
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: side, height: side)
            let frame = NSRect(
                x: local.x - side / 2 + CGFloat(index) * 10,
                y: local.y - side / 2 - CGFloat(index) * 8,
                width: side,
                height: side
            )
            item.setDraggingFrame(frame, contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = urls.count > 1 ? .pile : .none
    }

    override func mouseUp(with event: NSEvent) {
        armed = false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        armed = false
        dragDidEnd()
    }
}

final class FileRowView: FileDragView {
    var onRemove: (() -> Void)?
    private let item: StagedItem
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var hovered = false { didSet { needsDisplay = true; removeButton.alphaValue = hovered ? 1 : 0.55 } }

    init(item: StagedItem) {
        self.item = item
        super.init(frame: .zero)
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 28, height: 28)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.stringValue = item.displayName
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 1
        detailField.stringValue = Self.detail(for: item)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "从中转区移除")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeItem)
        removeButton.toolTip = "从中转区移除"
        removeButton.alphaValue = 0.55
        toolTip = item.displayName
        addSubview(iconView)
        addSubview(nameField)
        addSubview(detailField)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func fileURLs() -> [URL] { [item.url] }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let buttonPoint = removeButton.convert(local, from: self)
        if removeButton.bounds.insetBy(dx: -4, dy: -4).contains(buttonPoint) { return removeButton }
        return self
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 8, y: 9, width: 28, height: 28)
        removeButton.frame = NSRect(x: bounds.width - 30, y: 12, width: 22, height: 22)
        let textWidth = max(0, bounds.width - 46 - 36)
        nameField.frame = NSRect(x: 44, y: 24, width: textWidth, height: 16)
        detailField.frame = NSRect(x: 44, y: 6, width: textWidth, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    @objc private func removeItem() { onRemove?() }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func detail(for item: StagedItem) -> String {
        switch item.kind {
        case .folder: return "文件夹"
        case .package: return "文件包"
        case .file:
            if let count = item.byteCount { return bytes.string(fromByteCount: count) }
            return "文件"
        }
    }
}

final class DragAllView: FileDragView {
    var files: [StagedItem] = [] { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "按住并拖到目标位置"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func fileURLs() -> [URL] { files.map(\.url) }
    override func mouseDownHook() { pressed = true }
    override func dragDidEnd() { pressed = false }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        super.mouseUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor.controlAccentColor.withAlphaComponent(pressed ? 0.24 : 0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()
        let text = "按住拖出全部 \(files.count) 项" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }()
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(in: NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height), withAttributes: attrs)
    }
}
