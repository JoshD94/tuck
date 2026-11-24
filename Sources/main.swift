// Tuck: a tiny menu bar hider.
//
// Icons left of the ◀ divider hide when collapsed; ⌘-drag icons across the divider to choose.
//
// How hiding works on macOS 27: the menu bar no longer pushes icons off-screen when an item is
// wider than the screen; it drops the oversized item instead. But it does move icons into its
// overflow (») when an item fills the free space exactly. So on collapse Tuck sizes the divider
// to the gap between the frontmost app's menus (read with Accessibility) and the dot, and
// resizes it whenever the frontmost app, its menus or the screen changes.
import AppKit

let defaults = UserDefaults.standard
let autoHideKey = "autoHide"
let autoHideSeconds: TimeInterval = 10

if defaults.object(forKey: "NSStatusItem Preferred Position tuck.toggle") == nil {
    defaults.set(260.0, forKey: "NSStatusItem Preferred Position tuck.toggle")
}
if defaults.object(forKey: autoHideKey) == nil { defaults.set(true, forKey: autoHideKey) }

final class Tuck: NSObject, NSApplicationDelegate {
    let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var divider: NSStatusItem!
    var collapsed = false
    var hideTimer: Timer?
    var fitGeneration = 0
    var fittedMenusEnd: CGFloat = -1

    func applicationDidFinishLaunching(_ note: Notification) {
        toggle.autosaveName = "tuck.toggle"
        toggle.behavior = []
        if let b = toggle.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        makeDivider()

        // Scriptable: `open -g tuck://toggle` (also tuck://show, tuck://hide).
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))

        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(refit), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refit),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Menus can change without an app switch (e.g. a window opens); re-check now and then.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refit() }

        expand(scheduleHide: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.collapse() }
    }

    func symbol(_ name: String, _ label: String, size: CGFloat? = nil) -> NSImage? {
        var img = NSImage(systemSymbolName: name, accessibilityDescription: label)
        if let size { img = img?.withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) }
        img?.isTemplate = true
        return img
    }

    /// (Re)create the divider directly left of the dot, so no other icon sits between them.
    func makeDivider() {
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        let togglePos = defaults.double(forKey: "NSStatusItem Preferred Position tuck.toggle")
        defaults.set(togglePos + 1, forKey: "NSStatusItem Preferred Position tuck.divider")
        divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = "tuck.divider"
        divider.behavior = []
        divider.button?.appearsDisabled = true
        divider.button?.image = symbol("arrowtriangle.left.fill", "Divider", size: 8)
    }

    var toggleFrame: CGRect? { toggle.button?.window?.frame }
    var dividerFrame: CGRect? { divider.button?.window?.frame }

    // Laid out = divider sits right next to the dot, on its left.
    var dividerPlaced: Bool {
        guard let d = dividerFrame, let t = toggleFrame else { return false }
        return d.maxX <= t.minX + 1 && t.minX - d.maxX < 20
    }

    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        collapsed ? expand(scheduleHide: true) : collapse()
    }

    func collapse(retried: Bool = false) {
        hideTimer?.invalidate()
        guard dividerPlaced else {
            // Something got between the divider and the dot (or the divider was dragged): snap it back.
            if retried { NSSound.beep(); return }
            makeDivider()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.collapse(retried: true) }
            return
        }
        collapsed = true
        divider.button?.image = nil
        toggle.button?.image = symbol("circle.fill", "Show hidden icons", size: 9)
        fit(attempt: 0)
    }

    func expand(scheduleHide: Bool) {
        hideTimer?.invalidate()
        fitGeneration += 1
        fittedMenusEnd = -1
        collapsed = false
        divider.length = NSStatusItem.variableLength
        divider.button?.image = symbol("arrowtriangle.left.fill", "Divider", size: 8)
        toggle.button?.image = symbol("circle", "Hide icons", size: 9)
        if scheduleHide && defaults.bool(forKey: autoHideKey) {
            hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideSeconds, repeats: false) { [weak self] _ in
                self?.collapse()
            }
        }
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let host = URL(string: s)?.host else { return }
        switch host {
        case "toggle": collapsed ? expand(scheduleHide: true) : collapse()
        case "show": expand(scheduleHide: true)
        case "hide": collapse()
        default: break
        }
    }

    @objc func refit() {
        guard collapsed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.fit(attempt: 0) }
    }

    /// Size the divider to fill the free space left of the dot; shrink a little if macOS drops it.
    func fit(attempt: Int) {
        guard collapsed, let t = toggleFrame else { return }
        let menusEnd = frontmostMenusEnd(before: t.minX) ?? (t.minX * 0.45)
        // Window = length + 16 padding, plus an 8pt gap before the dot.
        let target = max(0, (t.minX - 24 - menusEnd - 4 - CGFloat(attempt) * 12).rounded(.down))
        if attempt == 0, menusEnd == fittedMenusEnd, dividerPlaced { return }
        divider.length = target
        fitGeneration += 1
        let gen = fitGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard gen == self.fitGeneration, self.collapsed else { return }
            if self.dividerPlaced { self.fittedMenusEnd = menusEnd }
            else if attempt < 8 { self.fit(attempt: attempt + 1) }
        }
    }

    /// Right edge of the frontmost app's menus (Apple menu … Help), in screen points.
    func frontmostMenusEnd(before limit: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var mb: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &mb) == .success,
              let menuBar = mb else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return nil }
        var end: CGFloat = 0
        for item in items {
            var f: CFTypeRef?
            var r = CGRect.zero
            if AXUIElementCopyAttributeValue(item, "AXFrame" as CFString, &f) == .success, let f {
                AXValueGetValue(f as! AXValue, .cgRect, &r)
            }
            if r.width > 0, r.maxX < limit { end = max(end, r.maxX) }
        }
        return end > 0 ? end : nil
    }

    func showMenu() {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Hide Again After \(Int(autoHideSeconds)) Seconds",
                              action: #selector(toggleAutoHide), keyEquivalent: "")
        auto.state = defaults.bool(forKey: autoHideKey) ? .on : .off
        menu.addItem(auto)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(login)
        if !AXIsProcessTrusted() {
            menu.addItem(NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAX), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "How to Use…", action: #selector(help), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    @objc func toggleAutoHide() { defaults.set(!defaults.bool(forKey: autoHideKey), forKey: autoHideKey) }
    @objc func toggleLogin() { LoginItem.isOn ? LoginItem.off() : LoginItem.on() }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func help() {
        expand(scheduleHide: false)
        let a = NSAlert()
        a.messageText = "How to use Tuck"
        a.informativeText = """
        Click the dot to show or hide icons.

        To choose what hides: hold ⌘ and drag menu bar icons. Anything left of the \
        triangle ( ◀ ) hides; anything right of it stays visible. Keep the triangle just left of the dot.

        Right-click the dot for settings.
        """
        NSApp.activate()
        a.runModal()
    }
}

// Open at login via a per-user LaunchAgent (works without a paid signing identity).
enum LoginItem {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.joshdirga.tuck.plist")
    static var isOn: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func on() {
        let plist: [String: Any] = [
            "Label": "com.joshdirga.tuck",
            "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        (plist as NSDictionary).write(to: url, atomically: true)
    }
    static func off() { try? FileManager.default.removeItem(at: url) }
}

let app = NSApplication.shared
let delegate = Tuck()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
