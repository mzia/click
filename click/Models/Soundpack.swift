//
//  Soundpack.swift
//  click
//
//  Created by Pablo Ruiz on 21/8/24.
//

import AppIntents
import Defaults
import Foundation

struct SoundpackObject: Decodable {
    let name: String
    let manufacturer: String
    let defines: [String: [Int]?]
}

enum Soundpack: String, CaseIterable, Defaults.Serializable {
    case egCrystalPurple = "eg-crysyal-purple"
    case egOreo = "eg-oreo"
    case nkCream = "nk-cream"

    private static let cacheLock = NSLock()
    private static var cache: [Soundpack: SoundpackObject] = [:]

    var soundpack: SoundpackObject? {
        Self.cacheLock.lock()
        if let cached = Self.cache[self] {
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        guard let loaded = loadJSON(rawValue) else {
            return nil
        }

        Self.cacheLock.lock()
        Self.cache[self] = loaded
        Self.cacheLock.unlock()
        return loaded
    }

    func soundSlice(for keyCode: UInt16) -> (startMs: Int, durationMs: Int)? {
        guard
            let rawEntry = soundpack?.defines[String(keyCode)],
            let values = rawEntry,
            values.count >= 2,
            values[0] >= 0,
            values[1] > 0
        else {
            return nil
        }
        return (startMs: values[0], durationMs: values[1])
    }
}

private func loadJSON(_ soundpack: String) -> SoundpackObject? {
    guard let url = Bundle.main.url(forResource: soundpack, withExtension: "json") else {
        print("Failed to find URL for resource: \(soundpack).json")
        return nil
    }

    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let soundpackObject = try decoder.decode(SoundpackObject.self, from: data)
        return soundpackObject
    } catch {
        print("Failed to load or decode JSON: \(error.localizedDescription)")
        return nil
    }
}

extension Soundpack: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Soundpack")
    }

    static var caseDisplayRepresentations: [Soundpack: DisplayRepresentation] {
        [
            .egCrystalPurple: DisplayRepresentation(stringLiteral: "EG Crystal Purple"),
            .egOreo: DisplayRepresentation(stringLiteral: "EG Oreo"),
            .nkCream: DisplayRepresentation(stringLiteral: "NK Cream")
        ]
    }
}
