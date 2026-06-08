//
//  AgentsTabView.swift
//  AllNotch
//
//  Agents tab: live agent sessions delivered by the Open Island bridge
//  (https://github.com/Octane0411/open-vibe-island), GPL v3, rendered in
//  AllNotch's notch panel using a ported, feature-complete IslandSessionRow.
//

import OpenIslandCore
import SwiftUI

/// Intrinsic height of the agent session list, measured behind the ScrollView's
/// content so it is independent of the panel/container height (no feedback loop).
private struct AgentsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AgentsTabView: View {
    @ObservedObject private var bridge = AgentBridgeController.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel

    /// Last measured intrinsic content height, retained so a panel-region resize
    /// can recompute the desired height even when the content itself is unchanged.
    @State private var lastContentHeight: CGFloat = 0

    /// Token + flag for suppressing the close-on-scroll gesture while the cursor
    /// is over the (scrollable) session list, mirroring Notes/Terminal. Without
    /// this, scrolling the list is read as a close gesture and dismisses the notch.
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        GeometryReader { region in
            Group {
                if bridge.sessions.isEmpty {
                    emptyState
                        .onAppear { bridge.desiredPanelHeight = 0 }
                } else {
                    sessionsList(regionHeight: region.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: bridge.sessions.isEmpty) { _, isEmpty in
                if isEmpty {
                    bridge.desiredPanelHeight = 0
                    updateSuppression(for: false)
                }
            }
            .onChange(of: region.size.height) { _, height in
                guard !bridge.sessions.isEmpty else { return }
                updateDesiredHeight(contentHeight: lastContentHeight, regionHeight: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { updateSuppression(for: $0) }
        .onAppear { bridge.startIfNeeded() }
        .onDisappear { updateSuppression(for: false) }
    }

    /// Suppress / restore the notch's close-on-scroll gesture while hovering the
    /// scrollable session list, so two-finger scrolling pans the list instead of
    /// closing the notch.
    private func updateSuppression(for hovering: Bool) {
        let shouldSuppress = hovering && !bridge.sessions.isEmpty
        guard shouldSuppress != isSuppressing else { return }
        isSuppressing = shouldSuppress
        vm.setScrollGestureSuppression(shouldSuppress, token: suppressionToken)
    }

    private func sessionsList(regionHeight: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 10)) { timelineContext in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(bridge.sessions) { session in
                        IslandSessionRow(
                            session: session,
                            referenceDate: timelineContext.date,
                            stateIndicator: .animatedDot,
                            isActionable: session.phase.requiresAttention,
                            isInteractive: true,
                            presentation: .list,
                            sideInset: 16,
                            lang: .shared,
                            onApprove: { bridge.resolve(session, $0) },
                            onAnswer: { bridge.answer(session, $0) },
                            onReply: TerminalTextSender.canReply(to: session, enabled: true)
                                ? { text in
                                    Task {
                                        await Task.detached(priority: .userInitiated) {
                                            TerminalTextSender.send(text, to: session)
                                        }.value
                                    }
                                } : nil,
                            onJump: { bridge.jumpBack(to: session) },
                            onDismiss: { bridge.dismiss(session) }
                        )
                    }
                }
                .padding(.vertical, 4)
                .background(
                    GeometryReader { content in
                        Color.clear.preference(
                            key: AgentsContentHeightKey.self,
                            value: content.size.height
                        )
                    }
                )
            }
            .onPreferenceChange(AgentsContentHeightKey.self) { contentHeight in
                lastContentHeight = contentHeight
                updateDesiredHeight(contentHeight: contentHeight, regionHeight: regionHeight)
            }
        }
    }

    /// Converts the measured intrinsic content height into a desired panel height.
    ///
    /// The panel chrome (header + tab bar + paddings above/below the tab content)
    /// is self-calibrated as `notchSize.height - regionHeight`, which is invariant,
    /// so this converges without oscillation. The plugin clamps the result to the
    /// base height and the screen cap.
    private func updateDesiredHeight(contentHeight: CGFloat, regionHeight: CGFloat) {
        guard contentHeight > 0, regionHeight > 0 else { return }
        let chrome = max(0, vm.notchSize.height - regionHeight)
        let desired = (contentHeight + chrome).rounded()
        if abs(desired - bridge.desiredPanelHeight) > 4 {
            bridge.desiredPanelHeight = desired
        }
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
