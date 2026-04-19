//
//  freespeechApp.swift
//  freespeech
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI

@main
struct freespeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorSchemeString == "dark" ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 600)
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = NSApplication.shared.windows.first else { return }

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        window.styleMask.insert(.fullSizeContentView)
        window.center()

        setTrafficLights(visible: false, in: window)

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak window] event in
            guard let window else { return event }
            let mouse = NSEvent.mouseLocation
            let inTitlebar = NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - 40,
                width: window.frame.width,
                height: 40
            ).contains(mouse)
            self.setTrafficLights(visible: inTitlebar, in: window)
            return event
        }
    }

    private func setTrafficLights(visible: Bool, in window: NSWindow) {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = !visible
        }
    }
} 
