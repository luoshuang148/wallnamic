import AppKit
import AVFoundation
import WallpaperCore

public struct Display: Identifiable {
    public let id: String
    public let name: String
    public let screen: NSScreen
    public init(id: String, name: String, screen: NSScreen) { self.id = id; self.name = name; self.screen = screen }
    @MainActor public static var current: [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let id: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                id = CFUUIDCreateString(nil, uuid) as String
            } else { id = "display-\(displayID)" }
            return Display(id: id, name: screen.localizedName, screen: screen)
        }
    }
}
private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor public final class WallpaperSession {
    public let window: NSWindow
    public let player: AVQueuePlayer
    public private(set) var looper: AVPlayerLooper?
    public let projectID: String
    public let videoPath: String
    public private(set) var fit: FitMode
    public private(set) var mediaReleased = false
    public var playbackTime: CMTime { mediaReleased ? savedTime : player.currentTime() }
    let token = UUID()
    var hiddenSince: Date?
    private(set) var releasedForSystem = false
    private let videoLayer: AVPlayerLayer
    private let stillLayer = CALayer()
    private var audioPolicy: LoopingAudioPolicy?
    private var observations: [NSKeyValueObservation] = []
    private var stopped = false
    private var failure: String?
    private var installed = false
    private var desiredPlaying = false
    private var desiredAudio = false
    private var savedTime = CMTime.zero
    private var residencyGeneration = 0
    private var releaseTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var occlusionObserver: NSObjectProtocol?
    private let onError: (WallpaperSession, String) -> Void
    private let onOcclusionChange: (WallpaperSession) -> Void
    public var isOccluded: Bool { installed && !window.occlusionState.contains(.visible) }

    init(project: WallpaperProject, fit: FitMode, screen: NSScreen, onOcclusionChange: @escaping (WallpaperSession) -> Void, onError: @escaping (WallpaperSession, String) -> Void) {
        self.onError = onError; self.onOcclusionChange = onOcclusionChange
        projectID = project.id; videoPath = project.videoPath; self.fit = fit
        player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        videoLayer = AVPlayerLayer(player: player)
        videoLayer.backgroundColor = NSColor.black.cgColor
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true; window.hidesOnDeactivate = false
        window.isOpaque = true; window.backgroundColor = .black; window.hasShadow = false
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = CALayer()
        for layer in [stillLayer, videoLayer] {
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(layer)
        }
        window.contentView = view
        configureLayers(screen: screen, fit: fit)
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.installed, !self.stopped else { return }
                self.onOcclusionChange(self)
            }
        }
        installLoop()
    }
    private func installLoop() {
        observations.removeAll()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: videoPath)))
        audioPolicy = LoopingAudioPolicy(player: player, enabled: desiredAudio)
        observations.append(player.observe(\.status, options: [.new]) { [weak self] player, _ in
            guard player.status == .failed else { return }
            let text = player.error?.localizedDescription ?? "视频播放失败。"
            Task { @MainActor in self?.handleFailure(text) }
        })
        if let looper {
            observations.append(looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                let text = looper.error?.localizedDescription ?? "视频循环播放失败。"
                Task { @MainActor in self?.handleFailure(text) }
            })
        }
    }
    func handleFailure(_ message: String) {
        guard !stopped else { return }
        failure = message
        if installed { onError(self, message) }
    }
    func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            if stopped { throw CancellationError() }
            if let failure { throw WallpaperError.message(failure) }
            if player.currentItem?.status == .failed {
                throw WallpaperError.message(player.currentItem?.error?.localizedDescription ?? "视频解码失败。")
            }
            if player.status == .failed || looper?.status == .failed { throw WallpaperError.message("视频播放器无法启动。") }
            if player.currentItem?.status == .readyToPlay && videoLayer.isReadyForDisplay { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw WallpaperError.message("播放器准备超时，请重新尝试。")
    }
    func show() { installed = true; window.orderBack(nil) }
    private func configureLayers(screen: NSScreen, fit: FitMode) {
        videoLayer.contentsScale = screen.backingScaleFactor
        stillLayer.contentsScale = screen.backingScaleFactor
        videoLayer.videoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
        stillLayer.contentsGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
    }
    func update(screen: NSScreen, fit: FitMode, playing: Bool) {
        self.fit = fit
        window.setFrame(screen.frame, display: true)
        configureLayers(screen: screen, fit: fit)
        setPlaying(playing)
    }
    func setAudioEnabled(_ enabled: Bool) { desiredAudio = enabled; audioPolicy?.setEnabled(enabled) }
    func setPlaying(_ playing: Bool) {
        desiredPlaying = playing
        guard !stopped, !mediaReleased || restoreTask != nil else { return }
        if playing { player.play() } else { player.pause() }
    }
    func cancelPendingRelease() {
        guard releaseTask != nil else { return }
        residencyGeneration += 1
        releaseTask?.cancel(); releaseTask = nil
    }
    private func unloadMedia() {
        observations.removeAll()
        audioPolicy?.stop(); audioPolicy = nil
        player.isMuted = true; player.pause()
        looper?.disableLooping(); looper = nil
        player.removeAllItems()
        videoLayer.player = nil
        videoLayer.opacity = 0
        mediaReleased = true
    }
    func releaseMedia(preserveFrame: Bool) {
        guard !stopped else { return }
        if !preserveFrame {
            cancelPendingRelease()
            residencyGeneration += 1; restoreTask?.cancel(); restoreTask = nil
            if !mediaReleased { savedTime = player.currentTime() }
            releasedForSystem = true
            window.orderOut(nil)
            unloadMedia()
            stillLayer.contents = nil
            return
        }
        guard !mediaReleased, releaseTask == nil else { return }
        residencyGeneration += 1
        let generation = residencyGeneration
        let time = player.currentTime()
        releaseTask = Task { [weak self] in
            guard let self, !self.stopped, !Task.isCancelled else { return }
            defer { if self.residencyGeneration == generation { self.releaseTask = nil } }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: self.videoPath)))
            generator.appliesPreferredTrackTransform = true
            if let screen = self.window.screen {
                generator.maximumSize = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
            }
            do {
                let image = try await withTaskCancellationHandler {
                    try await generator.image(at: time).image
                } onCancel: { generator.cancelAllCGImageGeneration() }
                guard !Task.isCancelled, !self.stopped, self.residencyGeneration == generation, self.isOccluded else { return }
                self.savedTime = time
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.stillLayer.contents = image
                self.unloadMedia()
                CATransaction.commit()
                self.onOcclusionChange(self)
            } catch { /* Retain the original frozen frame if snapshot preparation fails. */ }
        }
    }
    func restoreMedia() {
        cancelPendingRelease()
        guard mediaReleased, restoreTask == nil, !stopped else { return }
        residencyGeneration += 1
        let generation = residencyGeneration
        restoreTask = Task { [weak self] in
            guard let self, !self.stopped, !Task.isCancelled else { return }
            defer { if self.residencyGeneration == generation { self.restoreTask = nil } }
            self.failure = nil
            self.videoLayer.player = self.player
            self.installLoop()
            if self.desiredPlaying { self.player.play() }
            do {
                try await self.waitUntilReady()
                _ = await self.player.seek(to: self.savedTime, toleranceBefore: .zero, toleranceAfter: .zero)
                try Task.checkCancellation()
                guard !Task.isCancelled, !self.stopped, self.residencyGeneration == generation else { return }
                self.mediaReleased = false; self.releasedForSystem = false
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.videoLayer.opacity = 1; self.stillLayer.contents = nil
                CATransaction.commit()
                if self.installed { self.window.orderBack(nil) }
                self.onOcclusionChange(self)
            } catch is CancellationError { }
            catch { self.handleFailure(error.localizedDescription) }
        }
    }
    func stop() {
        guard !stopped else { return }
        stopped = true; residencyGeneration += 1
        releaseTask?.cancel(); releaseTask = nil; restoreTask?.cancel(); restoreTask = nil
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        unloadMedia(); stillLayer.contents = nil
        window.orderOut(nil); window.close()
    }
}
@MainActor public final class PreparedWallpaperChange {
    fileprivate let ticket: Int
    fileprivate let candidates: [String: WallpaperSession]
    fileprivate let state: AppState
    fileprivate let displays: [Display]
    fileprivate var finished = false
    fileprivate init(ticket: Int, candidates: [String: WallpaperSession], state: AppState, displays: [Display]) {
        self.ticket = ticket; self.candidates = candidates; self.state = state; self.displays = displays
    }
}
@MainActor public final class WallpaperEngine {
    public private(set) var sessions: [String: WallpaperSession] = [:]
    public var onError: ((String) -> Void)?
    public var onPlaybackChange: (() -> Void)?
    private var pending: [UUID: WallpaperSession] = [:]
    private var revision = 0
    private var playbackEnabled = true
    private var pauseWhenOccluded = false
    private var audioMuted = false
    private var audioDisplayOrder: [String] = []
    private var refreshTask: Task<Void, Never>?
    private var terminating = false
    private var systemSuspended = false
    public init() {}

