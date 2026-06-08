//
//  AgentsTabView.swift
//  AllNotch
//
//  Agents tab: live agent sessions delivered by the Open Island bridge
//  (https://github.com/Octane0411/open-vibe-island), GPL v3, rendered in
//  AllNotch's notch panel. Sessions needing attention show an interactive
//  approval card; the rest show a compact summary row. Hook enrollment lives
//  in Settings ▸ Agents.
//

import OpenIslandCore
import SwiftUI

struct AgentsTabView: View {
    @ObservedObject private var bridge = AgentBridgeController.shared

    var body: some View {
        Group {
            if bridge.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(bridge.sessions) { session in
                            if session.phase.requiresAttention {
                                AgentNotificationCard(session: session, bridge: bridge)
                            } else {
                                AgentSessionCompactRow(session: session) {
                                    bridge.jumpBack(to: session)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { bridge.startIfNeeded() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("No active agent sessions")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Text(bridge.statusMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            Text("Enroll your coding agents in Settings ▸ Agents.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
