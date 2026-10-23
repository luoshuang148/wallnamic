import WallpaperCore
import SwiftUI
import WallpaperRuntime

struct SettingsView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var startup: LoginStartupModel
    @ObservedObject var exit: ManagementExitCoordinator
    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .library
    private enum Page: CaseIterable {
        case library, performance, language
        var title: String {
            switch self {
            case .library: return L("settings.libraryAutoplay")
            case .performance: return L("library.performancePower")
            case .language: return L("settings.language")
            }
        }
        var symbol: String {
            switch self {
            case .library: return "slider.horizontal.3"
            case .performance: return "leaf"
            case .language: return "globe"
            }
        }
    }
    var body: some View {
        VStack(spacing:12) {
            HStack {
                Text(L("library.settings")).font(.title2.weight(.semibold))
                Spacer()
                Button(L("settings.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Divider()
            HStack(alignment:.top,spacing:0) {
                VStack(spacing:8) {
                    ForEach(Page.allCases,id:\.self) { item in
                        Button { page = item } label: {
                            Label(item.title,systemImage:item.symbol)
                                .font(.system(size:12,weight:.medium))
                                .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                                .contentShape(Rectangle())
                                .background(page == item ? Color.accentColor.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.trailing,12).frame(width:190)
                Divider()
                Group {
                    switch page {
                    case .library:
                        FeatureSettingsView(model:model,startup:startup,embedded:true)
                    case .performance:
                        PerformanceView(model:model,embedded:true)
                    case .language:
                        LanguageSettingsView()
                    }
                }.frame(width:650,height:530,alignment:.top)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if let error = exit.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(exit.isExiting ? L("settings.stoppingWallpapers") : L("settings.stopWallpapersAndQuitCompletely")) {
                    Task { await exit.stopWallpaperAndExit() }
                }.disabled(exit.isExiting)
            }
        }.padding(20).frame(width:900,height:680)
    }
}