    public func prepare(state: AppState, displays: [Display], shouldPlay: Bool) async throws -> PreparedWallpaperChange {
        guard !terminating else { throw CancellationError() }
        revision += 1
        for session in pending.values { session.stop() }
        pending.removeAll()
        let ticket = revision
        playbackEnabled = shouldPlay
        var candidates: [String: WallpaperSession] = [:]
        do {
            for display in displays {
                guard let assignment = state.assignment(for: display.id),
                      let project = state.projects.first(where: { $0.id == assignment.projectID }) else { continue }
                if let existing = sessions[display.id], existing.projectID == project.id, existing.videoPath == project.videoPath { continue }
                let fresh = try WallpaperProject.load(folder: URL(fileURLWithPath: project.folderPath))
                guard fresh.videoPath == project.videoPath else { throw WallpaperError.message("视频文件已改变，请重新导入。") }
                let session = WallpaperSession(project: fresh.identifyingSourceFolder(project.sourceFolderPath), fit: assignment.fit, screen: display.screen, onOcclusionChange: { [weak self] changed in
                    guard let self, self.sessions[display.id] === changed else { return }
                    self.applyPlayback()
                }) { [weak self] failed, message in
                    guard let self, self.sessions[display.id] === failed else { return }
                    self.sessions.removeValue(forKey: display.id)?.stop()
                    self.applyPlayback()
                    self.onError?(message)
                }
                candidates[display.id] = session
                pending[session.token] = session
                session.update(screen: display.screen, fit: assignment.fit, playing: playbackEnabled)
                try await session.waitUntilReady()
            }
            guard revision == ticket, !Task.isCancelled else { throw CancellationError() }
            return PreparedWallpaperChange(ticket: ticket, candidates: candidates, state: state, displays: displays)
        } catch {
            for session in candidates.values { pending.removeValue(forKey: session.token); session.stop() }
            throw error
        }
    }
    public func commit(_ change: PreparedWallpaperChange, shouldPlay: Bool, isMuted: Bool? = nil) throws {
        guard !change.finished, change.ticket == revision else { discard(change); throw CancellationError() }
        playbackEnabled = shouldPlay
        audioMuted = isMuted ?? change.state.isMuted
        audioDisplayOrder = change.displays.map(\.id)
        let online = Set(change.displays.map(\.id))
        for id in Array(sessions.keys) where !online.contains(id) { sessions.removeValue(forKey: id)?.stop() }
        for display in change.displays {
            guard let assignment = change.state.assignment(for: display.id),
                  change.state.projects.contains(where: { $0.id == assignment.projectID }) else {
                sessions.removeValue(forKey: display.id)?.stop(); continue
            }
            if let new = change.candidates[display.id] {
                let old = sessions.updateValue(new, forKey: display.id)
                pending.removeValue(forKey: new.token)
                new.update(screen: display.screen, fit: assignment.fit, playing: shouldPlay)
                new.show()
                old?.stop()
            } else { sessions[display.id]?.update(screen: display.screen, fit: assignment.fit, playing: shouldPlay) }
        }
        change.finished = true
        applyPlayback()
    }
    public func discard(_ change: PreparedWallpaperChange) {
        guard !change.finished else { return }
        change.finished = true
        for session in change.candidates.values { pending.removeValue(forKey: session.token); session.stop() }
    }
    public func reconcile(state: AppState, displays: [Display], shouldPlay: Bool) {
        guard !terminating else { return }
        refreshTask?.cancel()
        playbackEnabled = shouldPlay
        audioMuted = state.isMuted
        audioDisplayOrder = displays.map(\.id)
        let online = Set(displays.map(\.id))
        for id in Array(sessions.keys) where !online.contains(id) { sessions.removeValue(forKey: id)?.stop() }
        applyPlayback()
        refreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let change = try await self.prepare(state: state, displays: displays, shouldPlay: self.playbackEnabled)
                defer { self.discard(change) }
                try self.commit(change, shouldPlay: self.playbackEnabled, isMuted: self.audioMuted)
            } catch is CancellationError { }
            catch { self.onError?(error.localizedDescription) }
        }
    }
    public func setSystemSuspended(_ suspended: Bool) {
        guard !terminating, systemSuspended != suspended else { return }
        systemSuspended = suspended
        updateResidency()
    }
    public func updateResidency(now: Date = Date()) {
        guard !terminating else { return }
        for session in sessions.values {
            let visible = !session.isOccluded || (session.releasedForSystem && !systemSuspended)
            if visible { session.hiddenSince = nil }
            else if session.hiddenSince == nil { session.hiddenSince = now }
            let decision = PlaybackResidencyPolicy.decision(now: now, hiddenSince: session.hiddenSince,
                occlusionPauseEnabled: pauseWhenOccluded, systemSuspended: systemSuspended,
                manuallyPaused: !playbackEnabled, visible: visible, isResident: !session.mediaReleased)
            switch decision {
            case .release: session.releaseMedia(preserveFrame: !systemSuspended)
            case .restore: session.restoreMedia()
            case .retain: session.cancelPendingRelease()
            }
        }
    }
    public func setPlaying(_ playing: Bool) {
        guard !terminating else { return }
        playbackEnabled = playing
        applyPlayback()
        for session in pending.values { session.setPlaying(playing) }
    }
    public func setOcclusionPolicy(_ enabled: Bool) {
        pauseWhenOccluded = enabled
        applyPlayback()
    }
    public func setMuted(_ muted: Bool) { audioMuted = muted; applyPlayback() }
    private func applyPlayback() {
        guard !terminating else { return }
        let audible = audioMuted || !playbackEnabled ? nil : audioDisplayOrder.first { id in
            guard let session = sessions[id] else { return false }
            return !(pauseWhenOccluded && session.isOccluded)
        }
        for (id, session) in sessions where id != audible { session.player.isMuted = true }
        for (id, session) in sessions { session.setAudioEnabled(id == audible) }
        for session in sessions.values {
            session.setPlaying(playbackEnabled && !(pauseWhenOccluded && session.isOccluded))
        }
        if let audible { sessions[audible]?.player.isMuted = false }
        updateResidency()
        onPlaybackChange?()
    }
    public func stop() {
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        for session in sessions.values { session.stop() }
        for session in pending.values { session.stop() }
        sessions.removeAll()
        pending.removeAll()
    }
    public func freezeForTermination() {
        terminating = true
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        for session in pending.values { session.stop() }
        pending.removeAll()
        for session in sessions.values { session.cancelPendingRelease(); session.player.isMuted = true; session.setPlaying(false) }
    }
}
