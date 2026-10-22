import AppKit
import Combine
import AVFoundation
import WallpaperCore

public enum LibraryMode { case standalone, management, player }

@MainActor public final class LibraryModel: ObservableObject {
    @Published public private(set) var artworkRevision = 0
    @Published public private(set) var state = AppState()
    @Published public private(set) var displays: [Display] = Display.current
    @Published public private(set) var isBusy = false
    @Published public private(set) var mediaInfo: [String: MediaInfo] = [:]
    @Published public var errorMessage: String?
    @Published public private(set) var importStatus: String?
    @Published public private(set) var applicationEffects = ApplicationEffects()
    private var runningApplications: Set<String> = []
    private var frontmostApplication: String?
    private var playlistClock = PlaylistClock()
    public let engine: WallpaperEngine
    public let storeURL: URL
    public let mode: LibraryMode
    @Published private var externalPlaybackStatus: [String: String] = [:]
    private var intent = PlaybackIntent()
    private var readyProjects: Set<String> = []
    private var generation = 0
    private var pendingOperations = 0
    private var conversions: [Int: Task<WallpaperProject, Error>] = [:]
    private var persistenceBlocked = false
    private var needsPlaybackRefresh = false
    @Published public private(set) var variantStatus: String?
    private var onBattery = false
    private var lowPowerMode = false
    private var terminating = false
    private var pendingReloadBaseline: AppState?
    private var stateFileMonitor = StateFileChangeMonitor()
    public var onPlaybackStatusChange: (() -> Void)?

