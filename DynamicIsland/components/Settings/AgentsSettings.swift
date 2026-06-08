//
//  AgentsSettings.swift
//  AllNotch
//
//  Settings ▸ Agents: enroll coding agents (install/uninstall their hooks) and
//  configure how the notch surfaces attention requests. Backed by the Open
//  Island bridge (https://github.com/Octane0411/open-vibe-island), GPL v3.
//

import Defaults
import OpenIslandCore
import SwiftUI

struct AgentsSettings: View {
    @ObservedObject private var enrollment = AgentEnrollmentService.shared

    @Default(.enableAgentsFeature) private var enableAgentsFeature
    @Default(.agentNotificationsEnabled) private var notificationsEnabled
    @Default(.agentSoundsEnabled) private var soundsEnabled
    @Default(.agentSoundName) private var soundName
    @Default(.agentAutoOpenNotch) private var autoOpenNotch

    /// Common macOS system sounds available under /System/Library/Sounds.
    private let systemSounds = [
        "Submarine", "Ping", "Glass", "Hero", "Blow",
        "Bottle", "Frog", "Funk", "Morse", "Pop", "Purr", "Sosumi", "Tink",
    ]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAgentsFeature) {
                    Text("Enable Agents")
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Monitor your AI coding agents from the notch: live session status, one-click jump-back, and inline approval of permission requests.")
            }

            if enableAgentsFeature {
                Section {
                    ForEach(AgentEnrollmentService.displayAgents, id: \.self) { agent in
                        AgentEnrollmentRow(agent: agent, enrollment: enrollment)
                    }
                } header: {
                    Text("Enrolled Agents")
                } footer: {
                    Text("Installing an agent adds AllNotch's hooks to its configuration so sessions appear here. Removing it cleans the hooks back out.\n\nAgents load hooks only when they start, so restart any already-running CLI session (quit and relaunch it) after enrolling. Gemini CLI reports session activity but has no permission hook, so its approval prompts can't be intercepted yet.")
                }

                Section {
                    Defaults.Toggle(key: .agentNotificationsEnabled) {
                        Text("Surface a notification in the notch")
                    }
                    Defaults.Toggle(key: .agentAutoOpenNotch) {
                        Text("Open the notch automatically when attention is needed")
                    }
                    .disabled(!notificationsEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("When an agent needs approval or an answer, AllNotch flashes a sneak-peek. Open the notch to approve, deny, or reply inline.")
                }

                Section {
                    Defaults.Toggle(key: .agentSoundsEnabled) {
                        Text("Play a sound on attention")
                    }
                    HStack {
                        Text("Sound")
                        Spacer()
                        Picker("", selection: $soundName) {
                            ForEach(systemSounds, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 130)
                        .disabled(!soundsEnabled)
                        Button {
                            AgentSoundPlayer.play(named: soundName)
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Preview sound")
                        .disabled(!soundsEnabled)
                    }
                } header: {
                    Text("Sound")
                }
            }
        }
        .onAppear { enrollment.refreshAll() }
    }
}

// MARK: - Per-agent row

private struct AgentEnrollmentRow: View {
    let agent: AgentIdentifier
    @ObservedObject var enrollment: AgentEnrollmentService

    var body: some View {
        HStack(spacing: 11) {
            AgentBadge(tool: tool, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(tool.displayName)
                    .font(.system(size: 13, weight: .medium))
                statusLabel
            }

            Spacer()

            control
        }
        .padding(.vertical, 2)
    }

    private var status: AgentEnrollmentStatus { enrollment.status(for: agent) }
    private var isBusy: Bool { enrollment.busyAgents.contains(agent) }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .notInstalled:
            Text("Detected — not enrolled")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .agentNotDetected:
            Text("Not installed on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var control: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
        } else {
            switch status {
            case .installed:
                Button("Remove", role: .destructive) {
                    enrollment.uninstall(agent)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .notInstalled, .agentNotDetected:
                Button("Install") {
                    enrollment.install(agent)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(status == .agentNotDetected)
            case .unavailable:
                EmptyView()
            }
        }
    }

    private var tool: AgentTool {
        switch agent {
        case .claudeCode: return .claudeCode
        case .codex: return .codex
        case .cursor: return .cursor
        case .gemini: return .geminiCLI
        case .openCode: return .openCode
        case .kimi: return .kimiCLI
        case .qoder: return .qoder
        case .qwenCode: return .qwenCode
        case .factory: return .factory
        case .codebuddy: return .codebuddy
        case .claudeUsageBridge: return .claudeCode
        }
    }
}
