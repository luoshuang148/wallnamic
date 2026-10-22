import AppKit
import Combine
import Darwin
import WallpaperCore

public enum PlayerPhase: String, Codable { case starting, ready, stopping, stopped }
public struct PlayerDisplayStatus: Codable {
    public var message: String
    public var projectID: String
    public var seconds: Double
    public var rate: Float
    public var muted: Bool
    public init(message: String, projectID: String, seconds: Double, rate: Float, muted: Bool) {
        self.message = message; self.projectID = projectID; self.seconds = seconds; self.rate = rate; self.muted = muted
    }
}
public struct PlayerStatus: Codable {
    public var protocolVersion = 1
    public var sessionID: UUID
    public var pid: Int32
    public var build: String
    public var parentAppPath: String
    public var phase: PlayerPhase
    public var displays: [String: PlayerDisplayStatus]
    public var error: String?
    public var resourceStatus: String?
    public var updatedAt = Date()
    public init(sessionID: UUID, pid: Int32, build: String, parentAppPath: String, phase: PlayerPhase,
                displays: [String: PlayerDisplayStatus], error: String?, resourceStatus: String? = nil) {
        self.sessionID = sessionID; self.pid = pid; self.build = build; self.parentAppPath = parentAppPath
        self.phase = phase; self.displays = displays; self.error = error; self.resourceStatus = resourceStatus
    }
}
struct PlayerOwnership: Codable { var sessionID: UUID; var pid: Int32 }
private struct PlayerCommand: Codable { var sessionID: UUID }

