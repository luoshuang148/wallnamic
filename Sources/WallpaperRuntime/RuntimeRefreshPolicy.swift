import Foundation

public struct RuntimeRefreshPolicy {
    public static let heartbeatInterval: TimeInterval = 5
    public static let timerTolerance: TimeInterval = 1
    private var lastSharedCheck = Date.distantPast
    private var lastPlaylistCheck = Date.distantPast
    public init() {}
    public mutating func sharedStateCheckDue(now: Date) -> Bool {
        guard now.timeIntervalSince(lastSharedCheck) >= 30 else { return false }
        lastSharedCheck = now
        return true
    }
    public mutating func playlistCheckDue(now: Date, enabled: Bool) -> Bool {
        guard enabled else { lastPlaylistCheck = .distantPast; return false }
        guard now.timeIntervalSince(lastPlaylistCheck) >= 15 else { return false }
        lastPlaylistCheck = now
        return true
    }
}

/// Atomic replacements may retain size and modification time; include inode/device.
struct StateFileChangeMonitor {
    private struct Stamp: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modified: Date
    }
    private var stamp: Stamp?
    private var initialized = false
    mutating func consumeChange(at url: URL) throws -> Bool {
        let current: Stamp?
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            current = Stamp(device: (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                            inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                            size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0,
                            modified: attrs[.modificationDate] as? Date ?? .distantPast)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { current = nil }
        let changed = !initialized || current != stamp
        stamp = current; initialized = true
        return changed
    }
    mutating func invalidate() { initialized = false }
}
