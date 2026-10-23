import WallpaperCore
import AppKit
import WallpaperRuntime

@main struct WallFlowPlayerApplication {
    @MainActor static func main() {
        if PlayerLoginStartupCommand.performIfRequested() { return }
        let app = NSApplication.shared
        let delegate = PlayerDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class PlayerDelegate: NSObject, NSApplicationDelegate {
    private var lease: PlayerLease?
    private var host: DesktopPlaybackHost?
    private var terminationStarted = false
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        languageObserver = DistributedNotificationCenter.default().addObserver(
            forName: LanguageStore.languageDidChangeNotification, object: nil, queue: .main
        ) { _ in LanguageStore.shared.reloadFromDefaults() }
        var stateURL = BackgroundPlayerPaths.defaultStateURL
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--wallflow-state"), index + 1 < args.count { stateURL = URL(fileURLWithPath: args[index + 1]) }
        let paths = BackgroundPlayerPaths(stateURL: stateURL)
        do {
            guard let acquired = try PlayerLease.acquire(paths) else { NSApplication.shared.terminate(nil); return }
            lease = acquired
            var parent = Bundle.main.bundleURL
            for _ in 0..<4 { parent.deleteLastPathComponent() }
            let host = DesktopPlaybackHost(paths: paths, parentAppURL: parent,
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development", sessionID: acquired.sessionID)
            self.host = host
            host.onStopRequested = { NSApplication.shared.terminate(nil) }
            Task {
                do { try await host.start() }
                catch {
                    let alert = NSAlert(); alert.messageText = L("menu.backgroundPlayerCouldNotStart"); alert.informativeText = error.localizedDescription
                    alert.runModal()
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = L("menu.backgroundPlayerCouldNotStart"); alert.informativeText = error.localizedDescription
            alert.runModal(); NSApplication.shared.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let host else { return .terminateNow }
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        let wallpapers = host.prepareForTermination()
        let keeper = StaticWallpaperKeeper(directory: host.paths.stateURL.deletingLastPathComponent().appendingPathComponent("ExitWallpapers", isDirectory: true))
        Task { @MainActor in
            while !wallpapers.isEmpty {
                let errors = await keeper.preserve(wallpapers)
                if errors.isEmpty { break }
                let alert = NSAlert()
                alert.messageText = L("menu.couldNotPreserveWallpapersOnSomeDisplays")
                alert.informativeText = errors.joined(separator: "\n")
                alert.addButton(withTitle: L("menu.retry")); alert.addButton(withTitle: L("menu.quitAnyway"))
                sender.activate(ignoringOtherApps: true)
                if alert.runModal() != .alertFirstButtonReturn { break }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let languageObserver { DistributedNotificationCenter.default().removeObserver(languageObserver) }
        languageObserver = nil
        host?.finish()
        lease?.release(); lease = nil
        if let host {
            DistributedNotificationCenter.default().postNotificationName(BackgroundPlayerPaths.stoppedNotification,
                object: host.paths.stateURL.path, userInfo: ["session": host.sessionID.uuidString], deliverImmediately: true)
        }
    }
}
