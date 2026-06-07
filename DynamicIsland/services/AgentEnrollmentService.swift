//
//  AgentEnrollmentService.swift
//  AllNotch
//
//  Single facade that normalises hook install / uninstall / status for every
//  agent the Open Island bridge (https://github.com/Octane0411/open-vibe-island,
//  GPL v3) supports. Each AgentIdentifier is routed to its concrete
//  installation manager; the tri-state user intent is persisted via
//  AgentIntentStore so an explicitly-uninstalled agent is never silently
//  reinstalled.
//

import Combine
import Foundation
import OpenIslandCore
import os

/// Resolved enrollment state for one agent, as shown in Settings.
enum AgentEnrollmentStatus: Equatable {
    /// The agent itself is not installed on this Mac (its config dir is absent).
    case agentNotDetected
    /// The agent is present but AllNotch's hooks are not installed.
    case notInstalled
    /// AllNotch's hooks are installed for this agent.
    case installed
    /// Hooks cannot be installed (e.g. helper binary missing from the bundle).
    case unavailable(String)
}

@MainActor
final class AgentEnrollmentService: ObservableObject {
    static let shared = AgentEnrollmentService()

    /// Agents exposed in the enrollment UI, in display order. Excludes the
    /// internal `claudeUsageBridge`.
    static let displayAgents: [AgentIdentifier] = [
        .claudeCode, .codex, .cursor, .gemini, .openCode,
        .kimi, .qoder, .qwenCode, .factory, .codebuddy,
    ]

    @Published private(set) var statuses: [AgentIdentifier: AgentEnrollmentStatus] = [:]
    @Published private(set) var busyAgents: Set<AgentIdentifier> = []
    @Published private(set) var lastError: String?

    private let intentStore = AgentIntentStore()
    private let logger = os.Logger(subsystem: "com.allnotch.agents", category: "Enrollment")

    private init() {}

    // MARK: - Bundled helper

    /// Path to the AgentHooks helper embedded in the app bundle.
    private var bundledHooksBinaryURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AgentHooks")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    // MARK: - Public API

    func refreshAll() {
        for agent in Self.displayAgents {
            statuses[agent] = resolveStatus(for: agent)
        }
    }

    func status(for agent: AgentIdentifier) -> AgentEnrollmentStatus {
        statuses[agent] ?? resolveStatus(for: agent)
    }

    func isInstalled(_ agent: AgentIdentifier) -> Bool {
        if case .installed = status(for: agent) { return true }
        return false
    }

    func install(_ agent: AgentIdentifier) {
        guard !busyAgents.contains(agent) else { return }
        guard let bundled = bundledHooksBinaryURL else {
            lastError = "AgentHooks helper not found in the app bundle."
            statuses[agent] = .unavailable(lastError!)
            return
        }
        run(agent) { adapter in
            try adapter.install(hooksBinaryURL: bundled)
        } onSuccess: { [weak self] in
            self?.intentStore.setIntent(.installed, for: agent)
        }
    }

    func uninstall(_ agent: AgentIdentifier) {
        guard !busyAgents.contains(agent) else { return }
        run(agent) { adapter in
            try adapter.uninstall()
        } onSuccess: { [weak self] in
            self?.intentStore.setIntent(.uninstalled, for: agent)
        }
    }

    // MARK: - Execution

