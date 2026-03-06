//
//  LanguagePopover.swift
//  WidgetPortingAPP
//
//  Created by Niko on 26.12.25.
//

import SwiftUI

struct LanguagePopoverView: View {
    let appInfo: AppInfo
    @ObservedObject var widgetManager: WidgetManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Language")
                .font(.headline)
                .padding(.bottom, 4)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    let currentLang = widgetManager.selectedLanguages[appInfo.bundleIdentifier + "_" + appInfo.id]
                    
                    Button {
                        let key = appInfo.bundleIdentifier + "_" + appInfo.id
                        widgetManager.setLanguage(for: key, language: nil)
                        widgetManager.prepareLanguage(for: appInfo, language: nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Default")
                            Spacer()
                            if currentLang == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(currentLang == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(4)

                    Divider()

                    ForEach(appInfo.languages, id: \.self) { lang in
                        Button {
                            let key = appInfo.bundleIdentifier + "_" + appInfo.id
                            widgetManager.setLanguage(for: key, language: lang)
                            widgetManager.prepareLanguage(for: appInfo, language: lang)
                            dismiss()
                        } label: {
                            HStack {
                                Text(lang)
                                Spacer()
                                if currentLang == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(currentLang == lang ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .frame(width: 200)
    }
}
