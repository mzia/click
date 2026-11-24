//
//  CustomSoundpackManager.swift
//  click
//
//  Created for Click fork enhancements.
//

import Defaults
import Foundation

struct CustomSoundpackInfo: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: String
    let name: String
    let manufacturer: String
    let singleAudioFileName: String?
    let defines: [String: [Int]?]?
    let multiKeyAudioFiles: [String: String]?
}

enum CustomSoundpackError: LocalizedError {
    case missingConfig
    case invalidConfig(String)
    case missingAudioFile(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            "No config.json (or Click soundpack JSON) found in the selected folder."
        case let .invalidConfig(reason):
            "Invalid soundpack configuration: \(reason)"
        case let .missingAudioFile(file):
            "Referenced audio file not found: \(file)"
        case let .unsafePath(path):
            "Rejected unsafe file path: \(path)"
        }
    }
}

class CustomSoundpackManager: ObservableObject {
    static let shared = CustomSoundpackManager()

    @Published private(set) var customPacks: [CustomSoundpackInfo] = []

    private let fileManager = FileManager.default

    private static let allowedIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    // Mechvibes (libuiohook) scan code -> macOS CGKeyCode mapping
    private static let mechvibesToMacKeyCode: [String: String] = [
        "1": "53", "59": "122", "60": "120", "61": "99", "62": "118",
        "63": "96", "64": "97", "65": "98", "66": "100", "67": "101",
        "68": "109", "87": "103", "88": "111", "91": "105", "92": "107",
        "93": "113", "94": "106", "95": "64", "96": "79", "97": "80",
        "41": "50", "2": "18", "3": "19", "4": "20", "5": "21",
        "6": "23", "7": "22", "8": "26", "9": "28", "10": "25",
        "11": "29", "12": "27", "13": "24", "14": "51", "15": "48",
        "58": "57", "30": "0", "48": "11", "46": "8", "32": "2",
        "18": "14", "33": "3", "34": "5", "35": "4", "23": "34",
        "36": "38", "37": "40", "38": "37", "50": "46", "49": "45",
        "24": "31", "25": "35", "16": "12", "19": "15", "31": "1",
        "20": "17", "22": "32", "47": "9", "17": "13", "45": "7",
        "21": "16", "44": "6", "26": "33", "27": "30", "43": "42",
        "39": "41", "40": "39", "28": "36", "51": "43", "52": "47",
        "53": "44", "57": "49", "3639": "105", "70": "107", "3653": "113",
        "3666": "114", "3667": "117", "3655": "115", "3663": "119",
        "3657": "116", "3665": "121", "57416": "126", "57419": "123",
        "57421": "124", "57424": "125", "42": "56", "54": "60", "29": "59",
        "3613": "62", "56": "58", "3640": "61", "3675": "55", "3676": "54",
        "3677": "110", "69": "71", "3637": "75", "55": "67", "74": "78",
        "3597": "81", "78": "69", "3612": "76", "83": "65", "79": "83",
        "80": "84", "81": "85", "75": "86", "76": "87", "77": "88",
        "71": "89", "72": "91", "73": "92", "82": "82"
    ]

