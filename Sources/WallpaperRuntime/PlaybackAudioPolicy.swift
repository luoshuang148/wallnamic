import AVFoundation

@MainActor enum PlaybackAudioPolicy {
    static func apply(to item: AVPlayerItem, audioEnabled: Bool) {
        for track in item.tracks where track.assetTrack?.mediaType == .audio {
            if track.isEnabled != audioEnabled { track.isEnabled = audioEnabled }
        }
    }
}

/// AVPlayerLooper configures new items as playback advances. Apply policy to the
/// whole live queue, including tracks that finish loading after item insertion.
@MainActor final class LoopingAudioPolicy {
    private weak var player: AVQueuePlayer?
    private var enabled: Bool
    private var currentObservation: NSKeyValueObservation?
    private var itemObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    init(player: AVQueuePlayer, enabled: Bool = false) {
        self.player = player; self.enabled = enabled
        currentObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled; refresh() }
    func refresh() {
        guard let player else { return }
        let items = player.items()
        let live = Set(items.map(ObjectIdentifier.init))
        itemObservations = itemObservations.filter { live.contains($0.key) }
        for item in items {
            let key = ObjectIdentifier(item)
            if itemObservations[key] == nil {
                itemObservations[key] = [
                    item.observe(\.tracks, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    },
                    item.observe(\.status, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    }
                ]
            }
            PlaybackAudioPolicy.apply(to: item, audioEnabled: enabled)
        }
    }
    func stop() { currentObservation = nil; itemObservations.removeAll(); player = nil }
}
