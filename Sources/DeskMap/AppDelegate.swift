import AppKit
import SwiftUI
import Combine
import ServiceManagement

#if DEV_BUILD
let projectFolder = "/Users/proninigor/Projects/mac-desktop-map"
#endif

final class FloatingPanel: NSPanel {
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var originAtMouseDown: NSPoint = .zero

    // Клик без перетаскивания — переименовать десктоп; драг за фон двигает окно.
    override func mouseDown(with event: NSEvent) {
        originAtMouseDown = frame.origin
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1, frame.origin == originAtMouseDown {
            onClick?()
            return
        }
        super.mouseUp(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var panelMenuItem: NSMenuItem!
    private var onTopMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var renameMenuItem: NSMenuItem!
    private var compactMenuItem: NSMenuItem!
    private var indexOnlyMenuItem: NSMenuItem!
    private var goToMenu: NSMenu!
    private var alignLeftMenuItem: NSMenuItem!
    private var alignRightMenuItem: NSMenuItem!
    private var desktopsSettingsWindow: NSWindow?
    private var uiSettingsWindow: NSWindow?
    private var lastPanelFrame: NSRect = .zero
    private let monitor = SpaceMonitor()
    private var cancellables = Set<AnyCancellable>()

    private var panelVisible: Bool {
        get { UserDefaults.standard.object(forKey: "ShowFloatingPanel") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ShowFloatingPanel") }
    }

    private var panelOnTop: Bool {
        get { UserDefaults.standard.object(forKey: "PanelOnTop") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PanelOnTop") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        monitor.screenProvider = { [weak self] in self?.panel.screen ?? NSScreen.main }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
        rebuildMenu()

        // @Published эмитит на willSet — обрабатываем на следующем тике main queue,
        // когда значение уже записано.
        monitor.$current.combineLatest(monitor.$names)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        monitor.$editing
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] editing in
                guard let self, editing else { return }
                // Поле ввода в nonactivating-панели: делаем панель ключевой.
                self.setPanelVisible(true)
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
            }
            .store(in: &cancellables)

        L10n.shared.$lang
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        if panelVisible {
            panel.orderFrontRegardless()
        }
        monitor.start()
    }

    // MARK: - Плавающее окошко

    private func setupPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 26),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = panelOnTop ? .floating : .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let host = NSHostingController(rootView: ContentView(monitor: monitor))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)