    init() {
        reloadPacks()
    }

    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Click", isDirectory: true)
            .appendingPathComponent("CustomSoundpacks", isDirectory: true)
    }

    func reloadPacks() {
        let base = baseDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            DispatchQueue.main.async {
                self.customPacks = []
            }
            return
        }

        var loaded: [CustomSoundpackInfo] = []
        let decoder = JSONDecoder()
        for entry in entries {
            let metadataURL = entry.appendingPathComponent("click-pack.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let info = try? decoder.decode(CustomSoundpackInfo.self, from: data),
                  Self.isSafeIdentifier(info.id)
            else {
                continue
            }
            loaded.append(info)
        }

        loaded.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async {
            self.customPacks = loaded
        }
    }

    func pack(withID id: String) -> CustomSoundpackInfo? {
        customPacks.first(where: { $0.id == id })
    }

    func audioFileURL(for pack: CustomSoundpackInfo, fileName: String) -> URL? {
        guard Self.isSafeIdentifier(pack.id), Self.isSafeFileName(fileName) else {
            return nil
        }
        let packDir = baseDirectory.appendingPathComponent(pack.id, isDirectory: true).standardizedFileURL
        let fileURL = packDir.appendingPathComponent(fileName).standardizedFileURL
        guard fileURL.path.hasPrefix(packDir.path + "/") else {
            return nil
        }
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    @discardableResult
    func importSoundpack(from folderURL: URL) throws -> CustomSoundpackInfo {
        let standardizedFolder = folderURL.standardizedFileURL
        let configURL = try locateConfigFile(in: standardizedFolder)
        let rawData = try Data(contentsOf: configURL)

        guard let json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            throw CustomSoundpackError.invalidConfig("Root JSON must be an object.")
        }

        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let packName = name, !packName.isEmpty else {
            throw CustomSoundpackError.invalidConfig("Missing soundpack name.")
        }

        let isMechvibes = json["key_define_type"] != nil
        let keyDefineType = (json["key_define_type"] as? String) ?? "single"
        let manufacturer = (json["manufacturer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedManufacturer = (manufacturer?.isEmpty == false ? manufacturer! : "Custom")

        guard let rawDefines = json["defines"] as? [String: Any], !rawDefines.isEmpty else {
            throw CustomSoundpackError.invalidConfig("Missing 'defines' key mapping.")
        }

        let packID = UUID().uuidString.lowercased()
        let destinationDir = baseDirectory.appendingPathComponent(packID, isDirectory: true).standardizedFileURL
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let info: CustomSoundpackInfo
        do {
            if isMechvibes && keyDefineType == "multi" {
                info = try importMultiFilePack(
                    packID: packID,
                    name: packName,
                    manufacturer: resolvedManufacturer,
                    rawDefines: rawDefines,
                    sourceFolder: standardizedFolder,
                    destinationDir: destinationDir
                )
            } else {
                let declaredSound = json["sound"] as? String
                info = try importSingleFilePack(
                    packID: packID,
                    name: packName,
                    manufacturer: resolvedManufacturer,
                    isMechvibes: isMechvibes,
                    declaredSoundFile: declaredSound,
                    rawDefines: rawDefines,
                    sourceFolder: standardizedFolder,
                    destinationDir: destinationDir
                )
            }

            let encoded = try JSONEncoder().encode(info)
            try encoded.write(to: destinationDir.appendingPathComponent("click-pack.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: destinationDir)
            throw error
        }

        reloadPacks()
        return info
    }

    func deleteCustomPack(_ pack: CustomSoundpackInfo) {
        guard Self.isSafeIdentifier(pack.id) else { return }
        let base = baseDirectory.standardizedFileURL
        let target = base.appendingPathComponent(pack.id, isDirectory: true).standardizedFileURL
        guard target.path.hasPrefix(base.path + "/") else { return }

        try? fileManager.removeItem(at: target)
        AudioManager.invalidateCustomPackCache(id: pack.id)
        reloadPacks()
    }

    // MARK: - Private Helpers

    private func locateConfigFile(in folderURL: URL) throws -> URL {
        let mechvibesConfig = folderURL.appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: mechvibesConfig.path) {
            return mechvibesConfig
        }

        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        if let jsonFile = contents.first(where: { $0.pathExtension.lowercased() == "json" }) {
            return jsonFile
        }
        throw CustomSoundpackError.missingConfig
    }

    private func importSingleFilePack(
        packID: String,
        name: String,
        manufacturer: String,
        isMechvibes: Bool,
        declaredSoundFile: String?,
        rawDefines: [String: Any],
        sourceFolder: URL,
        destinationDir: URL
    ) throws -> CustomSoundpackInfo {
        let sourceAudioURL: URL
        if let declared = declaredSoundFile, !declared.isEmpty {
            sourceAudioURL = try resolveSafeSourceFile(declared, inside: sourceFolder)
        } else {
            let contents = (try? fileManager.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)) ?? []
            let supportedExts: Set<String> = ["ogg", "wav", "mp3", "m4a", "caf"]
            guard let found = contents.first(where: { supportedExts.contains($0.pathExtension.lowercased()) }) else {
                throw CustomSoundpackError.missingAudioFile("sound.ogg / sound.wav")
            }
            sourceAudioURL = found
        }

        let audioFileName = sourceAudioURL.lastPathComponent
        guard Self.isSafeFileName(audioFileName) else {
            throw CustomSoundpackError.unsafePath(audioFileName)
        }
        try fileManager.copyItem(at: sourceAudioURL, to: destinationDir.appendingPathComponent(audioFileName))

        var mappedDefines: [String: [Int]?] = [:]
        for (rawKey, rawValue) in rawDefines {
            let targetKey = isMechvibes ? Self.mechvibesToMacKeyCode[rawKey] : rawKey
            guard let macKey = targetKey else { continue }
            if let ints = rawValue as? [Int], ints.count >= 2 {
                mappedDefines[macKey] = ints
            } else if let nums = rawValue as? [NSNumber], nums.count >= 2 {
                mappedDefines[macKey] = nums.map { $0.intValue }
            }
        }

        guard !mappedDefines.isEmpty else {
            throw CustomSoundpackError.invalidConfig("No valid key definitions were mapped.")
        }

        return CustomSoundpackInfo(
            id: packID,
            name: name,
            manufacturer: manufacturer,
            singleAudioFileName: audioFileName,
            defines: mappedDefines,
            multiKeyAudioFiles: nil
        )
    }

    private func importMultiFilePack(
        packID: String,
        name: String,
        manufacturer: String,
        rawDefines: [String: Any],
        sourceFolder: URL,
        destinationDir: URL
    ) throws -> CustomSoundpackInfo {
        var mappedKeyFiles: [String: String] = [:]
        var copiedFiles: Set<String> = []

        for (rawKey, rawValue) in rawDefines {
            guard
                let macKey = Self.mechvibesToMacKeyCode[rawKey],
                let relativeFile = rawValue as? String,
                !relativeFile.isEmpty
            else {
                continue
            }

            let sourceAudioURL = try resolveSafeSourceFile(relativeFile, inside: sourceFolder)
            let safeFileName = sourceAudioURL.lastPathComponent
            guard Self.isSafeFileName(safeFileName) else {
                throw CustomSoundpackError.unsafePath(safeFileName)
            }

            if !copiedFiles.contains(safeFileName) {
                let dst = destinationDir.appendingPathComponent(safeFileName)
                if !fileManager.fileExists(atPath: dst.path) {
                    try fileManager.copyItem(at: sourceAudioURL, to: dst)
                }
                copiedFiles.insert(safeFileName)
            }

            mappedKeyFiles[macKey] = safeFileName
        }

        guard !mappedKeyFiles.isEmpty else {
            throw CustomSoundpackError.invalidConfig("No valid audio key mappings found.")
        }

        return CustomSoundpackInfo(
            id: packID,
            name: name,
            manufacturer: manufacturer,
            singleAudioFileName: nil,
            defines: nil,
            multiKeyAudioFiles: mappedKeyFiles
        )
    }

    private func resolveSafeSourceFile(_ relativeName: String, inside folderURL: URL) throws -> URL {
        guard !relativeName.contains(".."), !relativeName.hasPrefix("/") else {
            throw CustomSoundpackError.unsafePath(relativeName)
        }
        let candidate = folderURL.appendingPathComponent(relativeName).standardizedFileURL
        guard candidate.path.hasPrefix(folderURL.path + "/") else {
            throw CustomSoundpackError.unsafePath(relativeName)
        }
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw CustomSoundpackError.missingAudioFile(relativeName)
        }
        return candidate
    }

    private static func isSafeIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
    }
}
