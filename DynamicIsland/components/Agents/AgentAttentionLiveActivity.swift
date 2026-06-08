//
//  AgentAttentionLiveActivity.swift
//  AllNotch
//
//  Closed-notch live activity shown only while an agent session needs the
//  user's attention (a permission to grant or a question to answer). It wraps
//  the physical notch: an attention glyph on the leading wing, the Open Island
//  "space invaders" agents grid on the trailing wing. Tapping opens the Agents
//  tab in the expanded notch.
//

import SwiftUI
import OpenIslandCore

struct AgentAttentionLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var bridge = AgentBridgeController.shared

    private let wingPadding: CGFloat = 16

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight)
    }

    var body: some View {
        if let cells = bridge.closedNotchAgentCells {
            content(cells: cells)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .allNotchOpenAgents, object: nil)
                }
        }
    }

    @ViewBuilder
    private func content(cells: [AgentGridCell]) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: leftWingWidth, height: notchContentHeight)
                .background(alignment: .leading) {
                    glyphSection
                        .padding(.leading, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width, height: notchContentHeight)

            Color.clear
                .frame(width: rightWingWidth(cells: cells), height: notchContentHeight)
                .background(alignment: .trailing) {
                    AgentsClosedGridView(cells: cells)
                        .padding(.trailing, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private var glyphSection: some View {
        let phase = topAttentionPhase
        let accent = accentColor(for: phase)
        let icon = phase == .waitingForApproval ? "exclamationmark.shield.fill" : "questionmark.bubble.fill"
        let diameter = max(notchContentHeight - 8, 22)

        return Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .symbolEffect(.pulse, options: .repeating)
            .frame(width: diameter, height: diameter)
            .frame(height: notchContentHeight, alignment: .center)
    }

    /// The phase of the highest-priority attention session, used to tint the
    /// leading glyph (approval = red-ish shield, answer = amber question).
    private var topAttentionPhase: SessionPhase {
        if bridge.sessions.contains(where: { $0.phase == .waitingForApproval }) {
            return .waitingForApproval
        }
        return .waitingForAnswer
    }

    private func accentColor(for phase: SessionPhase) -> Color {
        IslandDesignPalette.Status.tint(for: phase)
    }

    private var leftWingWidth: CGFloat {
        wingPadding + max(notchContentHeight - 8, 22)
    }

    private func rightWingWidth(cells: [AgentGridCell]) -> CGFloat {
        wingPadding + max(AgentsGridLayout.intrinsicWidth(cells), 16)
    }
}
