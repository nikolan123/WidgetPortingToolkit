//
//  SplashScreenView.swift
//  WidgetPortingAPP
//
//  Created by Niko on 19.10.25.
//

import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var widgetManager: WidgetManager
    
    private var backgroundImage: NSImage? {
        NSImage(named: "ecsb_background_tile")
    }

    var body: some View {
        ZStack {
            // Patterned background
            if let img = backgroundImage {
                Image(nsImage: img)
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            } else {
                Color.gray.opacity(0.15).ignoresSafeArea()
            }
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Widget Porting Toolkit")
                        .font(.title)
                        .bold()
                    Text("Loading widgets…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                if let current = widgetManager.currentLoadingWidgetName {
                    Text("\(current)")
                        .font(.subheadline)
                }
                
                ProgressView(value: Double(widgetManager.loadingProgressNumerator),
                             total: Double(max(widgetManager.loadingProgressDenominator, 1)))
                .frame(width: 280)
                
                Text("\(widgetManager.loadingProgressNumerator) / \(widgetManager.loadingProgressDenominator)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }
}

#if DEBUG
final class MockWidgetManager: WidgetManager {
    override init() {
        super.init()
        self.loadingProgressDenominator = 10
        self.loadingProgressNumerator = 4
        self.currentLoadingWidgetName = "Weather Widget"
    }
}

#Preview {
    SplashScreenView()
        .environmentObject({
            let mock = WidgetManager()
            mock.loadingProgressDenominator = 10
            mock.loadingProgressNumerator = 4
            mock.currentLoadingWidgetName = "Weather Widget"
            return mock
        }())
        .frame(width: 600, height: 400)
}
#endif
