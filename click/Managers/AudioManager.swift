//
//  AudioManager.swift
//  click
//
//  Created by Pablo Ruiz on 24/8/24.
//

import AudioToolbox
import AVFoundation
import CoreAudio
import Defaults
import Foundation
import OggDecoder

class AudioManager {
    private struct LoadedSoundpack {
        let format: AVAudioFormat
        let buffers: [UInt16: AVAudioPCMBuffer]
    }

    private static let playerPoolSize = 16
    private static let audioQueue = DispatchQueue(label: "com.pruizlezcano.click.audioQueue", qos: .userInteractive)
    private static let previewQueue = DispatchQueue(label: "com.pruizlezcano.click.previewQueue", qos: .userInitiated)

    private static var engine: AVAudioEngine?
    private static var eqNode: AVAudioUnitEQ?
    private static var playerNodes: [AVAudioPlayerNode] = []
    private static var configuredFormat: AVAudioFormat?
    private static var nextNodeIndex = 0

    private static var activePack: LoadedSoundpack?
    private static var decodedCache: [Soundpack: LoadedSoundpack] = [:]

    private static var currentVolume: Float = 1.0
    private static var currentOutputDevice: OutputDevice = .any
    private static var configObserver: NSObjectProtocol?
    private static var previewToken = UUID()

    static func updatePlaybackSettings(volume: Float, outputDevice: OutputDevice) {
        audioQueue.async {
            currentVolume = max(0, volume)
            let deviceChanged = currentOutputDevice != outputDevice
            currentOutputDevice = outputDevice

            applyGain()
            if deviceChanged, engine != nil {
                applyOutputDevice(outputDevice)
            }
        }
    }

    static func loadSoundPack(_ soundPack: Soundpack, saveState: Bool = true) {
        print("Loading sound: \(soundPack.rawValue).ogg")

        loadBuffers(for: soundPack) { loaded in
            guard let loaded else { return }

            audioQueue.async {
                activePack = loaded
                configureEngineIfNeeded(for: loaded.format)
                print("Sound loaded successfully")
            }

            if saveState {
                DispatchQueue.main.async {
                    if AppState.shared.soundpack != soundPack {
                        AppState.shared.soundpack = soundPack
                    }
                    Defaults[.soundpack] = soundPack
                }
            }
        }
    }

    static func playSound(keyCode: UInt16) {
        audioQueue.async {
            guard let pack = activePack else { return }
            playBuffer(for: keyCode, from: pack)
        }
    }

    static func previewSoundPack(_ soundPack: Soundpack) {
        let token = UUID()
        audioQueue.async {
            previewToken = token
        }

        loadBuffers(for: soundPack) { loaded in
            guard let loaded else { return }

            previewQueue.async {
                let keyCodes: [UInt16] = [56, 4, 14, 37, 37, 31, 49, 56, 13, 31, 15, 37, 2, 56, 18] // Hello World!
                let waitTimes: [TimeInterval] = [
                    0.17, 0.28, 0.22, 0.15, 0.16, 0.16, 0.2, 0.1,
                    0.13, 0.17, 0.2, 0.23, 0.2, 0.21, 0.1
                ]

                for index in 0 ..< keyCodes.count {
                    let isCancelled = audioQueue.sync { previewToken != token }
                    if isCancelled { break }

                    audioQueue.async {
                        playBuffer(for: keyCodes[index], from: loaded)
                    }
                    Thread.sleep(forTimeInterval: waitTimes[index])
                }
            }
        }
    }

    // MARK: - Decoding & Buffering

