import WallpaperCore
import AppKit
import SwiftUI
import AVFoundation

struct VideoPreviewSurface: NSViewRepresentable {
    @ObservedObject private var language = LanguageStore.shared
    let player: AVQueuePlayer?
    let onVisibility: (Bool) -> Void
    let onReady: (Bool) -> Void
    func makeNSView(context:Context) -> PreviewSurfaceView { PreviewSurfaceView() }
    func updateNSView(_ view:PreviewSurfaceView,context:Context) {
        view.onVisibility = onVisibility
        view.onReady = onReady
        view.setPlayer(player)
        view.setAccessibilityLabel(L("preview.liveWallpaperPreview"))
    }
    static func dismantleNSView(_ view:PreviewSurfaceView,coordinator:()) { view.disconnect() }
}

final class PreviewSurfaceView: NSView {
    private let videoLayer = AVPlayerLayer()
    private var boundPlayer: AVQueuePlayer?
    private var readiness: NSKeyValueObservation?
    private var observers: [(NotificationCenter,NSObjectProtocol)] = []
    private var sleeping = false
    var onVisibility: ((Bool)->Void)?
    var onReady: ((Bool)->Void)?
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.clear.cgColor
        layer = videoLayer
        setAccessibilityLabel(L("preview.liveWallpaperPreview"))
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        videoLayer.frame = bounds
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    func setPlayer(_ player:AVQueuePlayer?) {
        guard boundPlayer !== player else { return }
        readiness?.invalidate(); readiness = nil
        boundPlayer = player
        videoLayer.player = player
        Task { @MainActor [weak self, weak player] in
            guard let self, self.boundPlayer === player else { return }
            self.onReady?(player != nil && self.videoLayer.isReadyForDisplay)
        }
        guard let player else { return }
        readiness = videoLayer.observe(\.isReadyForDisplay,options:[.initial,.new]) { [weak self, weak player] layer,_ in
            Task { @MainActor in
                guard let self, let player, self.boundPlayer === player else { return }
                self.onReady?(self.videoLayer.isReadyForDisplay)
            }
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else { reportVisibility(); return }
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,NSWindow.didBecomeKeyNotification] {
            observe(center,name,object:window) { $0.reportVisibility() }
        }
        observe(center,NSWindow.willCloseNotification,object:window) { $0.onVisibility?(false) }
        observe(center,NSApplication.didHideNotification,object:nil) { $0.reportVisibility() }
        observe(center,NSApplication.didUnhideNotification,object:nil) { $0.reportVisibility() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace,NSWorkspace.willSleepNotification,object:nil) { $0.sleeping = true; $0.reportVisibility() }
        observe(workspace,NSWorkspace.didWakeNotification,object:nil) { $0.sleeping = false; $0.reportVisibility() }
        reportVisibility()
    }
    private func reportVisibility() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let visible = self.window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            self.onVisibility?(visible && !NSApp.isHidden && !self.sleeping)
        }
    }
    private func observe(_ center:NotificationCenter,_ name:Notification.Name,object:Any?,action:@escaping @MainActor (PreviewSurfaceView)->Void) {
        let token = center.addObserver(forName:name,object:object,queue:.main) { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
        }
        observers.append((center,token))
    }
    private func removeObservers() {
        for (center,token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
    func disconnect() {
        removeObservers(); readiness?.invalidate(); readiness = nil
        videoLayer.player = nil; boundPlayer = nil
        onVisibility?(false)
        onVisibility = nil; onReady = nil
    }
    deinit { for (center,token) in observers { center.removeObserver(token) } }
}
