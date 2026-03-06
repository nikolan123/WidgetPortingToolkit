//
//  ResizePopover.swift
//  WidgetPortingAPP
//
//  Created by Niko on 25.12.25.
//

import SwiftUI

struct ResizePopover: View {
    let appInfo: AppInfo
    @ObservedObject var widgetManager: WidgetManager
    let liveUpdate: Bool
    @State private var customWidth: CGFloat
    @State private var customHeight: CGFloat
    
    init(appInfo: AppInfo, widgetManager: WidgetManager, liveUpdate: Bool = true) {
        self.appInfo = appInfo
        self.widgetManager = widgetManager
        self.liveUpdate = liveUpdate
        let tweaks = widgetManager.tweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
        self._customWidth = State(initialValue: tweaks.customWidth ?? appInfo.width)
        self._customHeight = State(initialValue: tweaks.customHeight ?? appInfo.height)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resize Widget Window")
                .font(.headline)
            
            Divider()
            
            HStack {
                Text("Width:").frame(width: 50, alignment: .leading)
                if liveUpdate {
                    Slider(value: Binding(
                        get: { customWidth },
                        set: { newValue in
                            customWidth = newValue
                            widgetManager.resizeWindow(for: appInfo, width: newValue, height: customHeight)
                        }
                    ), in: 100...800)
                } else {
                    Slider(value: $customWidth, in: 100...800, onEditingChanged: { editing in
                        if !editing {
                            widgetManager.resizeWindow(for: appInfo, width: customWidth, height: customHeight)
                        }
                    })
                }
                TextField("", value: $customWidth, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit {
                        widgetManager.resizeWindow(for: appInfo, width: customWidth, height: customHeight)
                    }
            }
            
            HStack {
                Text("Height:").frame(width: 50, alignment: .leading)
                if liveUpdate {
                    Slider(value: Binding(
                        get: { customHeight },
                        set: { newValue in
                            customHeight = newValue
                            widgetManager.resizeWindow(for: appInfo, width: customWidth, height: newValue)
                        }
                    ), in: 100...800)
                } else {
                    Slider(value: $customHeight, in: 100...800, onEditingChanged: { editing in
                        if !editing {
                            widgetManager.resizeWindow(for: appInfo, width: customWidth, height: customHeight)
                        }
                    })
                }
                TextField("", value: $customHeight, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit {
                        widgetManager.resizeWindow(for: appInfo, width: customWidth, height: customHeight)
                    }
            }
            
            Divider()
            
            Button("Reset to Default") {
                customWidth = appInfo.width
                customHeight = appInfo.height
                widgetManager.resizeWindow(for: appInfo, width: appInfo.width, height: appInfo.height)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 350)
    }
}
