//
//  AgentBridgeController.swift
//  AllNotch
//
//  In-app glue for the agent bridge grafted from Open Island
//  (https://github.com/Octane0411/open-vibe-island), GPL v3.
//
//  Owns the local BridgeServer (Unix-socket listener that AllNotchHooks
//  CLI processes connect to) and an observer LocalBridgeClient that streams
//  AgentEvents back into an observable SessionState for the Agents tab.
//

import AppKit
import Combine
import Defaults
import Foundation
import OpenIslandCore
import SwiftUI
import os

extension Notification.Name {
    /// Posted when an agent needs attention and the user has opted into
    /// auto-opening the notch. Observed by the notch view to surface the
    /// Agents tab.
    static let allNotchOpenAgents = Notification.Name("AllNotchOpenAgents")
}

@MainActor
final class AgentBridgeController: ObservableObject {
    static let shared = AgentBridgeController()

    /// Live sessions, ordered for display: attention-needed first, then
    /// running, then most-recently-updated.
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var isBridgeReady = false
    @Published private(set) var statusMessage = "Bridge not started."

    private let bridgeServer = BridgeServer()
    private var bridgeClient = LocalBridgeClient()
    private let commandClient = BridgeCommandClient()
    private var state = SessionState()

    /// Session ids currently surfaced as needing attention, so we only fire a
    /// notification on the *transition* into an attention phase, not on every
    /// subsequent event for the same request.
    private var attentionSessionIDs: Set<String> = []

    private var observerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var didStart = false

    private static let reconnectDelay: Duration = .seconds(2)
    private let logger = os.Logger(subsystem: "com.allnotch.agents", category: "AgentBridge")

    private init() {}

    // MARK: - Lifecycle

    /// Starts the bridge server and observer. Safe to call repeatedly.
    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        // Keep the installed hooks helper in sync with the bundled one, so an
        // app update refreshes a stale/broken binary without a manual reinstall.
        if let bundled = bundledHooksBinaryURL {
            try? ManagedHooksBinary.updateIfNeeded(from: bundled)
        }

        do {
            try bridgeServer.start()
            statusMessage = "Bridge ready. Waiting for agent hook events."
            connectObserver()
        } catch {
            isBridgeReady = false
            statusMessage = "Failed to start bridge: \(error.localizedDescription)"
            logger.error("Bridge start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        observerTask?.cancel()
        reconnectTask?.cancel()
        observerTask = nil
        reconnectTask = nil
        bridgeClient.disconnect()
        bridgeServer.stop()
        didStart = false
        isBridgeReady = false
    }

    // MARK: - Observer connection

    private func connectObserver() {
        observerTask?.cancel()
        reconnectTask?.cancel()
        bridgeClient.disconnect()

        // Fresh client per attempt so we never reuse a stale file descriptor.
        let client = LocalBridgeClient()
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            isBridgeReady = false
            statusMessage = "Bridge connect failed: \(error.localizedDescription)"
            scheduleReconnect()
            return
        }

        observerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.send(.registerClient(role: .observer))
                await MainActor.run {
                    self.isBridgeReady = true
                    self.statusMessage = "Bridge ready. Waiting for agent hook events."
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isBridgeReady = false
                    self.statusMessage = "Bridge registration failed: \(error.localizedDescription)"
                }
                self.scheduleReconnect()
                return
            }