    private static func loadBuffers(for soundPack: Soundpack, completion: @escaping (LoadedSoundpack?) -> Void) {
        audioQueue.async {
            if let cached = decodedCache[soundPack] {
                completion(cached)
                return
            }

            guard let soundURL = Bundle.main.url(forResource: soundPack.rawValue, withExtension: "ogg") else {
                print("Sound not found: \(soundPack.rawValue).ogg")
                completion(nil)
                return
            }

            guard let soundpackData = soundPack.soundpack else {
                print("Soundpack JSON not found: \(soundPack.rawValue).json")
                completion(nil)
                return
            }

            let decoder = OGGDecoder()
            decoder.decode(soundURL) { savedWavUrl in
                guard let savedWavUrl else {
                    print("Failed to decode OGG file")
                    completion(nil)
                    return
                }

                defer {
                    try? FileManager.default.removeItem(at: savedWavUrl)
                }

                do {
                    let loaded = try buildLoadedSoundpack(from: savedWavUrl, defines: soundpackData.defines)
                    audioQueue.async {
                        decodedCache[soundPack] = loaded
                        completion(loaded)
                    }
                } catch {
                    print("Failed to build audio buffers: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }

    private static func buildLoadedSoundpack(
        from wavURL: URL,
        defines: [String: [Int]?]
    ) throws -> LoadedSoundpack {
        let audioFile = try AVAudioFile(forReading: wavURL)
        let format = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)

        guard let fullBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate PCM buffer"])
        }
        try audioFile.read(into: fullBuffer)

        let sampleRate = format.sampleRate
        let sourceFrameLength = Int(fullBuffer.frameLength)
        let channelCount = Int(format.channelCount)
        var slicedBuffers: [UInt16: AVAudioPCMBuffer] = [:]

        for (keyString, rawSlice) in defines {
            guard
                let keyCode = UInt16(keyString),
                let slice = rawSlice,
                slice.count >= 2,
                slice[0] >= 0,
                slice[1] > 0
            else {
                continue
            }

            let startFrame = Int((Double(slice[0]) / 1000.0) * sampleRate)
            let desiredFrames = Int((Double(slice[1]) / 1000.0) * sampleRate)
            guard startFrame < sourceFrameLength, desiredFrames > 0 else { continue }

            let availableFrames = min(desiredFrames, sourceFrameLength - startFrame)
            guard
                availableFrames > 0,
                let keyBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(availableFrames))
            else {
                continue
            }
            keyBuffer.frameLength = AVAudioFrameCount(availableFrames)

            if let srcChannels = fullBuffer.floatChannelData, let dstChannels = keyBuffer.floatChannelData {
                let bytesToCopy = availableFrames * MemoryLayout<Float>.size
                for channel in 0 ..< channelCount {
                    memcpy(dstChannels[channel], srcChannels[channel].advanced(by: startFrame), bytesToCopy)
                }
            }

            slicedBuffers[keyCode] = keyBuffer
        }

        return LoadedSoundpack(format: format, buffers: slicedBuffers)
    }

    // MARK: - AVAudioEngine Management (audioQueue only)

    private static func configureEngineIfNeeded(for format: AVAudioFormat) {
        if let existingEngine = engine,
           let existingFormat = configuredFormat,
           existingFormat == format {
            if !existingEngine.isRunning {
                try? existingEngine.start()
            }
            return
        }

        teardownEngine()

        let newEngine = AVAudioEngine()
        let packMixer = AVAudioMixerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        newEngine.attach(packMixer)
        newEngine.attach(eq)
        newEngine.connect(packMixer, to: eq, format: format)
        newEngine.connect(eq, to: newEngine.mainMixerNode, format: format)

        var nodes: [AVAudioPlayerNode] = []
        nodes.reserveCapacity(playerPoolSize)
        for _ in 0 ..< playerPoolSize {
            let node = AVAudioPlayerNode()
            newEngine.attach(node)
            newEngine.connect(node, to: packMixer, format: format)
            nodes.append(node)
        }

        engine = newEngine
        eqNode = eq
        playerNodes = nodes
        configuredFormat = format
        nextNodeIndex = 0

        applyOutputDevice(currentOutputDevice)
        applyGain()

        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error.localizedDescription)")
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { _ in
            audioQueue.async {
                guard let currentEngine = engine, !currentEngine.isRunning else { return }
                do {
                    try currentEngine.start()
                } catch {
                    print("Failed to restart AVAudioEngine after configuration change: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func teardownEngine() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        for node in playerNodes {
            node.stop()
        }
        engine?.stop()
        engine = nil
        eqNode = nil
        playerNodes = []
        configuredFormat = nil
    }

    private static func playBuffer(for keyCode: UInt16, from pack: LoadedSoundpack) {
        guard let buffer = pack.buffers[keyCode] else { return }

        configureEngineIfNeeded(for: pack.format)
        guard let currentEngine = engine, !playerNodes.isEmpty else { return }

        if !currentEngine.isRunning {
            do {
                try currentEngine.start()
            } catch {
                print("Failed to start AVAudioEngine: \(error.localizedDescription)")
                return
            }
        }

        let node = playerNodes[nextNodeIndex]
        nextNodeIndex = (nextNodeIndex + 1) % playerNodes.count

        node.volume = min(currentVolume, 1.0)
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying {
            node.play()
        }
    }

    private static func applyGain() {
        let clampedNodeVolume = min(currentVolume, 1.0)
        for node in playerNodes {
            node.volume = clampedNodeVolume
        }

        guard let eq = eqNode else { return }
        if currentVolume <= 0 {
            eq.globalGain = -96.0
        } else if currentVolume > 1.0 {
            eq.globalGain = min(24.0, 20.0 * log10(currentVolume))
        } else {
            eq.globalGain = 0.0
        }
    }

    private static func applyOutputDevice(_ outputDevice: OutputDevice) {
        guard let currentEngine = engine, let audioUnit = currentEngine.outputNode.audioUnit else {
            return
        }

        let targetDeviceID: AudioDeviceID?
        switch outputDevice {
        case .any:
            targetDeviceID = defaultOutputDeviceID()
        case .headphones:
            targetDeviceID = audioDeviceID(forUID: "BuiltInHeadphoneOutputDevice") ?? defaultOutputDeviceID()
        case .speaker:
            targetDeviceID = audioDeviceID(forUID: "BuiltInSpeakerDevice") ?? defaultOutputDeviceID()
        }

        guard var deviceID = targetDeviceID else { return }

        let wasRunning = currentEngine.isRunning
        if wasRunning {
            currentEngine.pause()
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("Failed to set output audio device (OSStatus \(status))")
        }

        if wasRunning {
            try? currentEngine.start()
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
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
            return nil
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &devices
        ) == noErr else {
            return nil
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for deviceID in devices {
            var unmanagedUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &unmanagedUID) { pointer in
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, pointer)
            }
            if status == noErr, let cfUID = unmanagedUID?.takeRetainedValue(), (cfUID as String) == uid {
                return deviceID
            }
        }

        return nil
    }
}
