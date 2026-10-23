import AppKit
import SwiftUI
import WallpaperCore

struct LanguageSettingsView: View {
    @ObservedObject private var language = LanguageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("settings.language")).font(.title2.weight(.semibold))
            Text(L("settings.language.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Picker(L("settings.language"), selection: Binding(
                    get: { language.selection },
                    set: { language.setLanguage($0) }
                )) {
                    ForEach(LanguageStore.selectableCodes, id: \.self) { code in
                        Text(LanguageStore.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                // Picker caches its rows; refresh them so the Follow System
                // label is recomputed in the newly selected language.
                .id(language.resolvedCode)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 650, height: 530, alignment: .topLeading)
    }
}
