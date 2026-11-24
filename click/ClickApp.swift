//
//  ClickApp.swift
//  click
//
//  Created by Pablo Ruiz on 21/8/24.
//

import AppIntents
import Defaults
import SwiftUI

@main
struct ClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environmentObject(appState)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: Self.menuBarIcon(isActive: appState.isActive && !appState.isAutoMuted))
        }

        Settings {
            SettingsView()
        }
        .environmentObject(appState)
    }

    private static func menuBarIcon(isActive: Bool) -> NSImage {
        guard let baseIcon = NSImage(named: "MenuIcon")?.copy() as? NSImage else {
            let symbolName = isActive ? "keyboard" : "keyboard.badge.ellipsis"
            let fallback = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Click") ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        let ratio = baseIcon.size.width > 0 ? baseIcon.size.height / baseIcon.size.width : 1
        let targetHeight: CGFloat = 18
        let targetWidth = targetHeight / max(ratio, 0.1)
        let targetSize = NSSize(width: targetWidth, height: targetHeight)

        if isActive {
            baseIcon.size = targetSize
            baseIcon.isTemplate = true
            return baseIcon
        }

        // Draw a dimmed template icon with a diagonal slash when paused or auto-muted
        let mutedIcon = NSImage(size: targetSize, flipped: false) { rect in
            baseIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)

            let slash = NSBezierPath()
            slash.lineWidth = 1.6
            slash.lineCapStyle = .round
            slash.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2))
            slash.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            NSColor.labelColor.setStroke()
            slash.stroke()
            return true
        }
        mutedIcon.isTemplate = true
        return mutedIcon
    }
}
