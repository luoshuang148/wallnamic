import WallpaperCore
import SwiftUI
import WebKit
import WallpaperRuntime

private struct WorkshopWebSurface: NSViewRepresentable {
    let browser: WorkshopBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WorkshopBrowserView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    @StateObject private var browser = WorkshopBrowser()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("workshop.browser.browseWorkshop")).font(.title2.bold())
                Spacer()
                Button(L("workshop.browser.close")) { browser.close(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                Button(action: browser.goBack) { Image(systemName: "chevron.left") }
                    .help(L("workshop.browser.back")).accessibilityLabel(L("workshop.browser.back")).disabled(!browser.canGoBack)
                Button(action: browser.goForward) { Image(systemName: "chevron.right") }
                    .help(L("workshop.browser.forward")).accessibilityLabel(L("workshop.browser.forward")).disabled(!browser.canGoForward)
                Button(action: browser.reload) { Image(systemName: "arrow.clockwise") }
                    .help(L("workshop.browser.reload")).accessibilityLabel(L("workshop.browser.reload"))
                Button(L("workshop.browser.workshopHome"), action: browser.goHome)
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text(browser.address).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                Spacer(minLength: 0)
                if browser.isLoading { ProgressView().controlSize(.small) }
            }
            WorkshopWebSurface(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = browser.errorMessage ?? model.errorMessage ?? library.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled).lineLimit(3)
            }
            if !model.failures.isEmpty {
                DisclosureGroup(String(format: L("workshop.browser.itemsIncompleteExpandForDetails"), String(describing: model.failures.count))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
                                Text(failure).font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.frame(maxHeight: 100)
                }
            }
            HStack {
                if browser.isChecking { ProgressView().controlSize(.small); Text(L("workshop.browser.checkingItem")).font(.callout) }
                else if let item = browser.currentItem {
                    Text(item.title).font(.callout).lineLimit(1)
                    if !item.isVideo { Text(L("workshop.browser.onlyVideoWallpapersAreSupported")).font(.caption).foregroundStyle(.secondary) }
                } else { Text(L("workshop.browser.selectAnItemToDownloadItsVideoWallpaper")).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button(L("workshop.browser.downloadThisItem")) {
                    if let item = browser.currentItem, item.isVideo { model.downloadItem(item.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(browser.isLoading || browser.isChecking || browser.currentItem?.isVideo != true || (model.isBusy && !model.isSynchronizing) || library.isBusy)
            }
            HStack {
                if model.isBusy || library.isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button(L("workshop.browser.cancelTask")) { model.cancel() } }
            }
            if model.isBusy, model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }
        .padding(20).frame(width: 1000, height: 720)
        .onDisappear { browser.close() }
    }
}
