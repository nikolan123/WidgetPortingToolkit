//
//  OOBECoordinator.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

enum OOBEStep: Int, CaseIterable {
    case welcome = 0
    case widgetResources = 1
    case getWidgets = 2
    case instructions = 3
    case fullScreen = 4
    case complete = 5
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .widgetResources: return "Setup Widget Resources"
        case .getWidgets: return "Get Widgets"
        case .instructions: return "Basic Instructions"
        case .fullScreen: return "Full Screen Mode"
        case .complete: return "You're All Set!"
        }
    }
}

class OOBECoordinator: ObservableObject {
    @Published var currentStep: OOBEStep = .welcome
    @Published var userSelectedResourcePath: String = ""
    
    private(set) var isMovingForward: Bool = true
    
    func next() {
        if let nextStep = OOBEStep(rawValue: currentStep.rawValue + 1) {
            isMovingForward = true
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = nextStep
            }
        }
    }
    
    func back() {
        if let previousStep = OOBEStep(rawValue: currentStep.rawValue - 1) {
            isMovingForward = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = previousStep
            }
        }
    }
    
    var canGoBack: Bool {
        currentStep.rawValue > 0
    }
    
    var isLastStep: Bool {
        currentStep == .complete
    }
}

struct OOBECoordinatorView: View {
    @EnvironmentObject var manager: WidgetManager
    @StateObject private var coordinator = OOBECoordinator()
    @Environment(\.presentationMode) private var presentationMode
    @State private var offset: CGFloat = 0
    
    var body: some View {
        ZStack {
            if let bgImage = NSImage(named: "ecsb_background_tile") {
                Image(nsImage: bgImage)
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            } else {
                Color.gray.opacity(0.15)
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Content
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(OOBEStep.allCases, id: \.self) { step in
                            stepView(for: step)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .offset(x: -CGFloat(coordinator.currentStep.rawValue) * geometry.size.width)
                }
                
                Spacer()
                
                // Navigation buttons at bottom
                OOBENavigationButtons(
                    coordinator: coordinator,
                    continueAction: {
                        if coordinator.isLastStep {
                            closeWindow()
                        } else {
                            coordinator.next()
                        }
                    },
                    skipSetupAction: {
                        let alert = NSAlert()
                        alert.messageText = "Skip Setup?"
                        alert.informativeText = "You can always access this setup guide later from the Options menu."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Skip Setup")
                        alert.addButton(withTitle: "Continue Setup")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            closeWindow()
                        }
                    },
                    continueDisabled: coordinator.currentStep == .widgetResources && manager.supportDirectoryPath.isEmpty,
                    showSkip: coordinator.currentStep == .widgetResources,
                    showSkipSetup: coordinator.currentStep == .welcome
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 650, minHeight: 480)
    }
    
    private func closeWindow() {
        // Mark OOBE as completed
        manager.hasCompletedOOBE = true
        
        if let w = NSApp.keyWindow {
            w.close()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    @ViewBuilder
    private func stepView(for step: OOBEStep) -> some View {
        switch step {
        case .welcome:
            OOBEWelcomeContent(coordinator: coordinator)
        case .widgetResources:
            OOBEWidgetResourcesContent(coordinator: coordinator)
        case .getWidgets:
            OOBEGetWidgetsContent(coordinator: coordinator)
        case .instructions:
            OOBEInstructionsContent(coordinator: coordinator)
        case .fullScreen:
            OOBEFullScreenContent(coordinator: coordinator)
        case .complete:
            OOBECompleteContent(coordinator: coordinator, onFinish: closeWindow)
        }
    }
}

// MARK: - Navigation Buttons Component
struct OOBENavigationButtons: View {
    @ObservedObject var coordinator: OOBECoordinator
    let continueAction: () -> Void
    let skipSetupAction: () -> Void
    let continueDisabled: Bool
    let showSkip: Bool
    let showSkipSetup: Bool
    
    init(coordinator: OOBECoordinator, continueAction: @escaping () -> Void, skipSetupAction: @escaping () -> Void, continueDisabled: Bool = false, showSkip: Bool = false, showSkipSetup: Bool = false) {
        self.coordinator = coordinator
        self.continueAction = continueAction
        self.skipSetupAction = skipSetupAction
        self.continueDisabled = continueDisabled
        self.showSkip = showSkip
        self.showSkipSetup = showSkipSetup
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // skip setup btn for welcome page
            if showSkipSetup {
                Button("Skip Setup") {
                    skipSetupAction()
                }
                .font(.custom("Lucida Grande", size: 13))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Back button
            Button("Back") {
                coordinator.back()
            }
            .font(.custom("Lucida Grande", size: 15))
            .buttonStyle(.bordered)
            .controlSize(.large)
            .opacity(coordinator.canGoBack ? 1.0 : 0.0)
            .disabled(!coordinator.canGoBack)
            .animation(.easeInOut(duration: 0.25), value: coordinator.canGoBack)
            
            Spacer()
            
            // skip btn for wrs page
            if showSkip {
                Button("Skip") {
                    let alert = NSAlert()
                    alert.messageText = "Skip Widget Resources Setup?"
                    alert.informativeText = "Widgets won't work without the WidgetResources folder. You can set it up later in Options > Install Support Directory."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Skip Anyway")
                    alert.addButton(withTitle: "Cancel")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        continueAction()
                    }
                }
                .font(.custom("Lucida Grande", size: 13))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Continue button
            Button(coordinator.isLastStep ? "Get Started" : "Continue") {
                continueAction()
            }
            .id(coordinator.isLastStep)
            .font(.custom("Lucida Grande", size: 15))
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .disabled(continueDisabled)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.currentStep)
        .padding(.top, 10)
    }
}

struct OOBECoordinatorView_Previews: PreviewProvider {
    static var previews: some View {
        OOBECoordinatorView()
            .environmentObject(WidgetManager())
    }
}

extension WidgetManager {
    func openOOBEWindow() {
        let hostingView = NSHostingView(rootView: OOBECoordinatorView().environmentObject(self))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.title = "Welcome"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("OOBEWindow")
        NSApp.activate(ignoringOtherApps: true)
    }
}
