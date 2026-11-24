//
//  SettingsView.swift
//  click
//
//  Created by Pablo Ruiz on 25/8/24.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.startMinimized) var startMinimized
    @Default(.showNotifications) var showNotifications

    private var cornerRadius: CGFloat {
        if #available(macOS 26, *) {
            10
        } else {
            5
        }
    }

    var body: some View {
        TabView {
            generalSettings()
            soundSettings()
            autoMuteSettings()
            shortcutsSettings()
        }
        .scenePadding()
        .frame(minWidth: 420, maxWidth: 460)
    }

    private func generalSettings() -> some View {
        VStack {
            VStack(spacing: 0) {
                SettingsToggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        appState.toggleLaunchAtLogin(newValue)
                    }
                Divider()
                    .padding(.horizontal, 8)
                SettingsToggle("Start Minimized", isOn: $startMinimized)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }

            VStack(spacing: 0) {
                SettingsToggle("Notifications", isOn: $showNotifications)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .toggleStyle(.switch)
        .tabItem {
            Label("General", systemImage: "gear")
        }
    }

    private func soundSettings() -> some View {
        VStack {
            VStack(spacing: 0) {
                SettingsToggle("Override volume presets", isOn: $appState.overrideVolume)
                Divider()
                    .padding(.horizontal, 8)
                SettingsSlider(
                    "Custom volume",
                    value: $appState.customVolume,
                    disabled: !appState.overrideVolume,
                    in: 0.5 ... 10,
                    step: 0.5,
                    leftIcon: "speaker.fill",
                    rightIcon: "speaker.wave.3.fill"
                )
                Divider()
                    .padding(.horizontal, 8)
                HStack {
                    Text("Output device")
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Picker("", selection: $appState.selectedOutputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(audioDevices.outputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .frame(maxWidth: 190)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 34)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }

            VStack(spacing: 0) {
                SettingsToggle("Subtle pitch & volume variation", isOn: $appState.enableSoundVariation)
                Divider()
                    .padding(.horizontal, 8)
                SettingsToggle("Key-up (release) sound", isOn: $appState.enableKeyUpSound)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .toggleStyle(.switch)
        .tabItem {
            Label("Sound", systemImage: "speaker.wave.2")
        }
    }

    private func autoMuteSettings() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                SettingsToggle("Mute while microphone is active", isOn: $appState.autoMuteOnMicrophone)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Excluded apps")
                    Spacer()
                    Button(action: addExcludedApp) {
                        Label("Add App", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 34)

                if appState.excludedApps.isEmpty {
                    Divider()
                        .padding(.horizontal, 8)
                    Text("Click will stay active in all apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(appState.excludedApps) { app in
                        Divider()
                            .padding(.horizontal, 8)
                        HStack {
                            Text(app.name)
                            Spacer()
                            Button(action: {
                                appState.excludedApps.removeAll { $0.id == app.id }
                            }, label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            })
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 30)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .toggleStyle(.switch)
        .tabItem {
            Label("Auto-Mute", systemImage: "speaker.slash")
        }
    }

    private func shortcutsSettings() -> some View {
        VStack {
            VStack(spacing: 0) {
                SettingsShortcutRecorder("Toggle Click", name: .toggle)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .tabItem {
            Label("Shortcuts", systemImage: "command")
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application to Auto-Mute"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let appURL = panel.url,
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier
        else {
            return
        }

        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        if !appState.excludedApps.contains(where: { $0.bundleIdentifier == bundleID }) {
            appState.excludedApps.append(ExcludedApp(bundleIdentifier: bundleID, name: appName))
            appState.excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
