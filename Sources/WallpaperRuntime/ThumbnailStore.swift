import Foundation
import ImageIO

public actor ThumbnailStore {
    public static let shared = ThumbnailStore()
    private struct Key: Hashable {
        let path: String
        let modified: Date
        let size: UInt64
        let inode: UInt64
        let pixels: Int
    }
    private struct Entry { let image: CGImage; let cost: Int; var accessed: UInt64 }
    private struct Work { let id: UUID; let task: Task<CGImage?, Never> }
    private let byteLimit: Int
    private var cache: [Key: Entry] = [:]
    private var inFlight: [Key: Work] = [:]
    private var clock: UInt64 = 0
    public private(set) var cachedByteCount = 0
    private var pressure: DispatchSourceMemoryPressure?

    public init(byteLimit: Int = 24 * 1024 * 1024) {
        self.byteLimit = max(0, byteLimit)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressure = source
        source.setEventHandler { [weak self] in Task { await self?.removeAll() } }
        source.resume()
    }
    deinit { pressure?.cancel() }

    public func image(url: URL, maximumPixelSize: Int) async -> CGImage? {
        guard maximumPixelSize > 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let key = Key(path: url.path, modified: attrs[.modificationDate] as? Date ?? .distantPast,
                      size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0,
                      inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0, pixels: maximumPixelSize)
        clock &+= 1
        if var entry = cache[key] {
            entry.accessed = clock; cache[key] = entry
            return entry.image
        }
        let work: Work
        if let existing = inFlight[key] { work = existing }
        else {
            let task = Task.detached(priority: .utility) { () -> CGImage? in
                guard !Task.isCancelled,
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            }
            work = Work(id: UUID(), task: task); inFlight[key] = work
        }
        let image = await work.task.value
        if inFlight[key]?.id == work.id {
            inFlight.removeValue(forKey: key)
            if let image, !work.task.isCancelled {
                let cost = image.bytesPerRow * image.height
                if cost <= byteLimit {
                    while cachedByteCount + cost > byteLimit,
                          let oldest = cache.min(by: { $0.value.accessed < $1.value.accessed }) {
                        cachedByteCount -= oldest.value.cost; cache.removeValue(forKey: oldest.key)
                    }
                    clock &+= 1
                    cache[key] = Entry(image: image, cost: cost, accessed: clock)
                    cachedByteCount += cost
                }
            }
        }
        return image
    }
    public func removeAll() {
        cache.removeAll(); cachedByteCount = 0
        for work in inFlight.values { work.task.cancel() }
        inFlight.removeAll()
    }
}
