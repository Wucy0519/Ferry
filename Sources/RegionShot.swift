import AppKit
import Carbon
import ScreenCaptureKit

enum ShotShortcut {
    private static let keyCodeKey = "shotKeyCode"
    private static let modsKey = "shotCarbonMods"
    private static let labelKey = "shotLabel"

    static var keyCode: UInt32 {
        get {
            guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else { return UInt32(kVK_ANSI_R) }
            return UInt32(UserDefaults.standard.integer(forKey: keyCodeKey))
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: keyCodeKey) }
    }

    static var carbonModifiers: UInt32 {
        get {
            guard UserDefaults.standard.object(forKey: modsKey) != nil else { return UInt32(optionKey) }
            return UInt32(UserDefaults.standard.integer(forKey: modsKey))
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: modsKey) }
    }

    static var label: String {
        get { UserDefaults.standard.string(forKey: labelKey) ?? "⌥R" }
        set { UserDefaults.standard.set(newValue, forKey: labelKey) }
    }

    static func store(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbonModifiers(from: event.modifierFlags)
        label = displayString(for: event)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    static func displayString(for event: NSEvent) -> String {
        let flags = event.modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        return text + (key.isEmpty ? "键\(event.keyCode)" : key)
    }
}

final class RegionHotkey {
    var onFire: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func registerCurrent() {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<RegionHotkey>.fromOpaque(userData).takeUnretainedValue().onFire?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        var hotKeyID = EventHotKeyID(signature: OSType(0x46525931), id: 1)
        RegisterEventHotKey(ShotShortcut.keyCode, ShotShortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
}

enum ScreenshotFolder {
    private static let bookmarkKey = "screenshotFolderBookmark"

    static var displayName: String {
        resolvedURL()?.lastPathComponent ?? "未设置"
    }

    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "设为保存位置"
        panel.message = "截屏会一键保存到这个文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        return url
    }

    static func resolvedURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    static func save(_ item: StagedItem) -> String? {
        guard let folder = resolvedURL() else { return nil }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let dest = uniqueDestination(for: item.displayName, in: folder)
        do {
            try FileManager.default.copyItem(at: item.url, to: dest)
            return folder.lastPathComponent
        } catch {
            return nil
        }
    }

    private static func uniqueDestination(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let base = directory.appendingPathComponent(name)
        if !fm.fileExists(atPath: base.path) { return base }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var index = 2
        while index < 10000 {
            let next = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let url = directory.appendingPathComponent(next)
            if !fm.fileExists(atPath: url.path) { return url }
            index += 1
        }
        return directory.appendingPathComponent(UUID().uuidString + "-" + name)
    }
}

final class ShortcutCaptureWindow: NSWindow {
    var onCapture: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    private var finished = false
    private var keyMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "截屏快捷键"
        let label = NSTextField(wrappingLabelWithString: "按下新的组合键。需要包含 ⌘、⌥、⌃ 或 ⇧。按 Esc 取消。")
        label.frame = NSRect(x: 20, y: 28, width: 320, height: 64)
        label.font = .systemFont(ofSize: 13)
        contentView?.addSubview(label)
        isReleasedWhenClosed = false
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow else { return event }
            self.keyDown(with: event)
            return nil
        }
    }

    override func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if !finished { onCancel?() }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        finish(event: nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finish(event: nil)
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else {
            NSSound.beep()
            return
        }
        finish(event: event)
    }

    private func finish(event: NSEvent?) {
        guard !finished else { return }
        finished = true
        if let event {
            onCapture?(event)
        } else {
            onCancel?()
        }
        close()
    }
}

enum RegionCapture {
    static func grab(completion: @escaping (URL?, String?) -> Void) {
        RegionSelector.pick { rect in
            guard let rect else {
                completion(nil, nil)
                return
            }
            capture(rect) { image, error in
                DispatchQueue.main.async {
                    if let image, let url = writePNG(image) {
                        completion(url, nil)
                        return
                    }
                    let nsError = error as NSError?
                    if nsError?.domain == SCStreamErrorDomain && nsError?.code == SCStreamError.userDeclined.rawValue {
                        completion(nil, "请允许中转球v2录制屏幕，然后完全退出并重新打开。")
                    } else {
                        let detail = nsError?.localizedDescription ?? "没有得到图片"
                        completion(nil, "截屏没有放进中转球：\(detail)")
                    }
                }
            }
        }
    }

    private static func capture(_ appKitRect: CGRect, completion: @escaping (CGImage?, Error?) -> Void) {
        guard #available(macOS 14.0, *) else {
            completion(nil, nil)
            return
        }
        let scRect = appKitToCapture(appKitRect)
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.frame.intersects(scRect) }) ?? content.displays.first else {
                    completion(nil, nil)
                    return
                }
                var local = CGRect(
                    x: scRect.minX - display.frame.minX,
                    y: scRect.minY - display.frame.minY,
                    width: scRect.width,
                    height: scRect.height
                ).integral
                local.size.width = max(1, local.width)
                local.size.height = max(1, local.height)
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = local
                let scale = NSScreen.screens.first { $0.frame.intersects(appKitRect) }?.backingScaleFactor ?? 2
                config.width = max(1, Int((local.width * scale).rounded()))
                config.height = max(1, Int((local.height * scale).rounded()))
                config.showsCursor = false
                config.capturesAudio = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                completion(image, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    private static func appKitToCapture(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func writePNG(_ image: CGImage) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH-mm-ss"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("截屏 \(formatter.string(from: Date())).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try data.write(to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

final class RegionSelector: NSObject {
    private var windows: [NSWindow] = []
    private var completion: ((NSRect?) -> Void)?
    private var keyMonitor: Any?
    private static var current: RegionSelector?

    static func pick(_ completion: @escaping (NSRect?) -> Void) {
        let selector = RegionSelector()
        current = selector
        selector.completion = completion
        selector.start()
    }

    private func start() {
        for screen in NSScreen.screens {
            let overlay = SelectionOverlay(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlay.onFinish = { [weak self] rect in
                self?.finish(rect)
            }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = overlay
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.sharingType = .none
            window.orderFrontRegardless()
            windows.append(window)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(nil)
                return nil
            }
            return event
        }
        NSCursor.crosshair.set()
    }

    private func finish(_ rect: NSRect?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        let done = completion
        completion = nil
        Self.current = nil
        done?(rect)
    }
}

final class SelectionOverlay: NSView {
    var onFinish: ((NSRect?) -> Void)?
    private var anchor: NSPoint?
    private var current: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        let selection = anchor.flatMap { start in current.map { rect(from: start, to: $0) } }
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.append(NSBezierPath(rect: selection)) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        shade.fill()
        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let anchor else {
            onFinish?(nil)
            return
        }
        let local = rect(from: anchor, to: convert(event.locationInWindow, from: nil))
        guard local.width >= 4, local.height >= 4, let window else {
            onFinish?(nil)
            return
        }
        onFinish?(window.convertToScreen(local))
    }

    private func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
