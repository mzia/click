//
//  ContentView.swift
//  click
//
//  Created by Pablo Ruiz on 21/8/24.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var customPacks = CustomSoundpackManager.shared
    @State private var importErrorMessage: String?

    var body: some View {
        VStack {
            if !appState.permissionsGranted {
                PermissionsView()
            } else {
                HStack {
                    VStack {
                        Text("Click")
                            .font(.title.bold())
                            .padding()

                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Permissions granted")
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.secondary, lineWidth: 0.5)
                                .fill(.secondary.opacity(0.1))
                        )

                        Text("Choose your switch set")
                            .foregroundStyle(.secondary)
                            .padding(.top)

                        Button(action: importCustomPack) {
                            Label("Import Mechvibes Pack", systemImage: "folder.badge.plus")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .frame(minWidth: 225)
                    .padding()

                    Rectangle()
                        .frame(width: 1, height: 300)
                        .foregroundColor(.secondary.opacity(0.2))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Dictionary(grouping: Soundpack.allCases) { $0.soundpack?.manufacturer ?? "Other" }
                                .sorted(by: { $0.key < $1.key }), id: \.key) { manufacturer, soundpacks in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(manufacturer)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 8)
                                            .padding(.leading, 1)

                                        ForEach(soundpacks, id: \.self) { soundpack in
                                            let isSelected = appState.selectedCustomSoundpackID == nil
                                                && appState.soundpack == soundpack
                                            Button(action: {
                                                AudioManager.loadSoundPack(soundpack)
                                            }, label: {
                                                HStack {
                                                    Text(soundpack.soundpack?.name ?? soundpack.rawValue)
                                                        .font(.headline)
                                                    Spacer()
                                                    Button(action: {
                                                        AudioManager.previewSoundPack(soundpack)
                                                    }, label: {
                                                        HStack {
                                                            Image(systemName: "play.fill")
                                                            Text("Preview")
                                                        }
                                                        .font(.subheadline)
                                                        .padding(4)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .stroke(Color.secondary, lineWidth: 0.5)
                                                                .fill(.secondary.opacity(0.3))
                                                        )
                                                    })
                                                    .buttonStyle(.plain)
                                                }
                                                .padding()
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10.0)
                                                        .stroke(
                                                            isSelected ? Color.secondary : .clear,
                                                            lineWidth: 4
                                                        )
                                                        .stroke(Color.secondary, lineWidth: 1)
                                                        .fill(.ultraThickMaterial)
                                                )
                                            })
                                            .buttonStyle(.plain)
                                        }
                                        .animation(.default, value: appState.soundpack)
                                    }
                                }

                            if !customPacks.customPacks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Custom")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 1)

                                    ForEach(customPacks.customPacks) { pack in
                                        let isSelected = appState.selectedCustomSoundpackID == pack.id
                                        Button(action: {
                                            AudioManager.loadCustomSoundPack(pack)
                                        }, label: {
                                            HStack {
                                                Text(pack.name)
                                                    .font(.headline)
                                                Spacer()
                                                Button(action: {
                                                    AudioManager.previewCustomSoundPack(pack)
                                                }, label: {
                                                    HStack {
                                                        Image(systemName: "play.fill")
                                                        Text("Preview")
                                                    }
                                                    .font(.subheadline)
                                                    .padding(4)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.secondary, lineWidth: 0.5)
                                                            .fill(.secondary.opacity(0.3))
                                                    )
                                                })
                                                .buttonStyle(.plain)

                                                Button(action: {
                                                    deleteCustomPack(pack)
                                                }, label: {
                                                    Image(systemName: "trash")
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .padding(4)
                                                })
                                                .buttonStyle(.plain)
                                            }
                                            .padding()
                                            .background(
                                                RoundedRectangle(cornerRadius: 10.0)
                                                    .stroke(
                                                        isSelected ? Color.secondary : .clear,
                                                        lineWidth: 4
                                                    )
                                                    .stroke(Color.secondary, lineWidth: 1)
                                                    .fill(.ultraThickMaterial)
                                            )
                                        })
                                        .buttonStyle(.plain)
                                    }
                                    .animation(.default, value: appState.selectedCustomSoundpackID)
                                }
                            }
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
        }
        .padding([.horizontal, .bottom])
        .frame(width: 650, height: 400)
        .onAppear {
            appState.refreshPermissions()
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func importCustomPack() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Mechvibes Soundpack Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            let imported = try CustomSoundpackManager.shared.importSoundpack(from: folderURL)
            AudioManager.loadCustomSoundPack(imported)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func deleteCustomPack(_ pack: CustomSoundpackInfo) {
        let wasSelected = appState.selectedCustomSoundpackID == pack.id
        CustomSoundpackManager.shared.deleteCustomPack(pack)
        if wasSelected {
            AudioManager.loadSoundPack(appState.soundpack)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
