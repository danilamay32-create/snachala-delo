import AppKit
import SwiftUI
import Combine
import Shared

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var lastAlert: [String: Date] = [:]

    private var mainWindow: NSWindow?
    static let showNote = Notification.Name("ru.snachaladelo.show")

    func applicationDidFinishLaunching(_ note: Notification) {
        // Второй экземпляр не нужен: просим первый показать окно и выходим.
        let me = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: me).count > 1 {
            DistributedNotificationCenter.default().postNotificationName(
                AppDelegate.showNote, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showRequested), name: AppDelegate.showNote, object: nil)

        NSApp.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: model,
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) }
        ))

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &bag)
        updateStatusItem()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        // Для скриншотов в CI.
        let args = CommandLine.arguments
        if args.contains("--open-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.togglePopover() }
        } else if args.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.openSettings() }
        } else if !args.contains("--background") {
            // Запустили руками (Программы, Launchpad, Spotlight) — показать окно,
            // даже если значок в строке меню спрятался за «чёлкой».
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openMainWindow() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    @objc private func showRequested() {
        openMainWindow()
    }

    func openMainWindow() {
        popover.performClose(nil)
        if mainWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PopoverView(
                model: model,
                openSettings: { [weak self] in self?.openSettings() },
                quit: { NSApp.terminate(nil) }
            )))
            w.title = "Сначала дело"
            w.backgroundColor = NSColor(Theme.surface)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            mainWindow = w
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let (symbol, color): (String, NSColor?) = {
            switch model.status {
            case .locked: return ("lock.fill", Theme.lockNS)
            case .pass: return ("cup.and.saucer.fill", Theme.warnNS)
            case .free: return ("checkmark.circle.fill", Theme.freeNS)
            case .offline: return ("exclamationmark.triangle", nil)
            }
        }()
        var img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Сначала дело")
        if let c = color {
            img = img?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [c]))
            img?.isTemplate = false
        } else {
            img?.isTemplate = true
        }
        button.image = img
        if model.status == .pass, let p = model.snapshot?.passUntil {
            button.title = " " + Fmt.countdown(p, now: model.now)
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Сначала дело — настройки"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Blocked app launched

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier,
              let s = model.snapshot, s.locked,
              let blocked = s.apps.first(where: { $0.bundleID == id }) else { return }
        // Служба закроет его сама, но отсюда быстрее.
        app.forceTerminate()
        if let last = lastAlert[id], Date().timeIntervalSince(last) < 15 { return }
        lastAlert[id] = Date()
        let t = s.lockingTasks.first
        let alert = NSAlert()
        alert.messageText = "\(blocked.name) сейчас не откроется"
        if let t = t {
            alert.informativeText = "Сначала дело: «\(t.title)», \(Fmt.deadline(t.deadline, now: s.now)).\nЗакрой задачу, и всё снова заработает."
        } else {
            alert.informativeText = "Сначала закрой срочные задачи."
        }
        alert.addButton(withTitle: "Открыть задачи")
        alert.addButton(withTitle: "Ладно")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openMainWindow() }
    }

    // MARK: Menu (нужно, чтобы работали ⌘C / ⌘V в полях ввода)

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Скрыть значок", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