        if !panel.setFrameUsingName("DeskMapPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: f.maxX - panel.frame.width - 16,
                y: f.maxY - panel.frame.height - 16
            ))
        }
        panel.setFrameAutosaveName("DeskMapPanel")
        panel.delegate = self
        panel.onClick = { [weak self] in self?.monitor.beginEditing() }

        self.panel = panel
        clampPanelToScreen()
        lastPanelFrame = panel.frame
    }

    // MARK: - Окна настроек

    func openDesktopsSettings() {
        if desktopsSettingsWindow == nil {
            let host = NSHostingController(rootView: DesktopsSettingsView(monitor: monitor))
            let window = NSWindow(contentViewController: host)
            window.title = L10n.shared.t(.desktopsSettings).replacingOccurrences(of: "…", with: "")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            desktopsSettingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        desktopsSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openUISettings() {
        if uiSettingsWindow == nil {
            let host = NSHostingController(rootView: UISettingsView(monitor: monitor))
            let window = NSWindow(contentViewController: host)
            window.title = L10n.shared.t(.uiSettings).replacingOccurrences(of: "…", with: "")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            uiSettingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        uiSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        panelMenuItem?.state = visible ? .on : .off
    }

    func setPanelOnTop(_ onTop: Bool) {
        panelOnTop = onTop
        panel.level = onTop ? .floating : .normal
        if panelVisible { panel.orderFrontRegardless() }
        onTopMenuItem?.state = onTop ? .on : .off
    }

    var isPanelOnTop: Bool { panelOnTop }

    @objc private func toggleOnTop() {
        setPanelOnTop(!panelOnTop)
    }

    // Контент меняет размер (имя короче/длиннее) — не даём окну уходить за край экрана.
    private func clampPanelToScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, v.minX + 4), v.maxX - panel.frame.width - 4)
        origin.y = min(max(origin.y, v.minY + 4), v.maxY - panel.frame.height - 4)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Меню в меню-баре

    private func rebuildMenu() {
        let l10n = L10n.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        let goToItem = NSMenuItem(title: l10n.t(.goTo), action: nil, keyEquivalent: "")
        goToMenu = NSMenu()
        goToMenu.autoenablesItems = false
        goToItem.submenu = goToMenu
        menu.addItem(goToItem)

        renameMenuItem = NSMenuItem(title: l10n.t(.renameDesktop), action: #selector(renameDesktop), keyEquivalent: "r")
        renameMenuItem.target = self
        menu.addItem(renameMenuItem)

        menu.addItem(NSMenuItem.separator())

        let desktopsSettingsItem = NSMenuItem(title: l10n.t(.desktopsSettings), action: #selector(openDesktopsSettingsAction), keyEquivalent: ",")
        desktopsSettingsItem.target = self
        menu.addItem(desktopsSettingsItem)

        let uiSettingsItem = NSMenuItem(title: l10n.t(.uiSettings), action: #selector(openUISettingsAction), keyEquivalent: "")
        uiSettingsItem.target = self
        menu.addItem(uiSettingsItem)

        panelMenuItem = NSMenuItem(title: l10n.t(.showWindow), action: #selector(togglePanel), keyEquivalent: "")
        panelMenuItem.target = self
        panelMenuItem.state = panelVisible ? .on : .off
        menu.addItem(panelMenuItem)

        onTopMenuItem = NSMenuItem(title: l10n.t(.alwaysOnTop), action: #selector(toggleOnTop), keyEquivalent: "")
        onTopMenuItem.target = self
        onTopMenuItem.state = panelOnTop ? .on : .off
        menu.addItem(onTopMenuItem)

        compactMenuItem = NSMenuItem(title: l10n.t(.compactWindow), action: #selector(toggleCompact), keyEquivalent: "")
        compactMenuItem.target = self
        compactMenuItem.state = monitor.compact ? .on : .off
        menu.addItem(compactMenuItem)

        indexOnlyMenuItem = NSMenuItem(title: l10n.t(.indexOnly), action: #selector(toggleIndexOnly), keyEquivalent: "")
        indexOnlyMenuItem.target = self
        indexOnlyMenuItem.state = monitor.indexOnly ? .on : .off
        menu.addItem(indexOnlyMenuItem)


        let alignItem = NSMenuItem(title: l10n.t(.alignMenu), action: nil, keyEquivalent: "")
        let alignMenu = NSMenu()
        alignMenu.autoenablesItems = false
        alignLeftMenuItem = NSMenuItem(title: l10n.t(.alignLeft), action: #selector(selectAlignLeft), keyEquivalent: "")
        alignLeftMenuItem.target = self
        alignLeftMenuItem.state = monitor.alignRight ? .off : .on
        alignMenu.addItem(alignLeftMenuItem)
        alignRightMenuItem = NSMenuItem(title: l10n.t(.alignRight), action: #selector(selectAlignRight), keyEquivalent: "")
        alignRightMenuItem.target = self
        alignRightMenuItem.state = monitor.alignRight ? .on : .off
        alignMenu.addItem(alignRightMenuItem)
        alignItem.submenu = alignMenu
        menu.addItem(alignItem)

        loginMenuItem = NSMenuItem(title: l10n.t(.launchAtLogin), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginMenuItem.target = self
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginMenuItem)

        let langItem = NSMenuItem(title: l10n.t(.language), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        langMenu.autoenablesItems = false
        for (code, name) in L10n.languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = l10n.lang == code ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let aboutItem = NSMenuItem(title: l10n.t(.about), action: #selector(showAboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: l10n.t(.quit), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusItem() {
        let number = monitor.current.isFullscreen
            ? "⛶"
            : monitor.current.number.map(String.init) ?? "…"
        statusItem?.button?.title = number
        statusItem?.button?.toolTip = monitor.currentName
        renameMenuItem?.isEnabled = !monitor.current.isFullscreen
    }

    @objc private func renameDesktop() {
        monitor.beginEditing()
    }

    // MARK: - Переход к десктопу

    // Наполняет меню выбора десктопа: «N — Имя», текущий отмечен галкой.
    private func fillGoToMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for desktop in monitor.desktops {
            let name = monitor.names[desktop.uuid]
            let title = name.map { "\(desktop.index) — \($0)" } ?? String(desktop.index)
            let item = NSMenuItem(title: title, action: #selector(goToDesktop(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = desktop.index
            item.state = desktop.index == monitor.current.number ? .on : .off
            menu.addItem(item)
        }
    }

    /// Клик по номеру в окошке — меню выбора десктопа под окошком.
    func showGoToMenu() {
        guard !monitor.editing, let view = panel.contentView else { return }
        monitor.refresh()
        let menu = NSMenu()
        menu.autoenablesItems = false
        fillGoToMenu(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: view)
    }

    @objc private func goToDesktop(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        SpaceSwitcher.switchTo(index: index, monitor: monitor)
    }

    @objc private func togglePanel() { setPanelVisible(!panelVisible) }

    @objc private func toggleCompact() {
        monitor.compact.toggle()
        compactMenuItem?.state = monitor.compact ? .on : .off
    }

    @objc private func toggleIndexOnly() {
        monitor.indexOnly.toggle()
        indexOnlyMenuItem?.state = monitor.indexOnly ? .on : .off
    }


    @objc private func selectAlignLeft() { setAlignRight(false) }

    @objc private func selectAlignRight() { setAlignRight(true) }

    private func setAlignRight(_ value: Bool) {
        monitor.alignRight = value
        alignLeftMenuItem?.state = value ? .off : .on
        alignRightMenuItem?.state = value ? .on : .off
    }

    @objc private func openDesktopsSettingsAction() { openDesktopsSettings() }

    @objc private func openUISettingsAction() { openUISettings() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        L10n.shared.lang = code
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.shared.t(.loginItemError)
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showAboutAction() { showAbout() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - About

    func showAbout() {
        let l10n = L10n.shared
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AppInfo.name
        alert.addButton(withTitle: "OK")
        let versionLine = "\(l10n.t(.version)) \(AppInfo.version)"
        #if DEV_BUILD
        alert.informativeText = l10n.t(.aboutText) + "\n\n" + versionLine + "\n\n"
            + l10n.devSuffix().replacingOccurrences(of: "{path}", with: projectFolder)
        alert.addButton(withTitle: l10n.t(.openProjectFolder))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: projectFolder))
        }
        #else
        alert.informativeText = l10n.t(.aboutText) + "\n\n" + versionLine
        alert.runModal()
        #endif
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
              let panel = self.panel else { return }
        // При правом выравнивании держим правый край на месте: окно растёт/сжимается влево.
        if monitor.alignRight, lastPanelFrame.width > 0, panel.frame.width != lastPanelFrame.width {
            panel.setFrameOrigin(NSPoint(
                x: lastPanelFrame.maxX - panel.frame.width,
                y: panel.frame.origin.y
            ))
        }
        clampPanelToScreen()
        lastPanelFrame = panel.frame
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        lastPanelFrame = panel.frame
        // Окошко могли перетащить на другой дисплей — номер там другой.
        monitor.refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        if monitor.editing { monitor.cancelEditing() }
    }
}

extension AppDelegate: NSMenuDelegate {
    // Состояния могли поменять извне (контекстное меню окошка, Системные настройки).
    func menuWillOpen(_ menu: NSMenu) {
        monitor.refresh()
        if let goToMenu { fillGoToMenu(goToMenu) }
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        onTopMenuItem?.state = panelOnTop ? .on : .off
        panelMenuItem?.state = panelVisible ? .on : .off
        compactMenuItem?.state = monitor.compact ? .on : .off
        indexOnlyMenuItem?.state = monitor.indexOnly ? .on : .off
        alignLeftMenuItem?.state = monitor.alignRight ? .off : .on
        alignRightMenuItem?.state = monitor.alignRight ? .on : .off
    }
}