    public init(storeURL: URL, mode: LibraryMode = .standalone) {
        self.engine = WallpaperEngine(variantStore: PlaybackVariantStore(cacheRoot: storeURL.deletingLastPathComponent().appendingPathComponent("PlaybackVariants", isDirectory: true)))
        self.storeURL = storeURL
        self.mode = mode
        do { state = try StateStore.load(from: storeURL) }
        catch {
            if mode != .standalone { persistenceBlocked = true }
            let backup = storeURL.appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970))")
            do {
                try FileManager.default.copyItem(at: storeURL, to: backup)
                errorMessage = String(format: L("library.status.theSettingsFileCouldNotBeReadA"), String(describing: backup.lastPathComponent))
            } catch {
                persistenceBlocked = true
                errorMessage = String(format: L("library.status.theSettingsFileCouldNotBeReadOr"), String(describing: storeURL.path))
            }
        }
        intent.manuallyPaused = state.manuallyPaused
        engine.onError = { [weak self] message in self?.errorMessage = message }
        engine.onPlaybackChange = { [weak self] in
            self?.objectWillChange.send()
            self?.onPlaybackStatusChange?()
        }
        engine.variantStore.onChange = { [weak self] in
            guard let self else { return }
            self.setVariantStatus(self.engine.variantStore.statusMessage)
            self.onPlaybackStatusChange?()
        }
        engine.variantStore.onReady = { [weak self] in
            guard let self, !self.terminating, self.state.performance.qualityMode == .energySaving else { return }
            self.needsPlaybackRefresh = true
            if !self.isBusy { self.needsPlaybackRefresh = false; self.reconcile() }
        }
        engine.setOcclusionPolicy(state.performance.pauseWhenOccluded)
        engine.setMuted(state.isMuted)
    }
    public func refreshArtwork() { artworkRevision &+= 1 }
    public func restore(revalidate: Bool = true) async {
        guard !terminating else { return }
        refreshArtwork()
        let ticket = beginOperation()
        defer { endOperation() }
        var restored: Set<String> = []
        var info: [String: MediaInfo] = [:]
        // Management validates the whole library. The helper opens only wallpapers
        // assigned to connected screens; playlist choices are validated when selected.
        let needed = Set(displays.compactMap { state.assignment(for: $0.id)?.projectID })
        let restorationProjects = mode == .player ? state.projects.filter { needed.contains($0.id) } : state.projects
        for project in restorationProjects {
            do {
                if !revalidate, readyProjects.contains(project.id), let cached = mediaInfo[project.id] {
                    restored.insert(project.id); info[project.id] = cached; continue
                }
                let fresh = try WallpaperProject.load(folder: URL(fileURLWithPath: project.folderPath))
                guard fresh.videoPath == project.videoPath else { throw WallpaperError.message(L("library.status.theVideoPathHasChangedImportItAgain")) }
                info[project.id] = try await MediaValidator.validate(url: URL(fileURLWithPath: fresh.videoPath))
                guard ticket == generation else { return }
                restored.insert(project.id)
            } catch {
                guard ticket == generation else { return }
                errorMessage = String(format: L("library.status.couldNotRestore"), String(describing: project.title), String(describing: error.localizedDescription))
            }
        }
        guard ticket == generation else { return }
        readyProjects = restored
        mediaInfo = info
        guard mode != .management else { return }
        if applicationEffects.stopped { engine.stop(); return }
        do {
            var playable = state
            playable.projects = state.projects.filter { readyProjects.contains($0.id) }
            let change = try await engine.prepare(state: playable, displays: displays, shouldPlay: intent.shouldPlay)
            defer { engine.discard(change) }
            guard ticket == generation, !applicationEffects.stopped else { return }
            try engine.commit(change, shouldPlay: intent.shouldPlay, isMuted: effectiveMuted)
        } catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult public func importFolder(_ folder: URL, onProgress: ((String) -> Void)? = nil) async -> String? {
        guard !terminating else { return nil }
        let ticket = beginOperation()
        defer { conversions.removeValue(forKey: ticket); if ticket == generation { importStatus = nil }; endOperation() }
        do {
            let conversion = Task { [self] in
                try await VideoConverter.prepare(folder: folder, cacheRoot: storeURL.deletingLastPathComponent().appendingPathComponent("ConvertedVideos")) { [weak self] message in
                    if self?.generation == ticket { self?.importStatus = message; onProgress?(message) }
                }
            }
            conversions[ticket] = conversion
            var project = try await withTaskCancellationHandler { try await conversion.value } onCancel: { conversion.cancel() }
            if let existing = state.projects.first(where: { $0.folderPath == project.folderPath }) {
                project = project.identifyingSourceFolder(existing.sourceFolderPath)
            }
            let info = try await MediaValidator.validate(url: URL(fileURLWithPath: project.videoPath))
            try Task.checkCancellation()
            guard ticket == generation else { return nil }
            var next = state
            if let index = next.projects.firstIndex(where: { $0.id == project.id }) { next.projects[index] = project }
            else { next.projects.append(project) }
            try commit(next)
            refreshArtwork()
            readyProjects.insert(project.id)
            mediaInfo[project.id] = info
            errorMessage = nil
            reconcile()
            return project.id
        } catch is CancellationError {
            return nil
        } catch {
            guard ticket == generation else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }
    public func shutdown() {
        terminating = true
        generation += 1
        for task in conversions.values { task.cancel() }
        engine.freezeForTermination()
    }
    public func resumeManagementAfterFailedExit() {
        guard mode == .management else { return }
        terminating = false
    }
    public func prepareForTermination() -> [ExitWallpaper] {
        shutdown()
        guard mode != .management else { return [] }
        return displays.compactMap { display in
            // An installed session is authoritative even if an apply is still preparing.
            if let session = engine.sessions[display.id] {
                return ExitWallpaper(display:display,videoURL:URL(fileURLWithPath:session.videoPath),time:session.playbackTime,fit:session.fit)
            }
            guard let assignment = state.assignment(for:display.id),
                  let project = state.projects.first(where:{ $0.id == assignment.projectID }),
                  let fresh = try? WallpaperProject.load(folder:URL(fileURLWithPath:project.folderPath)),
                  fresh.videoPath == project.videoPath else { return nil }
            return ExitWallpaper(display:display,videoURL:URL(fileURLWithPath:project.videoPath),time:.zero,fit:assignment.fit)
        }
    }
    public func apply(projectID: String, target: String?, fit: FitMode) async {
        _ = await applyProject(projectID:projectID,target:target,fit:fit,fromPlaylist:false)
    }
    private func applyProject(projectID: String, target: String?, fit: FitMode, fromPlaylist: Bool) async -> Bool {
        guard !terminating else { return false }
        let playlistSettings = state.playlist
        let ticket = beginOperation()
        defer { endOperation() }
        do {
            guard let project = state.projects.first(where: { $0.id == projectID }) else {
                throw WallpaperError.message(L("library.status.thisWallpaperCouldNotBeFoundImportIt"))
            }
            let fresh = try WallpaperProject.load(folder: URL(fileURLWithPath: project.folderPath))
            guard fresh.videoPath == project.videoPath else { throw WallpaperError.message(L("library.status.theVideoPathHasChangedImportTheWallpaper")) }
            let info = try await MediaValidator.validate(url: URL(fileURLWithPath: fresh.videoPath))
            guard ticket == generation else { return false }
            guard !fromPlaylist || (playlistSettings == state.playlist && playlistEligible(ignoringBusy:true)) else { return false }
            var next = state
            let assignment = Assignment(projectID: projectID, fit: fit)
            if let target {
                guard displays.contains(where: { $0.id == target }) else { throw WallpaperError.message(L("library.status.theDisplayDisconnectedSelectADisplayAgain")) }
                next.assignments[target] = assignment
            } else { next.applyToAll(assignment, displays: displays.map(\.id)) }
            if applicationEffects.stopped || mode == .management {
                try commit(next, fromPlaylist: fromPlaylist)
                readyProjects.insert(projectID); mediaInfo[projectID] = info
                if !fromPlaylist { playlistClock.noteManualChoice(projectID,settings:state.playlist,now:Date()) }
                if mode != .management { engine.stop() }; errorMessage = nil
                return true
            }
            var playable = next
            playable.projects = next.projects.filter { readyProjects.contains($0.id) || $0.id == projectID }
            let change = try await engine.prepare(state: playable, displays: displays, shouldPlay: intent.shouldPlay)
            defer { engine.discard(change) }
            guard ticket == generation else { return false }
            guard !applicationEffects.stopped else { return false }
            guard !fromPlaylist || (playlistSettings == state.playlist && playlistEligible(ignoringBusy:true)) else { return false }
            // Preserve edits to collection/settings made while the player was preparing.
            next = state
            if let target { next.assignments[target] = assignment }
            else { next.applyToAll(assignment,displays:displays.map(\.id)) }
            try commit(next, fromPlaylist: fromPlaylist)
            readyProjects.insert(projectID)
            mediaInfo[projectID] = info
            if applicationEffects.stopped { engine.stop() }
            else if state.assignments != next.assignments || state.defaultAssignment != next.defaultAssignment {
                // The prepared change used an older independent display choice. Prepare from the merged state.
                await restore(revalidate: false)
            } else { try engine.commit(change, shouldPlay: intent.shouldPlay, isMuted: effectiveMuted) }
            if !fromPlaylist { playlistClock.noteManualChoice(projectID,settings:state.playlist,now:Date()) }
            errorMessage = nil
            return true
        } catch is CancellationError { }
        catch {
            guard ticket == generation else { return false }
            errorMessage = error.localizedDescription
        }
        return false
    }
    public func remove(projectID: String) {
        generation += 1
        var next = state
        next.remove(projectID: projectID)
        do {
            try commit(next)
            readyProjects.remove(projectID)
            mediaInfo.removeValue(forKey: projectID)
            reconcile()
        } catch { errorMessage = error.localizedDescription }
    }
    public func togglePause() {
        var next = state
        next.manuallyPaused.toggle()
        do {
            try commit(next)
            intent.manuallyPaused = next.manuallyPaused
            applyRuntimePolicy()
        } catch { errorMessage = error.localizedDescription }
    }
    public func setMuted(_ muted: Bool) {
        var next = state
        next.isMuted = muted
        do { try commit(next); applyRuntimePolicy() }
        catch { errorMessage = error.localizedDescription }
    }
    public func setSuspended(_ reason: String, active: Bool) {
        objectWillChange.send()
        if active { intent.suspensions.insert(reason) } else { intent.suspensions.remove(reason) }
        applyRuntimePolicy()
    }
    public func refreshDisplays() {
        guard !terminating else { return }
        generation += 1
        displays = Display.current
        if mode == .player { Task { [weak self] in await self?.restore(revalidate: false) } }
        else { reconcile() }
    }
    public var shouldPlay: Bool { intent.shouldPlay }
    public var isSystemSuspended: Bool { !intent.suspensions.isEmpty }
    public func setPerformance(_ settings: PerformanceSettings) {
        let oldQuality = state.performance.qualityMode
        var next = state
        next.performance = settings
        do {
            try commit(next)
            engine.setOcclusionPolicy(settings.pauseWhenOccluded)
            updatePowerState(onBattery: onBattery, lowPowerMode: lowPowerMode)
            if oldQuality != state.performance.qualityMode { reconcile() }
        } catch { errorMessage = error.localizedDescription }
    }
    public func updatePowerState(onBattery: Bool, lowPowerMode: Bool) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        let reasons = state.performance.pauseReasons(onBattery: onBattery, lowPowerMode: lowPowerMode, occluded: false)
        intent.suspensions.remove("battery")
        intent.suspensions.remove("lowPowerMode")
        if reasons.contains(.battery) { intent.suspensions.insert("battery") }
        if reasons.contains(.lowPowerMode) { intent.suspensions.insert("lowPowerMode") }
        applyRuntimePolicy()
    }
    public func setExternalPlaybackStatus(_ status: [String: String]) {
        guard externalPlaybackStatus != status else { return }
        externalPlaybackStatus = status
    }
    public func playbackStatus(for displayID: String) -> String {
        if mode == .management { return externalPlaybackStatus[displayID] ?? L("library.status.waitingForBackgroundPlayback") }
        if applicationEffects.stopped { return L("library.status.applicationRuleResourcesFreed") }
        if applicationEffects.paused { return L("library.status.applicationRulePaused") }
        if state.manuallyPaused { return L("library.status.manuallyPaused") }
        let reasons = state.performance.pauseReasons(onBattery: onBattery, lowPowerMode: lowPowerMode, occluded: engine.sessions[displayID]?.isOccluded ?? false)
        if reasons.contains(.battery) { return L("library.status.onBatteryPaused") }
        if reasons.contains(.lowPowerMode) { return L("library.status.lowPowerModePaused") }
        if isSystemSuspended { return L("library.status.pausedBySystem") }
        if reasons.contains(.occluded) { return L("library.status.desktopCoveredPaused") }
        return engine.sessions[displayID] == nil ? L("library.status.waitingForPlayback") : (applicationEffects.muted ? L("library.status.playingMutedByRule") : L("library.status.playing"))
    }
    private func reconcile() {
        guard mode != .management else { return }
        guard !terminating else { return }
        guard !applicationEffects.stopped else { engine.stop(); return }
        if isBusy { needsPlaybackRefresh = true; return }
        var playable = state
        playable.isMuted = effectiveMuted
        playable.projects = state.projects.filter { readyProjects.contains($0.id) }
        engine.reconcile(state: playable, displays: displays, shouldPlay: intent.shouldPlay)
    }
    private var effectiveMuted: Bool { state.isMuted || applicationEffects.muted }
    public func setVariantStatus(_ message: String?) {
        if variantStatus != message { variantStatus = message }
    }
    private func applyRuntimePolicy() {
        guard mode != .management else { return }
        guard !terminating else { return }
        if applicationEffects.stopped { engine.stop(); return }
        engine.variantStore.setGenerationAllowed(!onBattery && !lowPowerMode && !isSystemSuspended)
        engine.setSystemSuspended(!intent.suspensions.isDisjoint(with: ["sleep", "displaySleep", "inactiveSession", "lock"]))
        engine.setMuted(effectiveMuted)
        engine.setPlaying(intent.shouldPlay)
    }
    public func displayName(for project:WallpaperProject) -> String { state.organization.displayName(for:project) }
    @discardableResult public func rename(projectID:String,name:String?) -> Bool {
        do {
            guard let project = state.projects.first(where:{ $0.id == projectID }) else { throw WallpaperError.message(L("library.status.thisWallpaperCouldNotBeFound")) }
            let trimmed = name?.trimmingCharacters(in:.whitespacesAndNewlines)
            if let trimmed, trimmed.isEmpty { throw WallpaperError.message(L("library.status.theWallpaperNameCannotBeEmpty")) }
            var next = state
            next.organization.customNames[projectID] = trimmed == project.title ? nil : trimmed
            try commit(next); errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    public func setOrganization(_ organization: LibraryOrganization) {
        var next = state; next.organization = organization
        let ids = Set(state.projects.map(\.id)), groups = Set(organization.groups.map(\.id))
        next.organization.favorites.formIntersection(ids)
        next.organization.customNames = organization.customNames.filter { ids.contains($0.key) }
        next.organization.memberships = organization.memberships.filter { ids.contains($0.key) && groups.contains($0.value) }
        do { try commit(next) } catch { errorMessage = error.localizedDescription }
    }
    public func setPlaylist(_ playlist: PlaylistSettings) {
        do {
            try playlist.validate(availableIDs:Set(state.projects.map(\.id)))
            if let target = playlist.targetDisplayID, playlist.enabled, !displays.contains(where: { $0.id == target }) {
                throw WallpaperError.message(L("library.status.theDisplayDisconnectedSelectADisplayAgain"))
            }
            var next = state; next.playlist = playlist
            try commit(next); playlistClock.reset(); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    public func setApplicationRules(_ rules: [ApplicationRule]) {
        var next = state; next.applicationRules = rules
        do { try commit(next); refreshApplicationEffects() }
        catch { errorMessage = error.localizedDescription }
    }
    public func updateApplications(running: Set<String>, frontmost: String?) {
        runningApplications = running; frontmostApplication = frontmost
        refreshApplicationEffects()
    }
    private func refreshApplicationEffects() {
        let next = ApplicationEffects.evaluate(state.applicationRules,running:runningApplications,frontmost:frontmostApplication)
        guard next != applicationEffects else { return }
        let wasStopped = applicationEffects.stopped
        applicationEffects = next
        if next.paused { intent.suspensions.insert("application") } else { intent.suspensions.remove("application") }
        if wasStopped && !next.stopped { reconcile() }
        applyRuntimePolicy()
    }
    private func playlistEligible(ignoringBusy: Bool = false) -> Bool {
        let targetAvailable = state.playlist.targetDisplayID.map { target in displays.contains { $0.id == target } } ?? !displays.isEmpty
        let allOccluded = state.performance.pauseWhenOccluded && !engine.sessions.isEmpty && engine.sessions.values.allSatisfy(\.isOccluded)
        return (ignoringBusy || !isBusy) && intent.shouldPlay && !applicationEffects.stopped && targetAvailable && !allOccluded
    }
    public func tickPlaylist(now: Date = Date(), calendar: Calendar = .current) async {
        guard mode != .management else { return }
        guard !terminating else { return }
        let settings = state.playlist
        let current = settings.targetDisplayID.map { state.assignment(for:$0) } ?? state.defaultAssignment
        let ids = state.projects.filter { mode == .player || readyProjects.contains($0.id) }.map(\.id)
        let previousClock = playlistClock
        guard let id = playlistClock.next(settings:settings,availableIDs:ids,currentID:current?.projectID,now:now,calendar:calendar,canAdvance:playlistEligible()) else { return }
        let applied = await applyProject(projectID:id,target:settings.targetDisplayID,fit:current?.fit ?? .fill,fromPlaylist:true)
        if !applied && settings == state.playlist && !playlistEligible() {
            // Pausing while the player prepares defers this tick instead of consuming it.
            playlistClock = previousClock
        }
    }
    private func commit(_ next: AppState, fromPlaylist: Bool = false) throws {
        guard !terminating else { throw CancellationError() }
        guard !persistenceBlocked else { throw WallpaperError.message(L("library.status.resolveTheUnreadableSettingsFileBeforeRestartingThe")) }
        if mode == .standalone {
            try StateStore.save(next, to: storeURL); state = next
        } else {
            let merged = try SharedStateStore.saveChanges(base: state, next: next, to: storeURL) { current in
                if fromPlaylist && (current.playlist != self.state.playlist || current.manuallyPaused ||
                    current.applicationRules != self.state.applicationRules || current.performance != self.state.performance) {
                    throw CancellationError()
                }
            }
            if merged != next { pendingReloadBaseline = pendingReloadBaseline ?? next }
            state = merged
        }
        intent.manuallyPaused = state.manuallyPaused
        if mode != .standalone {
            engine.setOcclusionPolicy(state.performance.pauseWhenOccluded)
            updatePowerState(onBattery: onBattery, lowPowerMode: lowPowerMode)
            refreshApplicationEffects()
        }
    }
    public func reloadSharedStateIfChanged() async {
        guard !terminating else { return }
        do {
            guard try stateFileMonitor.consumeChange(at: storeURL) else { return }
            await reloadSharedState()
        } catch { stateFileMonitor.invalidate(); errorMessage = error.localizedDescription }
    }
    public func reloadSharedState() async {
        guard !terminating else { return }
        do {
            _ = try stateFileMonitor.consumeChange(at: storeURL)
            let fresh = try StateStore.load(from: storeURL)
            let old = pendingReloadBaseline ?? state
            pendingReloadBaseline = nil
            guard fresh != old else { return }
            state = fresh
            intent.manuallyPaused = fresh.manuallyPaused
            if old.playlist != fresh.playlist { playlistClock.reset() }
            if old.defaultAssignment != fresh.defaultAssignment || old.assignments != fresh.assignments {
                if let id = fresh.defaultAssignment?.projectID { playlistClock.noteManualChoice(id, settings: fresh.playlist, now: Date()) }
            }
            let changedIDs = Set(fresh.projects.filter { project in !old.projects.contains(project) }.map(\.id))
            readyProjects.subtract(changedIDs)
            mediaInfo = mediaInfo.filter { entry in !changedIDs.contains(entry.key) && fresh.projects.contains { $0.id == entry.key } }
            // Refresh policies first; unchanged sessions keep their current playback time.
            engine.setOcclusionPolicy(fresh.performance.pauseWhenOccluded)
            updatePowerState(onBattery: onBattery, lowPowerMode: lowPowerMode)
            refreshApplicationEffects()
            let assignmentChanged = old.assignments != fresh.assignments || old.defaultAssignment != fresh.defaultAssignment
            if old.projects != fresh.projects || (mode != .management && (assignmentChanged || old.performance.qualityMode != fresh.performance.qualityMode)) {
                await restore(revalidate: false)
            } else { applyRuntimePolicy() }
        } catch { stateFileMonitor.invalidate(); errorMessage = error.localizedDescription }
    }
    private func beginOperation() -> Int {
        generation += 1
        importStatus = nil
        pendingOperations += 1
        isBusy = true
        return generation
    }
    private func endOperation() {
        pendingOperations -= 1
        isBusy = pendingOperations > 0
        if !isBusy, needsPlaybackRefresh, !terminating {
            needsPlaybackRefresh = false
            reconcile()
        }
    }
}
