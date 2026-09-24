import AppKit
import Darwin

enum SwitchIcon {
    static func image(on: Bool, darkMenuBar: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        draw(on: on, darkMenuBar: darkMenuBar, in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = on ? "中转球已开启" : "中转球已关闭"
        return image
    }

    static func savePreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for on in [false, true] {
            for (name, dark, background) in [
                ("light", false, NSColor.white),
                ("dark", true, NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
            ] {
                let canvas = NSImage(size: NSSize(width: 48, height: 48))
                canvas.lockFocus()
                background.setFill()
                NSRect(x: 0, y: 0, width: 48, height: 48).fill()
                image(on: on, darkMenuBar: dark).draw(in: NSRect(x: 16, y: 16, width: 16, height: 16))
                canvas.unlockFocus()
                guard let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: directory.appendingPathComponent("switch-\(on ? "on" : "off")-\(name).png"))
            }
        }
    }

    private static func draw(on: Bool, darkMenuBar: Bool, in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
        ring.lineWidth = 1.25
        let ringColor = darkMenuBar
            ? NSColor(srgbRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            : NSColor(srgbRed: 0.45, green: 0.48, blue: 0.52, alpha: 1)
        ringColor.setStroke()
        ring.stroke()

        let core = NSBezierPath(ovalIn: NSRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8))
        let coreColor = on
            ? NSColor(srgbRed: 0.62, green: 0.48, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.80, blue: 0.83, alpha: 1)
        coreColor.setFill()
        core.fill()
    }
}

@main
enum TransferBallMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            StagingStore.runSelfTest()
            let previews = URL(fileURLWithPath: "/tmp/transfer-ball-previews", isDirectory: true)
            try? BallArtwork.savePreviews(to: previews)
            try? SwitchIcon.savePreviews(to: previews)
            return
        }
        if CommandLine.arguments.contains("--help") {
            print("中转球：菜单栏文件临时中转。打开应用后，点击菜单栏开关使用。")
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.wcy.transferball")
        if running.contains(where: { $0.processIdentifier != getpid() }) {
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, StagingStoreDelegate {
    private let store = StagingStore.live()
    private var shelf: ShelfController!
    private var statusItem: NSStatusItem!
    private var isOn = false
    private var lastCount = 0
    private var showingMenu = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.delegate = self
        shelf = ShelfController(store: store)
        configureStatusItem()
        configureMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.shutdown()
    }

    func stagingStoreDidChange(_ store: StagingStore) {
        let shouldPulse = store.items.count > lastCount && isOn
        lastCount = store.items.count
        shelf.sync(pulse: shouldPulse)
        updateStatusItem()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        updateStatusItem()
    }

    private func configureMainMenu() {
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出中转球", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.modifierFlags.contains(.option) == true {
            quit()
            return
        }
        if !showingMenu, event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        guard !showingMenu else { return }
        if isOn { turnOff() } else { turnOn() }
    }

    @objc private func toggleFromMenu() {
        if isOn { turnOff() } else { turnOn() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        BallStyle.size = CGFloat(sender.tag)
        shelf.applyStyle()
    }

    @objc private func chooseOpacity(_ sender: NSMenuItem) {
        BallStyle.opacity = CGFloat(sender.tag) / 100
        shelf.applyStyle()
    }

    private func styleMenu(title: String, options: [(title: String, value: Int)], current: Int, action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        for option in options {
            let item = NSMenuItem(title: option.title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = option.value
            item.state = option.value == current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func turnOn() {
        guard !isOn else { return }
        isOn = true
        updateStatusItem()
        shelf.show(expanded: false, animated: true)
    }

    private func turnOff() {
        guard isOn else { return }
        isOn = false
        updateStatusItem()
        store.clear()
        shelf.hide()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let darkMenuBar = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        button.image = SwitchIcon.image(on: isOn, darkMenuBar: darkMenuBar)
        button.contentTintColor = nil
        let count = store.items.count
        if isOn {
            button.toolTip = count == 0
                ? "悬浮球已显示。再次点击关闭并清空中转区。右键可退出。"
                : "中转区有 \(count) 个项目。再次点击关闭并清空，不会删除原文件。右键可退出。"
        } else {
            button.toolTip = "点击显示悬浮球。右键可退出。"
        }
        button.setAccessibilityLabel("中转球开关")
        button.setAccessibilityValue(isOn ? "开" : "关")
    }

    private func showMenu() {
        let menu = NSMenu()
        let count = store.items.count
        let info = NSMenuItem(title: count == 0 ? "中转区是空的" : "中转区有 \(count) 个项目", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let hint = NSMenuItem(title: "关闭开关只清空副本，不删除原文件", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(styleMenu(title: "悬浮球大小", options: BallStyle.sizeOptions.map { ($0.title, Int($0.value)) }, current: Int(BallStyle.size), action: #selector(chooseSize(_:))))
        menu.addItem(styleMenu(title: "透明程度", options: BallStyle.opacityOptions, current: Int((BallStyle.opacity * 100).rounded()), action: #selector(chooseOpacity(_:))))
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: isOn ? "关闭并清空" : "打开悬浮球", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出中转球", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        showingMenu = true
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        showingMenu = false
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

}
