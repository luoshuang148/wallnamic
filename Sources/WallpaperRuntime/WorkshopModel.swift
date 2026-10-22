import Foundation
import AppKit
import Combine
import WallpaperCore

public enum WorkshopImportResult: Equatable { case imported, existing }
private struct WorkshopPreferences: Codable { var account: String; var toolPath: String? }

@MainActor public final class WorkshopModel: ObservableObject {
    public typealias ItemLoader = ([WorkshopID]) async throws -> [WorkshopItem]
    @Published public var input = ""
    @Published public var account = ""
    @Published public private(set) var tool: URL?
    @Published public private(set) var accounts: [String] = []
    @Published public private(set) var candidates: [WorkshopItem] = []
    @Published public var selected: Set<WorkshopID> = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var status = L("workshop.status.ready")
    @Published public private(set) var completed = 0
    @Published public private(set) var total = 0
    @Published public private(set) var failures: [String] = []
    @Published public var errorMessage: String?
    private let library: LibraryModel
    private let preferencesURL: URL
    private let itemLoader: ItemLoader
    private var operation: Task<Void, Never>?
    public init(library: LibraryModel, preferencesURL: URL? = nil,
                itemLoader: @escaping ItemLoader = { try await WorkshopModel.fetchItems($0) }) {
        self.library = library
        self.itemLoader = itemLoader
        self.preferencesURL = preferencesURL ?? library.storeURL.deletingLastPathComponent().appendingPathComponent("workshop.json")
        let saved = (try? Data(contentsOf: self.preferencesURL)).flatMap { try? JSONDecoder().decode(WorkshopPreferences.self, from: $0) }
        tool = saved?.toolPath.map { URL(fileURLWithPath: $0) } ?? SteamPaths.discoverTool()
        accounts = SteamPaths.cachedAccounts()
        account = saved?.account ?? accounts.last ?? ""
    }
    public var selectedBytes: Int64 { candidates.filter { selected.contains($0.id) }.reduce(0) { total, item in let sum = total.addingReportingOverflow(item.bytes); return sum.overflow ? Int64.max : sum.partialValue } }
    public func refreshAccounts() { accounts = SteamPaths.cachedAccounts() }
    public func chooseTool(_ url: URL) { tool = url; savePreferences() }
    public func savePreferences() {
        do {
            let data = try JSONEncoder().encode(WorkshopPreferences(account: account, toolPath: tool?.path))
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: preferencesURL, options: .atomic)
        } catch { errorMessage = String(format: L("workshop.status.couldNotSaveDownloadSettings"), String(describing: error.localizedDescription)) }
    }
    public func loginInTerminal() {
        do {
            let tool = try requireTool(); try SteamPaths.validateAccount(account); savePreferences()
            let dir = tool.deletingLastPathComponent().path
            let q = SteamPaths.shellQuote
            let script = """
            #!/bin/bash
            cd \(q(dir)) || exit 1
            export DYLD_LIBRARY_PATH=\(q(dir))
            export DYLD_FRAMEWORK_PATH=\(q(dir))
            ulimit -n 2048
            echo \(q(L("workshop.login.terminalInstructions")))
            attempts=0
            while true; do
              ./steamcmd +login \(q(account)) +quit
              code=$?
              if [ "$code" -ne 42 ] || [ "$attempts" -ge 3 ]; then break; fi
              attempts=$((attempts+1))
            done
            echo \(q(L("workshop.login.terminalFinished")))
            read -r -p \(q(L("workshop.login.terminalClosePrompt")))
            """
            let file = preferencesURL.deletingLastPathComponent().appendingPathComponent("SteamLogin.command")
            try Data(script.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            status = L("workshop.status.completeSteamSignInInTerminalThenReturn")
        } catch { errorMessage = error.localizedDescription }
    }
    private func requireTool() throws -> URL {
        guard let tool, tool.lastPathComponent == "steamcmd", FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw WallpaperError.message(L("workshop.status.steamcmdNotFoundPlaceSteamToolsNextToThe"))
        }
        return tool
    }
    public func cancel() { operation?.cancel() }
    public func shutdown() { operation?.cancel() }
    private func start(_ work: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; failures = []; completed = 0; total = 0
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operation = nil }
            do { try await work() }
            catch is CancellationError { self.status = L("workshop.status.cancelledCompletedImportsWereKept") }
            catch { self.errorMessage = error.localizedDescription; self.status = L("workshop.status.theOperationDidNotFinishYouCanRetry") }
        }
    }
    public func downloadInput() {
        let requested = input
        start { [self] in
            try await downloadVerified(WorkshopID(requested))
        }
    }
    public func downloadItem(_ id: WorkshopID) { start { [self] in try await downloadVerified(id) } }
    private func downloadVerified(_ id: WorkshopID) async throws {
        status = L("workshop.status.checkingWallpaperType")
        let items = try await itemLoader([id])
        try Task.checkCancellation()
        guard items.count == 1, let item = items.first, item.id == id else {
            throw WallpaperError.message(L("workshop.status.steamReturnedItemInformationThatDoesNotMatch"))
        }
        guard item.isVideo else { throw WallpaperError.message(L("workshop.status.thisItemIsNotAnAccessibleWallpaperEngine")) }
        try await download([item])
    }
    public func downloadSelected() { let items = candidates.filter { selected.contains($0.id) }; guard !items.isEmpty else { return }; start { [self] in try await download(items) } }
    public func loadSubscriptions(_ ids: [WorkshopID]) { start { [self] in try await loadCandidates(ids) } }
    public func loadManifest(_ file: URL) {
        start { [self] in
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 10_000_000 else { throw WallpaperError.message(L("workshop.status.theManifestIsTooLargeSelectAppworkshop431960")) }
            try await loadCandidates(SteamKeyValues.installedIDs(String(contentsOf: file, encoding: .utf8)))
        }
    }
    private func loadCandidates(_ ids: [WorkshopID]) async throws {
        let ids = Array(Set(ids)).sorted { $0.rawValue < $1.rawValue }
        guard ids.count <= 10000 else { throw WallpaperError.message(L("workshop.status.subscriptionsExceed10000ItemsNothingWasRead")) }
        status = String(format: L("workshop.status.readingInformationForItems"), String(describing: ids.count)); total = ids.count
        var all: [WorkshopItem] = []
        for offset in stride(from: 0, to: ids.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(ids[offset..<min(offset+100, ids.count)])
            all += try await itemLoader(batch)
            completed += batch.count; status = String(format: L("workshop.status.filteringVideos"), String(describing: completed), String(describing: total))
        }
        try Task.checkCancellation()
        let videos = all.filter(\.isVideo)
        candidates = videos; selected = Set(videos.filter { !alreadyImported($0.id) }.map(\.id))
        status = String(format: L("workshop.status.foundVideosOutOfItemsTheRestAre"), String(describing: ids.count), String(describing: videos.count))
    }
    public static func fetchItems(_ ids: [WorkshopID]) async throws -> [WorkshopItem] {
        guard !ids.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((["itemcount=\(ids.count)"] + ids.enumerated().map { "publishedfileids%5B\($0.offset)%5D=\($0.element.rawValue)" }).joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { throw WallpaperError.message(L("workshop.status.theSteamWallpaperInformationRequestFailedCheckYour")) }
        let decoded = try WorkshopItem.decodeResponse(data)
        guard decoded.count == ids.count, Set(decoded.map(\.id)) == Set(ids) else { throw WallpaperError.message(L("workshop.status.steamReturnedAnIncompleteItemListThePrevious")) }
        let byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
    public func alreadyImported(_ id: WorkshopID) -> Bool {
        library.state.projects.contains { project in
            (try? WorkshopID(URL(fileURLWithPath: project.folderPath).lastPathComponent)) == id &&
            (try? WallpaperProject.load(folder: URL(fileURLWithPath: project.folderPath))) != nil
        }
    }
    @discardableResult public func importVideo(_ folder: URL) async throws -> WorkshopImportResult {
        _ = try WallpaperProject.load(folder: folder)
        if let id = try? WorkshopID(folder.lastPathComponent), alreadyImported(id) { library.refreshArtwork(); return .existing }
        try Task.checkCancellation()
        // Library restore/apply owns its generation until finished. Do not supersede it.
        while library.isBusy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        let imported = await library.importFolder(folder) { [weak self] message in self?.status = message }
        try Task.checkCancellation()
        guard imported != nil else { throw WallpaperError.message(library.errorMessage ?? L("workshop.status.importWasInterruptedByAnotherOperationTryAgain")) }
        return .imported
    }
    private func download(_ items: [WorkshopItem]) async throws {
        let tool = try requireTool(); try SteamPaths.validateAccount(account); savePreferences()
        total = items.count
        var added = 0; var skipped = 0
        for item in items {
            try Task.checkCancellation()
            if alreadyImported(item.id) { skipped += 1; completed += 1; continue }
            do {
                status = String(format: L("workshop.status.downloadingConnectingOrDownloadingPleaseWait"), String(describing: completed+1), String(describing: total), String(describing: item.title))
                var result: SteamProcessResult?
                for attempt in 0..<4 {
                    let value = try await SteamRunner.run(executable: tool, arguments: ["+@NoPromptForPassword", "1", "+login", account, "+workshop_download_item", "431960", item.id.rawValue, "+quit"], environment: SteamPaths.environment(tool: tool))
                    result = value
                    if value.exitCode != 42 || attempt == 3 { break }
                    status = L("workshop.status.steamcmdUpdatedReconnecting")
                }
                let resultValue = result!
                let folder = try SteamDownloadResult.folder(output: resultValue.output, exitCode: resultValue.exitCode, id: item.id)
                try SteamPaths.validateDownloadFolder(folder, id: item.id, roots: SteamPaths.contentRoots(tool: tool))
                status = String(format: L("workshop.status.validatingAndImporting"), String(describing: item.title))
                let imported = try await importVideo(folder)
                if imported == .imported { added += 1 } else { skipped += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append(String(format: L("workshop.status.itemFailure"), item.title, item.id.rawValue, error.localizedDescription)) }
            completed += 1
        }
        status = String(format: L("workshop.status.doneImportedAlreadyInTheLibraryFailed"), String(describing: added), String(describing: skipped), String(describing: failures.count))
    }
    public func scanLocal(_ selectedRoot: URL? = nil) {
        start { [self] in
            let roots = selectedRoot.map { [$0] } ?? SteamPaths.contentRoots(tool: tool)
            var folders: [URL] = []
            for root in roots where FileManager.default.fileExists(atPath: root.path) { folders += try SteamPaths.folders(in: root) }
            total = folders.count; var added = 0; var skipped = 0; var nonVideo = 0
            for folder in folders {
                try Task.checkCancellation(); status = String(format: L("workshop.status.checkingLocalWallpapers"), String(describing: completed+1), String(describing: total))
                do {
                    guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("project.json"))) as? [String: Any], (json["type"] as? String)?.lowercased() == "video" else { nonVideo += 1; completed += 1; continue }
                    let result = try await importVideo(folder)
                    if result == .imported { added += 1 } else { skipped += 1 }
                } catch is CancellationError { throw CancellationError() }
                catch { failures.append(String(format: L("workshop.status.folderFailure"), folder.lastPathComponent, error.localizedDescription)) }
                completed += 1
            }
            status = String(format: L("workshop.status.localScanCompleteImportedAlreadyInTheLibrary"), String(describing: added), String(describing: skipped), String(describing: nonVideo), String(describing: failures.count))
        }
    }
}