    /// Runs a file-system mutation off the main actor (managers are
    /// `@unchecked Sendable`), then refreshes status back on the main actor.
    private func run(
        _ agent: AgentIdentifier,
        _ work: @escaping (AgentInstallAdapter) throws -> Void,
        onSuccess: @escaping () -> Void
    ) {
        guard let adapter = adapter(for: agent) else { return }
        busyAgents.insert(agent)
        lastError = nil
        Task.detached(priority: .userInitiated) {
            do {
                try work(adapter)
                await MainActor.run {
                    onSuccess()
                    self.busyAgents.remove(agent)
                    self.statuses[agent] = self.resolveStatus(for: agent)
                }
            } catch {
                await MainActor.run {
                    self.busyAgents.remove(agent)
                    self.lastError = error.localizedDescription
                    self.statuses[agent] = self.resolveStatus(for: agent)
                    self.logger.error("Enrollment \(agent.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Status resolution

    private func resolveStatus(for agent: AgentIdentifier) -> AgentEnrollmentStatus {
        guard bundledHooksBinaryURL != nil else {
            return .unavailable("AgentHooks helper missing from the app bundle.")
        }
        guard let adapter = adapter(for: agent) else {
            return .unavailable("Unsupported agent.")
        }
        let detected = adapter.isAgentDetectedOnDisk
        let installed = (try? adapter.isHookInstalled()) ?? false
        if installed { return .installed }
        return detected ? .notInstalled : .agentNotDetected
    }

    // MARK: - Adapter routing

    private func adapter(for agent: AgentIdentifier) -> AgentInstallAdapter? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch agent {
        case .claudeCode:
            return ClaudeForkAdapter(directory: ClaudeConfigDirectory.resolved(), hookSource: "claude")
        case .qoder:
            return ClaudeForkAdapter(directory: home.appendingPathComponent(".qoder", isDirectory: true), hookSource: "qoder")
        case .qwenCode:
            return ClaudeForkAdapter(directory: home.appendingPathComponent(".qwen", isDirectory: true), hookSource: "qwen")
        case .factory:
            return ClaudeForkAdapter(directory: home.appendingPathComponent(".factory", isDirectory: true), hookSource: "factory")
        case .codebuddy:
            return ClaudeForkAdapter(directory: home.appendingPathComponent(".codebuddy", isDirectory: true), hookSource: "codebuddy")
        case .codex:
            return CodexAdapter()
        case .cursor:
            return CursorAdapter()
        case .gemini:
            return GeminiAdapter()
        case .kimi:
            return KimiAdapter()
        case .openCode:
            return OpenCodeAdapter()
        case .claudeUsageBridge:
            return nil
        }
    }
}

// MARK: - Adapters

/// Uniform interface over the heterogeneous per-agent installation managers.
protocol AgentInstallAdapter {
    /// Whether the target agent itself is installed (its config dir exists).
    var isAgentDetectedOnDisk: Bool { get }
    func isHookInstalled() throws -> Bool
    func install(hooksBinaryURL: URL) throws
    func uninstall() throws
}

private func directoryExists(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}

/// Claude Code and every Claude-format fork (Qoder, Qwen, Factory, CodeBuddy):
/// same hook schema, distinct config directory + `--source` value.
private struct ClaudeForkAdapter: AgentInstallAdapter {
    let directory: URL
    let hookSource: String

    private var manager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager(claudeDirectory: directory, hookSource: hookSource)
    }

    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().managedHooksPresent }
    func install(hooksBinaryURL: URL) throws { try manager.install(hooksBinaryURL: hooksBinaryURL) }
    func uninstall() throws { try manager.uninstall() }
}

private struct CodexAdapter: AgentInstallAdapter {
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    private var manager: CodexHookInstallationManager { CodexHookInstallationManager() }
    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().managedHooksPresent }
    func install(hooksBinaryURL: URL) throws { try manager.install(hooksBinaryURL: hooksBinaryURL) }
    func uninstall() throws { try manager.uninstall() }
}

private struct CursorAdapter: AgentInstallAdapter {
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true)
    private var manager: CursorHookInstallationManager { CursorHookInstallationManager() }
    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().managedHooksPresent }
    func install(hooksBinaryURL: URL) throws { try manager.install(hooksBinaryURL: hooksBinaryURL) }
    func uninstall() throws { try manager.uninstall() }
}

private struct GeminiAdapter: AgentInstallAdapter {
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true)
    private var manager: GeminiHookInstallationManager { GeminiHookInstallationManager() }
    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().managedHooksPresent }
    func install(hooksBinaryURL: URL) throws { try manager.install(hooksBinaryURL: hooksBinaryURL) }
    func uninstall() throws { try manager.uninstall() }
}

private struct KimiAdapter: AgentInstallAdapter {
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi", isDirectory: true)
    private var manager: KimiHookInstallationManager { KimiHookInstallationManager() }
    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().managedHooksPresent }
    func install(hooksBinaryURL: URL) throws { try manager.install(hooksBinaryURL: hooksBinaryURL) }
    func uninstall() throws { try manager.uninstall() }
}

/// OpenCode is plugin-based (JS), not hook-binary-based; it ignores the helper
/// URL and installs the bundled plugin source instead.
private struct OpenCodeAdapter: AgentInstallAdapter {
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode", isDirectory: true)
    private var manager: OpenCodePluginInstallationManager { OpenCodePluginInstallationManager() }
    var isAgentDetectedOnDisk: Bool { directoryExists(directory) }
    func isHookInstalled() throws -> Bool { try manager.status().isInstalled }
    func install(hooksBinaryURL: URL) throws { try manager.install(pluginSourceData: OpenCodePluginSource.data()) }
    func uninstall() throws { try manager.uninstall() }
}
