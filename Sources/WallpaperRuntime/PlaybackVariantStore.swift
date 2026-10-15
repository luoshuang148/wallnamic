import Foundation
import CryptoKit
import WallpaperCore

/// Bounded on-disk variants. A cache miss always returns the original immediately.
@MainActor public final class PlaybackVariantStore {
    public private(set) var statusMessage: String?
    public var onReady: (() -> Void)?
    public var onChange: (() -> Void)?
    private let cacheRoot: URL
    private let byteLimit: Int64
    private let encoder: (URL, URL) async throws -> Void
    private struct Job { let source: URL; let key: String }
    private var mode: PlaybackQualityMode = .original
    private var demand: [String: String] = [:]
    private var queue: [Job] = []
    private var active: (id: UUID, job: Job, task: Task<Void, Never>)?
    private var failed: [String: String] = [:]
    private var pinned: Set<String> = []
    private var generationAllowed = true

    public init(cacheRoot: URL? = nil, byteLimit: Int64 = 1024 * 1024 * 1024,
                encoder: @escaping (URL, URL) async throws -> Void = { try await PlaybackVariantEncoder.encode(source: $0, destination: $1) }) {
        self.cacheRoot = (cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallFlow/PlaybackVariants", isDirectory: true)).resolvingSymlinksInPath().standardizedFileURL
        self.byteLimit = max(0, byteLimit); self.encoder = encoder
    }
    private func key(for source: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        let stamp = "energy-v1-1920-30|\(source.resolvingSymlinksInPath().standardizedFileURL.path)|\(attrs[.size] ?? 0)|\((attrs[.modificationDate] as? Date ?? .distantPast).timeIntervalSinceReferenceDate)|\(attrs[.systemFileNumber] ?? 0)"
        return SHA256.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func url(for key: String) -> URL { cacheRoot.appendingPathComponent(key + ".mp4") }
    private func exists(_ key: String) -> Bool {
        ((try? url(for: key).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }
    public func updateDemand(sourceURLs: [URL], mode: PlaybackQualityMode) {
        var next: [String: String] = [:]
        if mode == .energySaving {
            for source in sourceURLs { if let key = try? key(for: source) { next[source.path] = key } }
        }
        if self.mode != mode || demand != next { failed.removeAll() }
        self.mode = mode; demand = next
        queue.removeAll { demand[$0.source.path] != $0.key }
        if let active, demand[active.job.source.path] != active.job.key { active.task.cancel() }
        refreshStatus(); startNext()
    }
    public func playbackURL(for source: URL, mode: PlaybackQualityMode) async throws -> URL {
        guard mode == .energySaving else { return source }
        let key = try key(for: source)
        if exists(key) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(for: key).path)
            return url(for: key)
        }
        guard self.mode == .energySaving, demand[source.path] == key else { return source }
        if failed[key] == nil, active?.job.key != key, !queue.contains(where: { $0.key == key }) {
            queue.append(Job(source: source, key: key))
        }
        refreshStatus(); startNext()
        return source
    }
    public func setGenerationAllowed(_ allowed: Bool) {
        guard generationAllowed != allowed else { return }
        generationAllowed = allowed
        if !allowed { active?.task.cancel() }
        refreshStatus(); startNext()
    }
    public func cancelGeneration() {
        demand.removeAll(); queue.removeAll(); mode = .original
        active?.task.cancel(); refreshStatus()
    }
    public func pin(playbackURLs: [URL]) { pinned = Set(playbackURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }) }
    public func trimCache() { _ = trim(reserving: 0) }
    private func trim(reserving: Int64) -> Bool {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "mp4" && !$0.lastPathComponent.hasPrefix(".") }
        var records = files.map { file -> (URL, Int64, Date) in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (file, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }
        var total = records.reduce(Int64(0)) { $0 + $1.1 }
        records.sort { $0.2 < $1.2 }
        for (file, bytes, _) in records where total + reserving > byteLimit && !pinned.contains(file.resolvingSymlinksInPath().standardizedFileURL.path) {
            if (try? fm.removeItem(at: file)) != nil { total -= bytes }
        }
        return total + reserving <= byteLimit
    }
    private func startNext() {
        guard generationAllowed, mode == .energySaving, active == nil else { return }
        while let job = queue.first {
            queue.removeFirst()
            guard demand[job.source.path] == job.key, !exists(job.key), failed[job.key] == nil else { continue }
            let id = UUID()
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let staging = self.cacheRoot.appendingPathComponent(".pending-" + id.uuidString + ".mp4")
                defer {
                    try? FileManager.default.removeItem(at: staging)
                    if self.active?.id == id { self.active = nil }
                    self.refreshStatus(); self.startNext()
                }
                do {
                    try Task.checkCancellation()
                    try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
                    try await self.encoder(job.source, staging)
                    try Task.checkCancellation()
                    _ = try await MediaValidator.validate(url: staging)
                    try Task.checkCancellation()
                    guard self.generationAllowed, self.demand[job.source.path] == job.key,
                          try self.key(for: job.source) == job.key else { return }
                    let size = Int64(try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    // Staging files are not cached entries and must not evict themselves.
                    guard size <= self.byteLimit, self.trim(reserving: size) else {
                        throw WallpaperError.message("省电缓存空间不足，继续使用原画质。")
                    }
                    try FileManager.default.moveItem(at: staging, to: self.url(for: job.key))
                    self.onReady?()
                } catch is CancellationError {
                    if self.demand[job.source.path] == job.key, !self.queue.contains(where: { $0.key == job.key }) {
                        self.queue.append(job)
                    }
                } catch {
                    self.failed[job.key] = error.localizedDescription
                }
            }
            active = (id, job, task)
            refreshStatus()
            return
        }
        refreshStatus()
    }
    private func refreshStatus() {
        let message: String?
        if mode == .original || demand.isEmpty { message = nil }
        else if demand.values.allSatisfy({ exists($0) }) { message = "省电视频已就绪" }
        else if let error = demand.values.compactMap({ failed[$0] }).first { message = "部分视频继续使用原画质：" + error }
        else if !generationAllowed { message = "当前继续使用原画质；接通电源后准备省电视频" }
        else { message = "正在准备省电视频，未就绪屏幕继续使用原画质" }
        guard message != statusMessage else { return }
        statusMessage = message; onChange?()
    }
}
