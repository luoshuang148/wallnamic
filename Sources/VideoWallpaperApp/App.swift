import AppKit
import SwiftUI
import Combine
import WallpaperCore
import WallpaperRuntime

@main struct VideoWallpaperApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: LibraryModel!
    private var workshop: WorkshopModel!
    private var player: BackgroundPlayerController!
    private var exit: ManagementExitCoordinator!
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var cancellable: AnyCancellable?
    private var window: NSWindow!
    private var startup = LoginStartupModel()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshPolicy = RuntimeRefreshPolicy()
    private var forceSharedReload = false
    private var refreshAgain = false
    private var startupTask: Task<Void, Never>?
    private var connectedSession: UUID?
    private var lastPlayerError: String?
    private var terminationStarted = false
    private var backgroundLogin = false
    private var managementRestored = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        backgroundLogin = ManagementLaunchPolicy.startsInBackground(NSAppleEventManager.shared().currentAppleEvent)
        let url = BackgroundPlayerPaths.defaultStateURL
        model = LibraryModel(storeURL: url, mode: .management)
        workshop = WorkshopModel(library: model)
        player = BackgroundPlayerController(stateURL: url)
        exit = ManagementExitCoordinator(quiesce: { [weak self] in self?.quiesce() }, stop: { [weak self] expectedSession in
            guard let self else { throw CancellationError() }
            // A complete exit requested during launch must also stop the helper being launched.
            if expectedSession == nil { await self.startupTask?.value }
            else { self.startupTask?.cancel() }
            try await self.player.stopAndWait(expectedSession: expectedSession)
        }, recover: { [weak self] in self?.model.resumeManagementAfterFailedExit() }, terminate: { [weak self] in
            self?.quit()
        })
        setupMainMenu()
        if !backgroundLogin { setupStatusItem() }
        startup.configureDefaultIfNeeded()
        if let error = startup.errorMessage { model.errorMessage = error }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Wallnamic"
        window.minSize = NSSize(width: 900, height: 660)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView(model: model, workshop: workshop, startup: startup, exit: exit))
        window.center()
        setupLifecycle()
        timer = Timer(timeInterval: RuntimeRefreshPolicy.heartbeatInterval, repeats: true) { [weak self] _ in Task { @MainActor in self?.requestRefresh() } }
        timer?.tolerance = RuntimeRefreshPolicy.timerTolerance
        RunLoop.main.add(timer!, forMode: .common)
        if !backgroundLogin { showLibrary() }
        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.player.ensureRunning()
                self.connectedSession = self.player.status?.sessionID
                if self.backgroundLogin { self.quit() }
                else { self.requestRefresh() }
            } catch is CancellationError { }
            catch {
                self.model.errorMessage = error.localizedDescription
                if self.backgroundLogin { self.showLibrary() }
            }
        }
    }
    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(), appMenu = NSMenu()
        let quit = NSMenuItem(title: L("menu.quitWallFlow"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit); appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(title: L("menu.edit"), action: nil, keyEquivalent: ""), edit = NSMenu(title: L("menu.edit"))
        for (title, action, key) in [(L("menu.cut"), "cut:", "x"), (L("menu.copy"), "copy:", "c"), (L("menu.paste"), "paste:", "v"), (L("menu.selectAll"), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit; menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let menu = NSMenu(); menu.delegate = self
        let open = NSMenuItem(title: L("menu.manageWallpapers"), action: #selector(showLibrary), keyEquivalent: ""); open.target = self
        menu.addItem(open); menu.addItem(.separator())
        let pause = NSMenuItem(title: L("menu.pauseAll"), action: #selector(togglePause), keyEquivalent: ""); pause.target = self
        pauseItem = pause; menu.addItem(pause); menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quitWallFlow"), action: #selector(quit), keyEquivalent: ""); quit.target = self
        menu.addItem(quit); item.menu = menu
        cancellable = model.$state.map(\.manuallyPaused).removeDuplicates().sink { [weak self] paused in
            let image = NSImage(systemSymbolName: paused ? "pause.rectangle" : "play.rectangle", accessibilityDescription: "Wallnamic")
            image?.isTemplate = true
            self?.statusItem?.button?.image = image
            self?.statusItem?.button?.toolTip = paused ? L("menu.wallflowPaused") : "Wallnamic"
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem?.title = model.state.manuallyPaused ? L("menu.resumePlayback") : L("menu.pauseAll")
        pauseItem?.isEnabled = !model.state.projects.isEmpty
    }
    @objc private func togglePause() { model.togglePause() }
    private func setupLifecycle() {
        // The management model uses these flags only for its silent preview.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.model.setSuspended("sleep", active: true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.model.setSuspended("sleep", active: false); $0.model.refreshDisplays() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.model.setSuspended("displaySleep", active: true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.model.setSuspended("displaySleep", active: false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.model.setSuspended("inactiveSession", active: true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.model.setSuspended("inactiveSession", active: false) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.model.setSuspended("lock", active: true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.model.setSuspended("lock", active: false) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.model.refreshDisplays() }
        observe(DistributedNotificationCenter.default(), Notification.Name(SharedStateStore.notification), object: model.storeURL.path) { $0.requestRefresh(forceShared: true) }
        observe(DistributedNotificationCenter.default(), BackgroundPlayerPaths.statusChangedNotification, object: model.storeURL.path) { $0.requestRefresh() }
        observePlayerExit(BackgroundPlayerPaths.stoppingNotification) { $0.quiesce() }
        let center = DistributedNotificationCenter.default()
        let stopped = center.addObserver(forName: BackgroundPlayerPaths.stoppedNotification, object: model.storeURL.path, queue: .main) { [weak self] notification in
            let session = (notification.userInfo?["session"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                guard let self, let session else { return }
                await self.exit.playerStopped(session: session, connectedSession: self.connectedSession)
            }
        }
        observers.append((center, stopped))
    }
    private func observePlayerExit(_ name: Notification.Name, action: @escaping @MainActor (AppDelegate) -> Void) {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: name, object: model.storeURL.path, queue: .main) { [weak self] notification in
            let session = notification.userInfo?["session"] as? String
            Task { @MainActor in
                guard let self, let session, session == self.connectedSession?.uuidString else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: String? = nil, action: @escaping @MainActor (AppDelegate) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self, !self.terminationStarted { action(self) } }
        }))
    }
    private func requestRefresh(forceShared: Bool = false) {
        guard !terminationStarted, managementRestored else { return }
        forceSharedReload = forceSharedReload || forceShared
        refreshAgain = true
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            repeat {
                self.refreshAgain = false
                let force = self.forceSharedReload; self.forceSharedReload = false
                if force { await self.model.reloadSharedState() }
                else if self.refreshPolicy.sharedStateCheckDue(now: Date()) { await self.model.reloadSharedStateIfChanged() }
                do {
                    try self.player.refreshStatus()
                    if let status = self.player.status {
                        self.connectedSession = status.sessionID
                        self.model.setExternalPlaybackStatus(status.displays.mapValues(\.message))
                        self.model.setVariantStatus(status.resourceStatus)
                        if let error = status.error, error != self.lastPlayerError { self.model.errorMessage = error }
                        self.lastPlayerError = status.error
                    } else {
                        self.model.setExternalPlaybackStatus([:])
                    }
                } catch { self.model.errorMessage = error.localizedDescription }
            } while self.refreshAgain && !Task.isCancelled && !self.terminationStarted
        }
    }
    private func quiesce() { workshop?.shutdown(); model?.shutdown() }
    @objc private func showLibrary() {
        model.refreshArtwork()
        backgroundLogin = false
        if statusItem == nil { setupStatusItem() }
        if !managementRestored {
            managementRestored = true
            Task { await model.restore() }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }
    @objc private func quit() {
        if let window { ManagementWindowPolicy.allowQuitWithPresentedSheet(in: window) }
        NSApplication.shared.terminate(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationStarted = true
        quiesce()
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); refreshTask?.cancel(); startupTask?.cancel()
        cancellable?.cancel()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        quiesce()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
