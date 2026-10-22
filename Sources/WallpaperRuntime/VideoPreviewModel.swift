import AVFoundation
import Combine
import WallpaperCore

/// One silent preview, independent of desktop playback and saved assignments.
@MainActor public final class VideoPreviewModel: ObservableObject {
    @Published private var playback: PreviewPlayback?
    public var player: AVQueuePlayer? { playback?.player }
    @Published public private(set) var aspectRatio: Double?
    @Published public private(set) var errorMessage: String?
    private var project: WallpaperProject?
    private var visible = false
    private var generation = 0
    private var preparation: Task<Void,Never>?
    private var observations: [NSKeyValueObservation] = []

    public init() {}
    public func setProject(_ next:WallpaperProject?) {
        guard project?.id != next?.id || project?.videoPath != next?.videoPath else { return }
        releasePlayback()
        project = next
        errorMessage = nil
        if visible { prepare() }
    }
    public func setVisible(_ next:Bool) {
        guard visible != next else { return }
        visible = next
        if next { prepare() } else { releasePlayback() }
    }
    public func stop() {
        visible = false
        project = nil
        errorMessage = nil
        releasePlayback()
    }
    private func prepare() {
        guard visible, player == nil, preparation == nil, let project else { return }
        errorMessage = nil
        let ticket = generation
        preparation = Task { [weak self] in
            do {
                let fresh = try WallpaperProject.load(folder:URL(fileURLWithPath:project.folderPath))
                guard fresh.videoPath == project.videoPath else { throw WallpaperError.message(L("library.status.theVideoPathHasChangedImportItAgain")) }
                let info = try await MediaValidator.validate(url:URL(fileURLWithPath:fresh.videoPath))
                try Task.checkCancellation()
                guard let self, self.visible, self.generation == ticket else { return }
                guard info.width > 0, info.height > 0 else { throw WallpaperError.message(L("error.preview.theVideoDimensionsAreInvalid")) }
                let asset = try await PlaybackAssetFactory.makeAsset(url: URL(fileURLWithPath: fresh.videoPath), includeAudio: false)
                try Task.checkCancellation()
                guard self.visible, self.generation == ticket else { return }
                let playback = PreviewPlayback(asset: asset)
                let player = playback.player, looper = playback.looper
                self.aspectRatio = Double(info.width)/Double(info.height)
                self.playback = playback
                self.preparation = nil
                self.observations = [
                    player.observe(\.status,options:[.new]) { [weak self, weak player] value,_ in
                        guard value.status == .failed else { return }
                        let message = value.error?.localizedDescription ?? L("error.preview.previewPlaybackFailed")
                        Task { @MainActor in self?.failed(player:player,ticket:ticket,message:message) }
                    },
                    looper.observe(\.status,options:[.new]) { [weak self, weak player] value,_ in
                        guard value.status == .failed else { return }
                        let message = value.error?.localizedDescription ?? L("error.preview.previewLoopingFailed")
                        Task { @MainActor in self?.failed(player:player,ticket:ticket,message:message) }
                    }
                ]
                player.play()
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == ticket else { return }
                self.preparation = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }
    private func failed(player:AVQueuePlayer?,ticket:Int,message:String) {
        guard generation == ticket, let player, self.player === player else { return }
        errorMessage = message
        releasePlayback()
    }
    private func releasePlayback() {
        generation += 1
        preparation?.cancel(); preparation = nil
        observations.removeAll()
        playback?.stop(); playback = nil
        aspectRatio = nil
    }
    deinit { preparation?.cancel() }
}

private final class PreviewPlayback {
    let player: AVQueuePlayer
    let looper: AVPlayerLooper
    init(asset: AVAsset) {
        player = AVQueuePlayer()
        player.isMuted = true; player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player:player,templateItem:AVPlayerItem(asset:asset))
    }
    func stop() { player.pause(); looper.disableLooping(); player.removeAllItems() }
    deinit { stop() }
}
