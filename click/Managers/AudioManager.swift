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

    private struct PlayerVoice {
        let player: AVAudioPlayerNode
        let timePitch: AVAudioUnitTimePitch
    }

    private static let playerPoolSize = 12
    private static let audioQueue = DispatchQueue(label: "com.pruizlezcano.click.audioQueue", qos: .userInteractive)
    private static let previewQueue = DispatchQueue(label: "com.pruizlezcano.click.previewQueue", qos: .userInitiated)

    private static var engine: AVAudioEngine?
    private static var eqNode: AVAudioUnitEQ?
    private static var voices: [PlayerVoice] = []
    private static var configuredFormat: AVAudioFormat?
    private static var nextVoiceIndex = 0

    private static var activePack: LoadedSoundpack?
    private static var decodedBuiltInCache: [Soundpack: LoadedSoundpack] = [:]
    private static var decodedCustomCache: [String: LoadedSoundpack] = [:]

    private static var currentVolume: Float = 1.0
    private static var currentOutputDeviceUID = ""
    private static var soundVariationEnabled = false
    private static var keyUpSoundEnabled = false
    private static var isAutoMuted = false

    private static var configObserver: NSObjectProtocol?
    private static var previewToken = UUID()

    static func updatePlaybackSettings(
        volume: Float,
        outputDeviceUID: String,
        enableSoundVariation: Bool,
        enableKeyUpSound: Bool
    ) {
        audioQueue.async {
            currentVolume = max(0, volume)
            let deviceChanged = currentOutputDeviceUID != outputDeviceUID
            currentOutputDeviceUID = outputDeviceUID
            soundVariationEnabled = enableSoundVariation
            keyUpSoundEnabled = enableKeyUpSound

            applyGain()
            if deviceChanged, engine != nil {
                applyOutputDevice(uid: outputDeviceUID)
            }
        }
    }

    static func setAutoMuted(_ muted: Bool) {
        audioQueue.async {
            isAutoMuted = muted
        }
    }

    static func invalidateCustomPackCache(id: String) {
        audioQueue.async {
            decodedCustomCache.removeValue(forKey: id)
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
                    if AppState.shared.selectedCustomSoundpackID != nil {
                        AppState.shared.selectedCustomSoundpackID = nil
                    }
                    if AppState.shared.soundpack != soundPack {
                        AppState.shared.soundpack = soundPack
                    }
                    Defaults[.soundpack] = soundPack
                    Defaults[.selectedCustomSoundpackID] = nil
                }
            }
        }
    }

    static func loadCustomSoundPack(_ customPack: CustomSoundpackInfo, saveState: Bool = true) {
        print("Loading custom soundpack: \(customPack.name)")

        loadBuffers(for: customPack) { loaded in
            guard let loaded else { return }

            audioQueue.async {
                activePack = loaded
                configureEngineIfNeeded(for: loaded.format)
                print("Custom soundpack loaded successfully")
            }

            if saveState {
                DispatchQueue.main.async {
                    if AppState.shared.selectedCustomSoundpackID != customPack.id {
                        AppState.shared.selectedCustomSoundpackID = customPack.id
                    }
                    Defaults[.selectedCustomSoundpackID] = customPack.id
                }
            }
        }
    }

    static func playSound(keyCode: UInt16) {
        audioQueue.async {
            guard !isAutoMuted, let pack = activePack else { return }
            playBuffer(for: keyCode, from: pack, isKeyUp: false)
        }
    }

    static func playKeyUpSound(keyCode: UInt16) {
        audioQueue.async {
            guard !isAutoMuted, keyUpSoundEnabled, let pack = activePack else { return }
            playBuffer(for: keyCode, from: pack, isKeyUp: true)
        }
    }

    static func previewSoundPack(_ soundPack: Soundpack) {
        let token = UUID()
        audioQueue.async {
            previewToken = token
        }

        loadBuffers(for: soundPack) { loaded in
            guard let loaded else { return }
            runPreviewSequence(using: loaded, token: token)
        }
    }

    static func previewCustomSoundPack(_ customPack: CustomSoundpackInfo) {
        let token = UUID()
        audioQueue.async {
            previewToken = token
        }

        loadBuffers(for: customPack) { loaded in
            guard let loaded else { return }
            runPreviewSequence(using: loaded, token: token)
        }
    }

    private static func runPreviewSequence(using loaded: LoadedSoundpack, token: UUID) {
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
                    playBuffer(for: keyCodes[index], from: loaded, isKeyUp: false)
                }
                Thread.sleep(forTimeInterval: waitTimes[index])
            }
        }
    }

    // MARK: - Decoding & Buffering

    private static func loadBuffers(for soundPack: Soundpack, completion: @escaping (LoadedSoundpack?) -> Void) {
        audioQueue.async {
            if let cached = decodedBuiltInCache[soundPack] {
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

            decodeAudioToReadableURL(soundURL) { decodedURL, shouldDelete in
                guard let decodedURL else {
                    completion(nil)
                    return
                }
                defer {
                    if shouldDelete {
                        try? FileManager.default.removeItem(at: decodedURL)
                    }
                }

                do {
                    let loaded = try buildSingleFileLoadedSoundpack(from: decodedURL, defines: soundpackData.defines)
                    audioQueue.async {
                        decodedBuiltInCache[soundPack] = loaded
                        completion(loaded)
                    }
                } catch {
                    print("Failed to build audio buffers: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }

    private static func loadBuffers(
        for customPack: CustomSoundpackInfo,
        completion: @escaping (LoadedSoundpack?) -> Void
    ) {
        audioQueue.async {
            if let cached = decodedCustomCache[customPack.id] {
                completion(cached)
                return
            }

            if let singleAudio = customPack.singleAudioFileName, let defines = customPack.defines {
                guard let audioURL = CustomSoundpackManager.shared.audioFileURL(for: customPack, fileName: singleAudio) else {
                    print("Custom soundpack audio not found: \(singleAudio)")
                    completion(nil)
                    return
                }

                decodeAudioToReadableURL(audioURL) { decodedURL, shouldDelete in
                    guard let decodedURL else {
                        completion(nil)
                        return
                    }
                    defer {
                        if shouldDelete {
                            try? FileManager.default.removeItem(at: decodedURL)
                        }
                    }

                    do {
                        let loaded = try buildSingleFileLoadedSoundpack(from: decodedURL, defines: defines)
                        audioQueue.async {
                            decodedCustomCache[customPack.id] = loaded
                            completion(loaded)
                        }
                    } catch {
                        print("Failed to build custom soundpack buffers: \(error.localizedDescription)")
                        completion(nil)
                    }
                }
                return
            }

            if let multiFiles = customPack.multiKeyAudioFiles {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let loaded = try buildMultiFileLoadedSoundpack(for: customPack, keyFiles: multiFiles)
                        audioQueue.async {
                            decodedCustomCache[customPack.id] = loaded
                            completion(loaded)
                        }
                    } catch {
                        print("Failed to build multi-file custom soundpack: \(error.localizedDescription)")
                        completion(nil)
                    }
                }
                return
            }

            completion(nil)
        }
    }

    private static func decodeAudioToReadableURL(
        _ sourceURL: URL,
        completion: @escaping (URL?, Bool) -> Void
    ) {
        if sourceURL.pathExtension.lowercased() == "ogg" {
            let decoder = OGGDecoder()
            decoder.decode(sourceURL) { savedWavUrl in
                if let savedWavUrl {
                    completion(savedWavUrl, true)
                } else {
                    print("Failed to decode OGG file: \(sourceURL.lastPathComponent)")
                    completion(nil, false)
                }
            }
        } else {
            completion(sourceURL, false)
        }
    }

    private static func decodeAudioSync(_ sourceURL: URL) -> (url: URL, shouldDelete: Bool)? {
        if sourceURL.pathExtension.lowercased() != "ogg" {
            return (sourceURL, false)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: URL?
        let decoder = OGGDecoder()
        decoder.decode(sourceURL) { savedWavUrl in
            result = savedWavUrl
            semaphore.signal()
        }
        semaphore.wait()
        guard let result else { return nil }
        return (result, true)
    }

    private static func buildSingleFileLoadedSoundpack(
        from audioURL: URL,
        defines: [String: [Int]?]
    ) throws -> LoadedSoundpack {
        let audioFile = try AVAudioFile(forReading: audioURL)
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

    private static func buildMultiFileLoadedSoundpack(
        for customPack: CustomSoundpackInfo,
        keyFiles: [String: String]
    ) throws -> LoadedSoundpack {
        let uniqueFileNames = Set(keyFiles.values)
        var fileBuffers: [String: AVAudioPCMBuffer] = [:]
        var targetFormat: AVAudioFormat?

        for fileName in uniqueFileNames {
            guard let sourceURL = CustomSoundpackManager.shared.audioFileURL(for: customPack, fileName: fileName),
                  let decoded = decodeAudioSync(sourceURL)
            else {
                continue
            }
            defer {
                if decoded.shouldDelete {
                    try? FileManager.default.removeItem(at: decoded.url)
                }
            }

            let audioFile = try AVAudioFile(forReading: decoded.url)
            let fileFormat = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount)
            else {
                continue
            }
            try audioFile.read(into: buffer)

            if targetFormat == nil {
                targetFormat = fileFormat
            }

            if let expected = targetFormat, fileFormat != expected {
                if let converted = convertBuffer(buffer, to: expected) {
                    fileBuffers[fileName] = converted
                }
            } else {
                fileBuffers[fileName] = buffer
            }
        }

        guard let format = targetFormat else {
            throw NSError(domain: "AudioManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No readable audio files in soundpack"])
        }

        var buffersByKey: [UInt16: AVAudioPCMBuffer] = [:]
        for (keyString, fileName) in keyFiles {
            guard let keyCode = UInt16(keyString), let buffer = fileBuffers[fileName] else { continue }
            buffersByKey[keyCode] = buffer
        }

        return LoadedSoundpack(format: format, buffers: buffersByKey)
    }

    private static func convertBuffer(_ source: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: source.format, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return source
        }
        return error == nil ? outputBuffer : nil
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

        var createdVoices: [PlayerVoice] = []
        createdVoices.reserveCapacity(playerPoolSize)
        for _ in 0 ..< playerPoolSize {
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()
            newEngine.attach(player)
            newEngine.attach(timePitch)
            newEngine.connect(player, to: timePitch, format: format)
            newEngine.connect(timePitch, to: packMixer, format: format)
            createdVoices.append(PlayerVoice(player: player, timePitch: timePitch))
        }

        engine = newEngine
        eqNode = eq
        voices = createdVoices
        configuredFormat = format
        nextVoiceIndex = 0

        applyOutputDevice(uid: currentOutputDeviceUID)
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
        for voice in voices {
            voice.player.stop()
        }
        engine?.stop()
        engine = nil
        eqNode = nil
        voices = []
        configuredFormat = nil
    }

    private static func playBuffer(for keyCode: UInt16, from pack: LoadedSoundpack, isKeyUp: Bool) {
        guard let buffer = pack.buffers[keyCode] else { return }

        configureEngineIfNeeded(for: pack.format)
        guard let currentEngine = engine, !voices.isEmpty else { return }

        if !currentEngine.isRunning {
            do {
                try currentEngine.start()
            } catch {
                print("Failed to start AVAudioEngine: \(error.localizedDescription)")
                return
            }
        }

        let voice = voices[nextVoiceIndex]
        nextVoiceIndex = (nextVoiceIndex + 1) % voices.count

        var baseVolume = min(currentVolume, 1.0)
        var pitchCents: Float = 0.0

        if isKeyUp {
            baseVolume *= 0.42
            pitchCents += 180.0
        }

        if soundVariationEnabled {
            baseVolume = min(1.0, max(0.0, baseVolume * Float.random(in: 0.92 ... 1.08)))
            pitchCents += Float.random(in: -35.0 ... 35.0)
        }

        voice.timePitch.pitch = pitchCents
        voice.player.volume = baseVolume
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.player.isPlaying {
            voice.player.play()
        }
    }

    private static func applyGain() {
        let clampedNodeVolume = min(currentVolume, 1.0)
        for voice in voices {
            voice.player.volume = clampedNodeVolume
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

    private static func applyOutputDevice(uid: String) {
        guard let currentEngine = engine, let audioUnit = currentEngine.outputNode.audioUnit else {
            return
        }

        let resolvedDeviceID = AudioDeviceManager.audioDeviceID(forUID: uid)
            ?? AudioDeviceManager.defaultOutputDeviceID()

        guard var deviceID = resolvedDeviceID else { return }

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
}
