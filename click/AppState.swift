//
//  AppState.swift
//  click
//
//  Created by Pablo Ruiz on 21/8/24.
//

import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import ServiceManagement

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var soundpack: Soundpack = Defaults[.soundpack] {
        didSet {
            Defaults[.soundpack] = soundpack
        }
    }

    @Published var permissionsGranted = PermissionsManager.getStatus()
    @Published var isActive = PermissionsManager.getStatus()

    @Published var volumePreset: VolumePreset = Defaults[.volumePreset] {
        didSet {
            Defaults[.volumePreset] = volumePreset
            syncAudioPlaybackSettings()
        }
    }

    @Published var overrideVolume: Bool = Defaults[.overrideVolume] {
        didSet {
            Defaults[.overrideVolume] = overrideVolume
            syncAudioPlaybackSettings()
        }
    }

    @Published var customVolume: Float = Defaults[.customVolume] {
        didSet {
            Defaults[.customVolume] = customVolume
            syncAudioPlaybackSettings()
        }
    }

    @Published var outputDevice: OutputDevice = Defaults[.outputDevice] {
        didSet {
            Defaults[.outputDevice] = outputDevice
            syncAudioPlaybackSettings()
        }
    }

    var effectiveVolume: Float {
        overrideVolume ? customVolume : volumePreset.volume
    }

    var startApp: (() -> Void)?
    var stopApp: (() -> Void)?

    private var permissionTimer: AnyCancellable?
    private var appActiveObserver: AnyCancellable?

    init() {
        syncAudioPlaybackSettings()

        KeyboardShortcuts.onKeyUp(for: .toggle) { [weak self] in
            guard let self, self.permissionsGranted else { return }
            self.toggle()
            NotificationsManager.stateNotification(state: self.isActive)
        }

        appActiveObserver = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }

        if !permissionsGranted {
            startPermissionMonitoring()
        }
    }

    func syncAudioPlaybackSettings() {
        AudioManager.updatePlaybackSettings(volume: effectiveVolume, outputDevice: outputDevice)
    }

    func startPermissionMonitoring() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
    }

    func refreshPermissions() {
        let isGranted = PermissionsManager.getStatus()
        guard isGranted != permissionsGranted else { return }

        permissionsGranted = isGranted
        if isGranted {
            permissionTimer?.cancel()
            permissionTimer = nil
            startApp?()
            NotificationsManager.requestPermission()
        } else {
            stopApp?()
            startPermissionMonitoring()
        }
    }

    func toggle() {
        guard permissionsGranted else { return }
        if isActive {
            stopApp?()
        } else {
            startApp?()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to modify login item: \(error.localizedDescription)")
        }
    }
}
