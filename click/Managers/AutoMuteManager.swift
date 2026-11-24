//
//  AutoMuteManager.swift
//  click
//
//  Created for Click fork enhancements.
//

import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation

struct ExcludedApp: Identifiable, Codable, Hashable, Defaults.Serializable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

enum AutoMuteReason: Equatable {
    case microphoneActive
    case excludedApp(String)

    var description: String {
        switch self {
        case .microphoneActive:
            "Microphone active"
        case let .excludedApp(appName):
            "\(appName) focused"
        }
    }
}

class AutoMuteManager: ObservableObject {
    static let shared = AutoMuteManager()

    @Published private(set) var muteReason: AutoMuteReason?

    var isAutoMuted: Bool {
        muteReason != nil
    }

    private var autoMuteOnMic = false
    private var excludedApps: [ExcludedApp] = []
    private var frontmostBundleID: String?
    private var frontmostAppName: String?

    private var workspaceObserver: NSObjectProtocol?
    private var micPollTimer: AnyCancellable?
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        let front = NSWorkspace.shared.frontmostApplication
        frontmostBundleID = front?.bundleIdentifier
        frontmostAppName = front?.localizedName

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.frontmostBundleID = app.bundleIdentifier
            self?.frontmostAppName = app.localizedName
            self?.evaluateAutoMuteState()
        }

        startHardwareDeviceListener()
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        stopHardwareDeviceListener()
        micPollTimer?.cancel()
    }

    func configure(autoMuteOnMicrophone: Bool, excludedApps: [ExcludedApp]) {
        self.autoMuteOnMic = autoMuteOnMicrophone
        self.excludedApps = excludedApps

        if autoMuteOnMicrophone {
            startMicrophoneMonitoring()
        } else {
            micPollTimer?.cancel()
            micPollTimer = nil
        }

        evaluateAutoMuteState()
    }

    func evaluateAutoMuteState() {
        var newReason: AutoMuteReason?

        if let frontID = frontmostBundleID,
           let matched = excludedApps.first(where: { $0.bundleIdentifier == frontID }) {
            newReason = .excludedApp(frontmostAppName ?? matched.name)
        } else if autoMuteOnMic, Self.isAnyMicrophoneActive() {
            newReason = .microphoneActive
        }

        if newReason != muteReason {
            muteReason = newReason
        }
        AudioManager.setAutoMuted(newReason != nil)
    }

    private func startMicrophoneMonitoring() {
        guard micPollTimer == nil else { return }
        micPollTimer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateAutoMuteState()
            }
    }

    private func startHardwareDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.evaluateAutoMuteState()
        }
        devicesListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func stopHardwareDeviceListener() {
        guard let block = devicesListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        devicesListenerBlock = nil
    }

    // Checks CoreAudio input devices without requesting microphone recording permission.
    static func isAnyMicrophoneActive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        ) == noErr else {
            return false
        }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        ) == noErr else {
            return false
        }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        for deviceID in deviceIDs {
            guard inputChannelCount(for: deviceID) > 0 else { continue }

            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &size, &isRunning)
            if status == noErr, isRunning != 0 {
                return true
            }
        }

        return false
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize) == noErr,
              propertySize > 0
        else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, rawPointer) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
