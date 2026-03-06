//
//  AboutWindow.swift
//  WidgetPortingAPP
//
//  Created by Niko on 11.11.25.
//

import SwiftUI
import AppKit

struct AboutWindow: View {
    @AppStorage("defaultWidgetLanguage") var defaultWidgetLanguage: String = ""
    @Environment(\.presentationMode) private var presentationMode
    
    let gitCommitShort = Bundle.main.object(forInfoDictionaryKey: "GitCommitShort") as? String ?? "Unknown"
    
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

            VStack(spacing: 10) {
                Image("dashboard_2015")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(radius: 5, y: 2)

                Divider().frame(width: 170)
                    .opacity(0.25)

                Text("Widget Porting Toolkit")
                    .font(.title)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Made by Niko • Commit \(gitCommitShort)")
                    .foregroundStyle(.gray)
                    .font(.callout)
                
                HStack {
                    Link(destination: URL(string: "https://widgets.nikolan.net/")!) {
                        Text("Official Website")
                    }
                    
                    Text("•")
                        .foregroundStyle(.gray)
                    
                    Link(destination: URL(string: "https://github.com/nikolan123/WidgetPortingToolkit/")!) {
                        Text("GitHub")
                    }
                }
                .foregroundStyle(.blue)
                .font(.callout)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 40)
        }
        .frame(width: 400, height: 300)
        .preferredColorScheme(.dark)
    }
}

func openAboutWindow() {
    let popupView = AboutWindow()
    let hosting = NSHostingController(rootView: popupView)

    let window = NSWindow(contentViewController: hosting)
    window.title = "About Widget Porting Toolkit"
    window.center()
    window.setContentSize(NSSize(width: 400, height: 300))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.makeKeyAndOrderFront(nil)
    window.level = .floating
}

#Preview {
    AboutWindow()
}