public struct BackgroundPlayerPaths {
    public let stateURL: URL
    public var directory: URL { stateURL.deletingLastPathComponent().appendingPathComponent("Runtime", isDirectory: true) }
    public static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoWallpaper/state.json")
    }
    public static let statusChangedNotification = Notification.Name("local.zongzihao.WallFlow.statusChanged")
    public static let commandNotification = Notification.Name("local.zongzihao.WallFlow.playerCommand")
    public static let stoppedNotification = Notification.Name("local.zongzihao.WallFlow.playerStopped")
    public static let stoppingNotification = Notification.Name("local.zongzihao.WallFlow.playerStopping")
    public init(stateURL: URL) { self.stateURL = stateURL }
    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(directory.path, 0o700) == 0 else { throw WallpaperError.message(L("error.player.couldNotSecureTheBackgroundPlayerDirectory")) }
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try prepareDirectory()
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        guard chmod(url.path, 0o600) == 0 else { throw WallpaperError.message(L("error.player.couldNotSecureTheBackgroundPlayerState")) }
    }
    public func writeStatus(_ value: PlayerStatus) throws { try write(value, name: "status.json") }
    public func readStatus() throws -> PlayerStatus? {
        let url = directory.appendingPathComponent("status.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PlayerStatus.self, from: Data(contentsOf: url))
    }
    public func requestStop(session: UUID) throws {
        try write(PlayerCommand(sessionID: session), name: "stop.json")
        DistributedNotificationCenter.default().postNotificationName(Self.commandNotification, object: stateURL.path, userInfo: nil, deliverImmediately: true)
    }
    public func stopRequested(session: UUID) throws -> Bool {
        let url = directory.appendingPathComponent("stop.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try JSONDecoder().decode(PlayerCommand.self, from: Data(contentsOf: url)).sessionID == session
    }
    func writeOwnership(_ value: PlayerOwnership) throws { try write(value, name: "owner.json") }
    func readOwnership() throws -> PlayerOwnership? {
        let url = directory.appendingPathComponent("owner.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PlayerOwnership.self, from: Data(contentsOf: url))
    }
    public func hasOwner() throws -> Bool {
        guard let probe = try PlayerLease.acquire(self, recordingOwnership: false) else { return true }
        probe.release()
        return false
    }
}

/// The kernel releases this lease even if a helper crashes. PID files are never the lock.
public final class PlayerLease {
    public let sessionID = UUID()
    private var fd: Int32
    private init(fd: Int32) { self.fd = fd }
    public static func acquire(_ paths: BackgroundPlayerPaths) throws -> PlayerLease? { try acquire(paths, recordingOwnership: true) }
    static func acquire(_ paths: BackgroundPlayerPaths, recordingOwnership: Bool) throws -> PlayerLease? {
        try paths.prepareDirectory()
        let fd = Darwin.open(paths.directory.appendingPathComponent("player.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw WallpaperError.message(L("error.player.couldNotLockTheBackgroundPlayer")) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let saved = errno; Darwin.close(fd)
            if saved == EWOULDBLOCK { return nil }
            throw WallpaperError.message(L("error.player.couldNotLockTheBackgroundPlayer"))
        }
        let lease = PlayerLease(fd: fd)
        if recordingOwnership {
            do { try paths.writeOwnership(PlayerOwnership(sessionID: lease.sessionID, pid: getpid())) }
            catch { lease.release(); throw error }
        }
        return lease
    }
    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN); Darwin.close(fd); fd = -1
    }
    deinit { release() }
}

@MainActor public final class BackgroundPlayerController: ObservableObject {
    @Published public private(set) var status: PlayerStatus?
    @Published public private(set) var isStopping = false
    public let paths: BackgroundPlayerPaths
    private var lastVerifiedStatus: PlayerStatus?
    private let build: String
    private let parentAppPath: String?
    private let timeout: TimeInterval
    private let launch: () async throws -> Void
    private let isProcessRunning: (Int32) -> Bool

    public convenience init(stateURL: URL = BackgroundPlayerPaths.defaultStateURL, appURL: URL = Bundle.main.bundleURL) {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        self.init(paths: BackgroundPlayerPaths(stateURL: stateURL), build: build, parentAppPath: appURL.path, timeout: 30) {
            let helper = appURL.appendingPathComponent("Contents/Library/LoginItems/WallFlowPlayer.app")
            guard FileManager.default.fileExists(atPath: helper.path) else { throw WallpaperError.message(L("error.player.backgroundPlayerNotFoundUseTheCompleteWallFlow")) }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.arguments = ["--wallflow-state", stateURL.path,
                                "-AppleLanguages", "(\(Bundle.main.preferredLocalizations.first ?? "zh-Hans"))"]
            _ = try await NSWorkspace.shared.openApplication(at: helper, configuration: config)
        }
    }
    init(paths: BackgroundPlayerPaths, build: String, parentAppPath: String? = nil, timeout: TimeInterval, isProcessRunning: @escaping (Int32) -> Bool = { kill($0, 0) == 0 }, launch: @escaping () async throws -> Void) {
        self.paths = paths; self.build = build; self.parentAppPath = parentAppPath; self.timeout = timeout; self.launch = launch; self.isProcessRunning = isProcessRunning
    }
    private func activeStatus() throws -> PlayerStatus? {
        guard try paths.hasOwner(), let owner = try paths.readOwnership(), let status = try paths.readStatus(),
              owner.sessionID == status.sessionID, owner.pid == status.pid, status.protocolVersion == 1,
              status.pid > 0, kill(status.pid, 0) == 0, Date().timeIntervalSince(status.updatedAt) < 15,
              status.phase != .stopped else { return nil }
        return status
    }
    private func checkCompatibility(_ value: PlayerStatus) throws {
        guard value.build == build, parentAppPath == nil || value.parentAppPath == parentAppPath else {
            throw WallpaperError.message(L("error.player.aBackgroundPlayerFromAnotherVersionOrLocation"))
        }
    }
    public func refreshStatus() throws {
        status = try activeStatus()
        if let status { try checkCompatibility(status); lastVerifiedStatus = status }
    }
    public func ensureRunning() async throws {
        status = nil
        if !(try paths.hasOwner()) { try await launch() }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            try Task.checkCancellation()
            if let value = try activeStatus() {
                try checkCompatibility(value)
                status = value; lastVerifiedStatus = value
                if value.phase == .ready { return }
                if value.phase == .stopping { throw WallpaperError.message(L("error.player.theBackgroundPlayerIsQuittingOpenTheApp")) }
            }
            try await Task.sleep(for: .milliseconds(50))
        } while Date() < deadline
        throw WallpaperError.message(L("error.player.backgroundPlayerStartupTimedOutOpenWallFlowAgain"))
    }
    public func stopAndWait(expectedSession: UUID? = nil) async throws {
        guard !isStopping else { throw WallpaperError.message(L("error.player.waitingForTheBackgroundPlayerToQuit")) }
        isStopping = true
        defer { isStopping = false }
        let owned = try paths.hasOwner()
        let active = owned ? try activeStatus() : nil
        // A stopped notification arrives before process disappearance; keep the last verified identity.
        guard let current = active ?? (owned ? nil : lastVerifiedStatus) else {
            if !owned && expectedSession == nil { status = nil; return }
            throw WallpaperError.message(L("error.player.theBackgroundPlayerIsStillRunningOrIts"))
        }
        if let expectedSession, current.sessionID != expectedSession {
            throw WallpaperError.message(L("error.player.theBackgroundPlayerRestartedRetryQuittingCompletely"))
        }
        status = current; lastVerifiedStatus = current
        // Complete exit must also be able to stop an older build before an update.
        if owned { try paths.requestStop(session: current.sessionID) }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let ownedNow = try paths.hasOwner()
            if ownedNow, let owner = try paths.readOwnership(), owner.sessionID != current.sessionID {
                throw WallpaperError.message(L("error.player.theBackgroundPlayerRestartedRetryQuittingCompletely"))
            }
            if let other = try paths.readStatus(), other.sessionID != current.sessionID {
                throw WallpaperError.message(L("error.player.theBackgroundPlayerRestartedRetryQuittingCompletely"))
            }
            if !ownedNow && !isProcessRunning(current.pid) { status = nil; return }
            try await Task.sleep(for: .milliseconds(50))
        } while Date() < deadline
        throw WallpaperError.message(L("error.player.theBackgroundPlayerIsStillRunningRespondTo"))
    }
}