            do {
                for try await event in stream {
                    await self.apply(event)
                }
                // Stream ended cleanly (server closed); try to reconnect.
                if !Task.isCancelled { self.scheduleReconnect() }
            } catch {
                if !Task.isCancelled { self.scheduleReconnect() }
            }
        }
    }

    private func scheduleReconnect() {
        guard didStart else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: AgentBridgeController.reconnectDelay)
            guard let self, !Task.isCancelled, self.didStart else { return }
            await MainActor.run { self.connectObserver() }
        }
    }

    // MARK: - Event application

    private func apply(_ event: AgentEvent) {
        state.apply(event)
        bridgeServer.updateStateSnapshot(state)
        sessions = sortedSessions(state.sessions)
        reconcileAttention()
    }

    /// Fires a notification (sneak-peek + sound + optional auto-open) the first
    /// time a session enters an attention-needed phase, and clears tracking
    /// once it no longer needs attention.
    private func reconcileAttention() {
        let current = Set(sessions.filter { $0.phase.requiresAttention }.map(\.id))
        let newlyNeedingAttention = current.subtracting(attentionSessionIDs)
        attentionSessionIDs = current

        guard !newlyNeedingAttention.isEmpty else { return }
        for id in newlyNeedingAttention {
            guard let session = sessions.first(where: { $0.id == id }) else { continue }
            presentAttention(for: session)
        }
    }

    private func presentAttention(for session: AgentSession) {
        let accent = Color(agentHex: session.tool.brandColorHex) ?? .orange
        let icon = session.phase == .waitingForApproval ? "exclamationmark.shield.fill" : "questionmark.bubble.fill"

        if Defaults[.agentNotificationsEnabled] {
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .agentAttention,
                duration: 4,
                icon: icon,
                title: session.tool.displayName,
                subtitle: session.phase.displayName,
                accentColor: accent
            )
        }

        if Defaults[.agentSoundsEnabled] {
            AgentSoundPlayer.play(named: Defaults[.agentSoundName])
        }

        if Defaults[.agentAutoOpenNotch] {
            NotificationCenter.default.post(name: .allNotchOpenAgents, object: nil)
        }
    }

    private func sortedSessions(_ input: [AgentSession]) -> [AgentSession] {
        input.sorted { lhs, rhs in
            let lp = priority(for: lhs.phase)
            let rp = priority(for: rhs.phase)
            if lp != rp { return lp < rp }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func priority(for phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .waitingForAnswer: return 0
        case .running: return 1
        case .completed: return 2
        }
    }

    // MARK: - Jump back

    /// Brings the terminal/IDE that owns this session to the front.
    func jumpBack(to session: AgentSession) {
        guard let target = session.jumpTarget else {
            statusMessage = "No jump target available for this session yet."
            return
        }
        do {
            _ = try TerminalJumpService().jump(to: target)
        } catch {
            statusMessage = "Jump back failed: \(error.localizedDescription)"
            logger.error("Jump back failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Interactive permissions

    /// Resolves a pending permission request by replying to the held hook
    /// process over the bridge socket. The send is blocking, so it runs off the
    /// main actor.
    func resolve(_ session: AgentSession, _ action: ApprovalAction) {
        let resolution: PermissionResolution
        switch action {
        case .deny:
            resolution = .deny()
        case .allowOnce:
            resolution = .allowOnce()
        case let .allowWithUpdates(updates):
            resolution = .allowOnce(updatedPermissions: updates)
        }
        sendCommand(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            failureContext: "Approval"
        )
    }

    /// Answers a pending structured question for the session.
    func answer(_ session: AgentSession, _ response: QuestionPromptResponse) {
        sendCommand(
            .answerQuestion(sessionID: session.id, response: response),
            failureContext: "Answer"
        )
    }

    private func sendCommand(_ command: BridgeCommand, failureContext: String) {
        let client = commandClient
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                _ = try client.send(command)
            } catch {
                await MainActor.run {
                    self?.statusMessage = "\(failureContext) failed: \(error.localizedDescription)"
                    self?.logger.error("\(failureContext, privacy: .public) command failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Bundled helper

    /// Path to the AgentHooks helper embedded in the app bundle. Used to keep
    /// the installed copy fresh on launch (enrollment itself lives in
    /// `AgentEnrollmentService`).
    private var bundledHooksBinaryURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/AgentHooks")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}

// MARK: - Sound

/// Plays a named macOS system sound for agent attention events.
enum AgentSoundPlayer {
    static func play(named name: String) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}

private extension Color {
    /// Hex initializer for agent brand colors (e.g. "#RRGGBB").
    init?(agentHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
