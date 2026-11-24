//
//  ContentView.swift
//  click
//
//  Created by Pablo Ruiz on 21/8/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

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
                    }
                    .frame(minWidth: 225)
                    .padding()

                    Rectangle()
                        .frame(width: 1, height: 300)
                        .foregroundColor(.secondary.opacity(0.2))

                    VStack {
                        ForEach(Dictionary(grouping: Soundpack.allCases) { $0.soundpack?.manufacturer ?? "Other" }
                            .sorted(by: { $0.key < $1.key }), id: \.key) { manufacturer, soundpacks in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(manufacturer)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 1) // Visual adjustment

                                    ForEach(soundpacks, id: \.self) { soundpack in
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
                                                        appState.soundpack == soundpack ? Color.secondary : .clear,
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
                    }
                    .padding()

                    Spacer()
                }
            }
        }
        .padding([.horizontal, .bottom])
        .frame(width: 650, height: 400)
        .onAppear {
            appState.refreshPermissions()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
