//
//  MenuBarView.swift
//  click
//
//  Created by Pablo Ruiz on 25/8/24.
//

import SettingsAccess
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var customPacks = CustomSoundpackManager.shared

    var body: some View {
        Button {
            appState.toggle()
        } label: {
            if appState.isActive {
                Text("Disable Click")
            } else {
                Text("Enable Click")
            }
        }
        .disabled(!appState.permissionsGranted)
        .keyboardShortcut("K", modifiers: [.command, .shift])

        if appState.isActive, let reason = appState.autoMuteReason {
            Text("Auto-muted: \(reason.description)")
                .foregroundStyle(.secondary)
        }

        Divider()

        Picker(selection: $appState.volumePreset) {
            ForEach(VolumePreset.allCases, id: \.self) { volume in
                HStack {
                    Text(volume.rawValue.capitalized)
                }
                .tag(volume)
            }
        } label: {
            Image(systemName: "speaker.wave.2")
            Text("Volume")
        }

        Menu {
            ForEach(Soundpack.allCases, id: \.self) { soundpack in
                Button {
                    AudioManager.loadSoundPack(soundpack)
                } label: {
                    let isSelected = appState.selectedCustomSoundpackID == nil
                        && appState.soundpack == soundpack
                    if isSelected {
                        Label(soundpack.soundpack?.name ?? soundpack.rawValue, systemImage: "checkmark")
                    } else {
                        Text(soundpack.soundpack?.name ?? soundpack.rawValue)
                    }
                }
            }

            if !customPacks.customPacks.isEmpty {
                Divider()
                ForEach(customPacks.customPacks) { pack in
                    Button {
                        AudioManager.loadCustomSoundPack(pack)
                    } label: {
                        if appState.selectedCustomSoundpackID == pack.id {
                            Label(pack.name, systemImage: "checkmark")
                        } else {
                            Text(pack.name)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "circle.fill")
            Text("Soundpack")
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        } preAction: {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } postAction: {}
            .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit")
        }
        .keyboardShortcut("Q", modifiers: [.command])
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
