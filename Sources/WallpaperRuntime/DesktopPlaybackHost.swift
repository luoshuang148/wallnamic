import AppKit
import AVFoundation
import WallpaperCore

/// Lives exclusively in WallFlowPlayer. The management process never owns this host.
@MainActor public final class DesktopPlaybackHost {
    public let model: LibraryModel
    public let paths: BackgroundPlayerPaths
    public let sessionID: UUID
    public private(set) var phase: PlayerPhase = .starting
    private let parentAppURL: URL
    private let build: String
    private let statusWriter: (PlayerStatus) throws -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerMonitor: PowerMonitor?
    private var applicationMonitor: ApplicationMonitor?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false
    private var refreshPolicy = RuntimeRefreshPolicy()
    private var forceReload = false
    private var stopScheduled = false
    public var onStopRequested: (() -> Void)?

    public init(paths: BackgroundPlayerPaths, parentAppURL: URL, build: String, sessionID: UUID, statusWriter: ((PlayerStatus) throws -> Void)? = nil) {
        self.statusWriter = statusWriter ?? { try paths.writeStatus($0) }
        self.sessionID = sessionID
        self.paths = paths; self.parentAppURL = parentAppURL; self.build = build
        model = LibraryModel(storeURL: paths.stateURL, mode: .player)
    }
    public func start() async throws {
        try publishStatus()
        model.onPlaybackStatusChange = { [weak self] in self?.requestRefresh(force: false) }
        powerMonitor = PowerMonitor { [weak self] battery, lowPower in self?.model.updatePowerState(onBattery: battery, lowPowerMode: lowPower) }
        powerMonitor?.start()
        applicationMonitor = ApplicationMonitor { [weak self] running, frontmost in self?.model.updateApplications(running: running, frontmost: frontmost) }
        applicationMonitor?.start()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.model.setSuspended("sleep", active: true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.powerMonitor?.refresh(); $0.model.setSuspended("sleep", active: false); $0.model.refreshDisplays() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.model.setSuspended("displaySleep", active: true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.model.setSuspended("displaySleep", active: false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.model.setSuspended("inactiveSession", active: true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.model.setSuspended("inactiveSession", active: false) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.model.setSuspended("lock", active: true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.model.setSuspended("lock", active: false) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.model.refreshDisplays() }
        observe(DistributedNotificationCenter.default(), Notification.Name(SharedStateStore.notification), object: paths.stateURL.path) { $0.requestRefresh() }
        observe(DistributedNotificationCenter.default(), BackgroundPlayerPaths.commandNotification, object: paths.stateURL.path) { $0.checkStopRequest() }
        timer = Timer(timeInterval: RuntimeRefreshPolicy.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        timer?.tolerance = RuntimeRefreshPolicy.timerTolerance
        RunLoop.main.add(timer!, forMode: .common)
        await model.restore()
        guard phase == .starting else { return }
        phase = .ready
        try publishStatus()
        checkStopRequest()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: String? = nil, action: @escaping @MainActor (DesktopPlaybackHost) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .starting || self.phase == .ready else { return }
                action(self)
                self.requestRefresh(force: false)
            }
        }))
    }
    private func requestRefresh(force: Bool = true) {
        guard phase == .starting || phase == .ready else { return }
        needsRefresh = true
        forceReload = forceReload || force
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            while self.needsRefresh && !Task.isCancelled {
                self.needsRefresh = false
                let force = self.forceReload
                self.forceReload = false
                if force { await self.model.reloadSharedState() }
                else if self.refreshPolicy.sharedStateCheckDue(now: Date()) { await self.model.reloadSharedStateIfChanged() }
                if self.phase == .ready && self.refreshPolicy.playlistCheckDue(now: Date(), enabled: self.model.state.playlist.enabled) {
                    await self.model.tickPlaylist()
                }
            }
            self.model.engine.updateResidency()
            try? self.publishStatus()
        }
    }
    func heartbeat() {
        guard phase == .starting || phase == .ready else { return }
        checkStopRequest()
        requestRefresh(force: false)
    }
    private func checkStopRequest() {
        guard phase == .starting || phase == .ready else { return }
        do {
            if !stopScheduled, try paths.stopRequested(session: sessionID) {
                stopScheduled = true
                // AppKit's terminateLater nested loop must run outside a main-dispatch
                // callback, otherwise that occupied queue cannot resume the frame-export task.
                RunLoop.main.perform(inModes: [.default]) { [weak self] in self?.onStopRequested?() }
            }
        }
        catch { model.errorMessage = "无法读取退出请求：\(error.localizedDescription)" }
    }
    public func publishStatus() throws {
        var displays: [String: PlayerDisplayStatus] = [:]
        for display in model.displays {
            let session = model.engine.sessions[display.id]
            let seconds = session?.playbackTime.seconds ?? 0
            displays[display.id] = PlayerDisplayStatus(message: model.playbackStatus(for: display.id),
                projectID: session?.projectID ?? "", seconds: seconds.isFinite ? seconds : 0,
                rate: session?.player.rate ?? 0, muted: session?.player.isMuted ?? true)
        }
        try statusWriter(PlayerStatus(sessionID: sessionID, pid: getpid(), build: build,
            parentAppPath: parentAppURL.path, phase: phase, displays: displays, error: model.errorMessage, resourceStatus: model.variantStatus))
        DistributedNotificationCenter.default().postNotificationName(BackgroundPlayerPaths.statusChangedNotification,
            object: paths.stateURL.path, userInfo: nil, deliverImmediately: true)
    }
    public func prepareForTermination() -> [ExitWallpaper] {
        phase = .stopping
        powerMonitor?.stop(); applicationMonitor?.stop()
        refreshTask?.cancel(); needsRefresh = false
        let wallpapers = model.prepareForTermination()
        try? publishStatus()
        DistributedNotificationCenter.default().postNotificationName(BackgroundPlayerPaths.stoppingNotification,
            object: paths.stateURL.path, userInfo: ["session": sessionID.uuidString], deliverImmediately: true)
        return wallpapers
    }
    public func finish() {
        phase = .stopped
        model.onPlaybackStatusChange = nil
        timer?.invalidate(); timer = nil
        powerMonitor?.stop(); applicationMonitor?.stop(); refreshTask?.cancel()
        model.shutdown(); model.engine.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        try? publishStatus()
    }
}
