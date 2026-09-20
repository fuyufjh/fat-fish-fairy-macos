import AppKit
import SwiftUI

@main struct FatFishApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    let model = FishModel()
    var mainWindow: NSWindow!
    var pet: PetPanel!
    var statusItem: NSStatusItem!
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        setupAppMenu()
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 930, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        mainWindow.title = "小肥鱼 · FatFishFairy"
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model))
        mainWindow.minSize = NSSize(width: 850, height: 670)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()
        pet = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 365), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pet.title = "小肥鱼 · 桌面伙伴"
        pet.isFloatingPanel = true; pet.level = .floating; pet.backgroundColor = .clear
        pet.isOpaque = false; pet.hasShadow = false; pet.hidesOnDeactivate = false
        pet.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        pet.contentView = NSHostingView(rootView: PetView(model: model))
        pet.delegate = self
        restorePetPosition()
        pet.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = AppBrand.menuBarIcon(from: AppBrand.image)
        statusItem.button?.setAccessibilityLabel("小肥鱼")
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.sessionChanged(active: false) } })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.sessionChanged(active: true) } })
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        showWindow()
    }
    func setupAppMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于小肥鱼", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出小肥鱼", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; bar.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; bar.addItem(editItem); NSApp.mainMenu = bar
    }
    @objc func screenLocked() { model.sessionChanged(active: false) }
    @objc func screenUnlocked() { model.sessionChanged(active: true) }
    @objc func displayChanged() { restorePetPosition() }
    func restorePetPosition() {
        let desired = NSPoint(x: model.preferences.petX ?? ((NSScreen.main?.visibleFrame.maxX ?? 1200) - 350), y: model.preferences.petY ?? 35)
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: desired.x + 165, y: desired.y + 100)) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        pet.setFrameOrigin(NSPoint(x: min(max(desired.x, bounds.minX), bounds.maxX - 330), y: min(max(desired.y, bounds.minY), bounds.maxY - 365)))
    }
    func savePetPosition() {
        model.preferences.petX = pet.frame.minX; model.preferences.petY = pet.frame.minY; model.persist()
    }
    func windowDidMove(_ notification: Notification) { if (notification.object as? NSWindow) === pet { savePetPosition() } }
    @objc func showWindow() { if !mainWindow.isVisible { model.reloadLatestMessages() }; mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func togglePet() {
        model.petVisible.toggle()
        if model.petVisible { pet.orderFrontRegardless() } else { pet.orderOut(nil) }
    }
    @objc func toggleObservation() { model.setAutomatic(!model.preferences.automatic) }
    @objc func observe() { model.observe() }
    @objc func selectTheme(_ item: NSMenuItem) { if let id = item.representedObject as? String { model.chooseTheme(id) } }
    @objc func statusClicked() {
        guard let button = statusItem.button else { return }
        let menu = makeMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        for (title, action) in [("聊两句…", #selector(showWindow)), ("看一眼屏幕", #selector(observe)), (model.preferences.automatic ? "暂停自动观察" : "开始自动观察", #selector(toggleObservation)), (model.petVisible ? "隐藏小肥鱼" : "显示小肥鱼", #selector(togglePet))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let themeItem = NSMenuItem(title: "桌面形象", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in model.themes {
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = theme.id
            item.state = theme.id == model.preferences.theme ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu; menu.addItem(themeItem)
        menu.addItem(withTitle: "退出小肥鱼", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.cancel(); savePetPosition(); model.persist() }
}
