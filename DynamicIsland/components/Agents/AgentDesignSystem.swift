//
//  AgentDesignSystem.swift
//  AllNotch
//
//  Design tokens (V6Palette, IslandDesignPalette) and a lightweight LanguageManager
//  adapted from Open Vibe Island (GPL v3) to keep code clean and localized.
//

import SwiftUI
import OpenIslandCore

enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }
}

enum V6Palette {
    static let ink = Color(red: 0x0d / 255.0, green: 0x0d / 255.0, blue: 0x0f / 255.0)
    static let paper = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
}

enum IslandDesignPalette {
    enum Status {
        static let waitingAggregate = Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0)
        static let waitingForApproval = Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0)
        static let waitingForAnswer = Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0)
        static let running = Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0)
        static let completed = Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0)
        static let inactive = V6Palette.paper.opacity(0.38)
        static let idle = V6Palette.paper.opacity(0.35)

        static func tint(for phase: SessionPhase) -> Color {
            switch phase {
            case .waitingForApproval:
                return waitingForApproval
            case .waitingForAnswer:
                return waitingForAnswer
            case .running:
                return running
            case .completed:
                return completed
            }
        }

        static func tint(for phase: SessionPhase, presence: IslandSessionPresence) -> Color {
            if phase == .waitingForApproval || phase == .waitingForAnswer {
                return tint(for: phase)
            }

            switch presence {
            case .running:
                return running
            case .active:
                return completed
            case .inactive:
                return inactive
            }
        }
    }
}

@Observable
final class LanguageManager: @unchecked Sendable {
    static let shared = LanguageManager()

    private let translationsEN: [String: String] = [
        "island.quit.confirmTitle": "Quit Session",
        "island.quit.confirmAction": "Quit",
        "settings.general.cancel": "Cancel",
        "island.quit.confirmMessage": "Are you sure you want to stop this agent session?",
        "island.hint.installHooks": "Install hooks in settings to link your agents",
        "island.checkingTerminals": "Checking terminal sessions...",
        "island.terminalOwnership": "Terminal Ownership",
        "island.noTerminals": "No active terminal found.",
        "island.startAgent": "Start an agent in your terminal.",
        "island.recentSessions": "Recent agent sessions",
        "island.showAll": "Show All (%d)",
        "island.sessionList.title": "Sessions",
        "island.sessionOverview.total": "Total",
        "island.sessionOverview.waiting": "Waiting",
        "island.sessionOverview.waitingCompact": "Waiting",
        "island.sessionOverview.running": "Running",
        "island.sessionOverview.runningCompact": "Running",
        "island.sessionOverview.done": "Done",
        "island.sessionOverview.idle": "Idle",
        "subagents.title": "%d subagents",
        "subagents.completed": "Completed",
        "approval.toolPermissionRequested": "Tool Permission Requested",
        "approval.deny": "Deny",
        "approval.allowOnce": "Allow Once",
        "approval.alwaysAllow": "Always Allow '%@'",
        "completion.done": "Done",
        "completion.replyPlaceholder": "Reply to %@...",
        "tasks.summary": "%d done, %d in progress, %d pending",
        "question.otherPlaceholder": "Type your answer...",
        "question.submit": "Submit",
        "question.answerNeeded": "Answer Needed",
        "question.sendReply": "Send Reply",
        "question.sendAnswer": "Send Answer",
        "question.next": "Next",
        "question.step": "Question %d / %d"
    ]

    private let translationsFR: [String: String] = [
        "island.quit.confirmTitle": "Quitter la session",
        "island.quit.confirmAction": "Quitter",
        "settings.general.cancel": "Annuler",
        "island.quit.confirmMessage": "Êtes-vous sûr de vouloir arrêter cette session d'agent ?",
        "island.hint.installHooks": "Installez les hooks dans les préférences pour lier vos agents",
        "island.checkingTerminals": "Vérification des sessions de terminal...",
        "island.terminalOwnership": "Propriété du terminal",
        "island.noTerminals": "Aucun terminal actif trouvé.",
        "island.startAgent": "Lancez un agent dans votre terminal.",
        "island.recentSessions": "Sessions d'agents récentes",
        "island.showAll": "Tout afficher (%d)",
        "island.sessionList.title": "Sessions",
        "island.sessionOverview.total": "Total",
        "island.sessionOverview.waiting": "En attente",
        "island.sessionOverview.waitingCompact": "Attente",
        "island.sessionOverview.running": "En cours",
        "island.sessionOverview.runningCompact": "En cours",
        "island.sessionOverview.done": "Terminé",
        "island.sessionOverview.idle": "Inactif",
        "subagents.title": "%d sous-agents",
        "subagents.completed": "Terminé",
        "approval.toolPermissionRequested": "Autorisation d'outil requise",
        "approval.deny": "Refuser",
        "approval.allowOnce": "Autoriser une fois",
        "approval.alwaysAllow": "Toujours autoriser '%@'",
        "completion.done": "Terminé",
        "completion.replyPlaceholder": "Répondre à %@...",
        "tasks.summary": "%d terminées, %d en cours, %d en attente",
        "question.otherPlaceholder": "Saisissez votre réponse...",
        "question.submit": "Envoyer",
        "question.answerNeeded": "Réponse requise",
        "question.sendReply": "Envoyer la réponse",
        "question.sendAnswer": "Envoyer la réponse",
        "question.next": "Suivant",
        "question.step": "Question %d / %d"
    ]

    private var useFrench: Bool {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr")
    }

    func t(_ key: String) -> String {
        let dict = useFrench ? translationsFR : translationsEN
        return dict[key] ?? key
    }

    func t(_ key: String, _ args: any CVarArg...) -> String {
        let format = t(key)
        return String(format: format, arguments: args)
    }
}

struct AgentBadge: View {
    let tool: AgentTool
    var size: CGFloat = 30

    var body: some View {
        Text(tool.shortName)
            .font(.system(size: size * 0.3, weight: .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(Color(agentHex: tool.brandColorHex) ?? .gray)
            )
    }
}

extension Color {
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

extension AttributedString {
    static func agentInline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

