import SwiftUI
import AppKit
import WebKit
import WallpaperCore
import WallpaperRuntime

struct WorkshopView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    let onImportFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsSubscriptions = false
    @State private var showsBrowser = false
    @State private var showsLinkDownload = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("library.workshop")).font(.title2.bold())
                Spacer()
                Button(L("settings.done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button { showsBrowser = true } label: { Label(L("workshop.browseWorkshop"), systemImage: "globe") }
                            .buttonStyle(.borderedProminent)
                        Button { showsSubscriptions = true } label: { Label(L("workshop.readSteamSubscriptions"), systemImage: "person.crop.circle.badge.checkmark") }
                        Spacer()
                        Menu(L("workshop.otherSources")) {
                            Button(L("workshop.importWallpaperFolder"), action: onImportFolder)
                            Button(L("workshop.downloadFromLink")) { showsLinkDownload = true }
                            Button(L("workshop.importLocalDownloads")) { model.scanLocal() }
                            Divider()
                            Button(L("workshop.selectSteamVideoFolder"), action: chooseLocal)
                            Button(L("workshop.readWindowsDownloadManifest"), action: chooseManifest)
                        }.frame(width: 120)
                    }.disabled(model.isBusy || library.isBusy)
                    GroupBox(L("workshop.downloadAccount")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField(L("workshop.steamLoginAccountName"), text: $model.account).textFieldStyle(.roundedBorder)
                                    .onSubmit { model.savePreferences() }
                                if !model.accounts.isEmpty {
                                    Menu(L("workshop.signedInAccounts")) {
                                        ForEach(model.accounts, id: \.self) { name in Button(name) { model.account = name; model.savePreferences() } }
                                    }.frame(width: 120)
                                }
                                Button(L("workshop.signInToDownload")) { model.loginInTerminal() }
                                    .help(L("workshop.theAccountMustOwnWallpaperEngineCompleteSteam"))
                            }.disabled(model.isBusy || library.isBusy)
                            HStack {
                                Image(systemName: model.tool == nil ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(model.tool == nil ? .orange : .secondary)
                                Text(model.tool == nil ? L("workshop.steamcmdNotFound") : L("workshop.steamcmdReady")).font(.caption)
                                Spacer()
                                Button(L("workshop.chooseTool"), action: chooseTool).controlSize(.small).disabled(model.isBusy || library.isBusy)
                            }
                        }.padding(8)
                    }
                    if !model.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(String(format: L("workshop.videoWallpapers"), String(describing: model.candidates.count))).font(.headline)
                                Spacer()
                                Button(L("workshop.selectAllNotImported")) { model.selected = Set(model.candidates.filter { !model.alreadyImported($0.id) }.map(\.id)) }
                                Button(L("workshop.deselectAll")) { model.selected = [] }
                            }.disabled(model.isBusy || library.isBusy)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(model.candidates) { item in
                                        HStack {
                                            Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } })) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(item.title).lineLimit(2)
                                                    Text("\(item.id.rawValue) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }.toggleStyle(.checkbox).disabled(model.isBusy || library.isBusy || model.alreadyImported(item.id))
                                            Spacer()
                                            if model.alreadyImported(item.id) { Text(L("workshop.imported")).font(.caption).foregroundStyle(.secondary) }
                                            Link(L("workshop.details"), destination: item.id.url).font(.caption)
                                        }
                                    }
                                }.padding(12)
                            }.frame(height: 200).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Text(String(format: L("workshop.selectedAbout"), String(describing: model.selected.count), String(describing: ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file)))).font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button(L("workshop.downloadSelectedVideos")) { model.downloadSelected() }.buttonStyle(.borderedProminent).disabled(model.isBusy || library.isBusy || model.selected.isEmpty)
                            }
                        }
                    }
                    if let error = model.errorMessage ?? library.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    if !model.failures.isEmpty {
                        DisclosureGroup(String(format: L("workshop.browser.itemsIncompleteExpandForDetails"), String(describing: model.failures.count))) {
                            VStack(alignment: .leading, spacing: 8) { ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.caption).textSelection(.enabled) } }.padding(.top, 8)
                        }
                    }
                }
            }
            Divider()
            HStack {
                if model.isBusy || library.isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? (library.isBusy ? L("workshop.importing") : model.status)).font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button(L("workshop.browser.cancelTask")) { model.cancel() } }
            }
            if model.isBusy && model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }.padding(24).frame(width: 780, height: 660).onAppear { model.refreshAccounts() }
        .sheet(isPresented: $showsSubscriptions) {
            SubscriptionView { ids in model.loadSubscriptions(ids); showsSubscriptions = false }
        }
        .sheet(isPresented: $showsBrowser) { WorkshopBrowserView(model: model, library: library) }
        .sheet(isPresented: $showsLinkDownload) { WorkshopLinkDownloadView(model: model, library: library) }
    }
    private func chooseTool() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectTheSteamCMDExecutableSteamcmd"); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.chooseTool(url) }
    }
    private func chooseLocal() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectContent431960ContainingNumberedWallpaperFolders"); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { model.scanLocal(url) }
    }
    private func chooseManifest() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectWindowsAppworkshop431960Acf"); panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.loadManifest(url) }
    }
}

private struct WorkshopLinkDownloadView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    private var isBusy: Bool { model.isBusy || library.isBusy }
    private var canDownload: Bool { !isBusy && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("workshop.downloadFromLinkTitle")).font(.title2.bold())
                Spacer()
                Button(L("workshop.browser.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField(L("workshop.pasteASteamWorkshopLinkOrNumericID"), text: $model.input)
                    .textFieldStyle(.roundedBorder).disabled(isBusy)
                    .onSubmit { if canDownload { model.downloadInput() } }
                Button(L("workshop.downloadAndImport")) { model.downloadInput() }
                    .buttonStyle(.borderedProminent).disabled(!canDownload)
            }
            if let error = model.errorMessage ?? library.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !model.failures.isEmpty {
                DisclosureGroup(String(format: L("workshop.browser.itemsIncompleteExpandForDetails"), String(describing: model.failures.count))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
                                Text(failure).font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
            Divider()
            HStack {
                if isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? (library.isBusy ? L("workshop.importing") : model.status))
                    .font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button(L("workshop.browser.cancelTask")) { model.cancel() } }
            }
            if model.isBusy, model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }.padding(24).frame(width: 620)
    }
}

private struct SubscriptionWebView: NSViewRepresentable {
    let browser: SubscriptionBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
private struct SubscriptionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @StateObject private var browser = SubscriptionBrowser()
    @Environment(\.dismiss) private var dismiss
    let onRead: ([WorkshopID]) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("workshop.steamAccountSubscriptions")).font(.title2.bold())
                Spacer()
                Button(browser.isReading ? L("workshop.cancelReading") : L("workshop.browser.close")) { browser.cancel(); dismiss() }
            }
            Text(L("workshop.signInToTheSteamWebsiteAndThe")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text(browser.address).font(.caption).lineLimit(1).textSelection(.enabled)
            }
            SubscriptionWebView(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = browser.errorMessage { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                if browser.isReading { ProgressView().controlSize(.small) }
                Text(browser.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("workshop.backToMySubscriptions")) { browser.goHome() }.disabled(browser.isReading)
                Button(L("workshop.readAllSubscriptions")) { browser.readAll(completion: onRead) }.buttonStyle(.borderedProminent).disabled(browser.isReading)
            }
        }.padding(20).frame(width: 880, height: 700).onDisappear { browser.cancel() }
    }
}
