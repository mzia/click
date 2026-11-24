//
//  EventManager.swift
//  click
//
//  Created by Pablo Ruiz on 24/8/24.
//

import SwiftUI

class EventManager {
    private static var eventMonitor: Any?
    private static var localEventMonitor: Any?
    private static var activeKeys: Set<UInt16> = []
    private static let eventQueue = DispatchQueue(label: "com.pruizlezcano.click.eventQueue", qos: .userInteractive)

    static func setupEventMonitors() {
        removeEventMonitors()

        // Global monitor
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged],
            handler: { event in
                handleEvent(event: event)
            }
        )

        // Local monitor (when the app is focused)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged],
            handler: { event -> NSEvent? in
                handleEvent(event: event)
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.function) {
                    // Allow the event to propagate for system shortcuts
                    return event
                }
                return nil // Prevents the 'beep' sound by macOS
            }
        )
    }

    private static func handleEvent(event: NSEvent) {
        let type = event.type
        let keyCode = event.keyCode
        let modifierRawValue = event.modifierFlags.rawValue

        eventQueue.async {
            switch type {
            case .keyDown:
                if !activeKeys.contains(keyCode) {
                    activeKeys.insert(keyCode)
                    AudioManager.playSound(keyCode: keyCode)
                }
            case .flagsChanged:
                // Return if key released (not caps lock)
                guard modifierRawValue != 256 || keyCode == 57 else { return }
                AudioManager.playSound(keyCode: keyCode)
            case .keyUp:
                if activeKeys.remove(keyCode) != nil {
                    AudioManager.playKeyUpSound(keyCode: keyCode)
                }
            default:
                break
            }
        }
    }

    static func removeEventMonitors() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        eventQueue.async {
            activeKeys.removeAll()
        }
    }
}
