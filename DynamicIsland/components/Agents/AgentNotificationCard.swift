//
//  AgentNotificationCard.swift
//  AllNotch
//
//  Reusable, interactive cards for agent sessions surfaced by the Open Island
//  bridge (https://github.com/Octane0411/open-vibe-island, GPL v3). The
//  attention card lets the user approve / deny / answer a request directly from
//  the notch; the compact row summarises running and completed sessions.
//

import OpenIslandCore
import SwiftUI

// MARK: - Shared pieces

/// Brand color for an agent, resolved from its hex palette.
enum AgentBrandColor {
    static func color(for tool: AgentTool) -> Color {
        Color(agentHex: tool.brandColorHex) ?? .gray
    }
}

private extension Color {
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

/// Square brand badge with the agent's short name.
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
                    .fill(AgentBrandColor.color(for: tool).gradient)
            )
    }
}

/// Small pill showing the session phase.
struct AgentPhaseChip: View {
    let phase: SessionPhase

    var body: some View {
        Text(phase.displayName.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint))
    }

    private var tint: Color {
        switch phase {
        case .waitingForApproval: return Color(red: 0.98, green: 0.66, blue: 0.62)
        case .waitingForAnswer: return Color(red: 1.0, green: 0.84, blue: 0.54)
        case .running: return Color(red: 0.45, green: 0.66, blue: 1.0)
        case .completed: return Color(red: 0.46, green: 0.75, blue: 0.53)
        }
    }
}

// MARK: - Interactive attention card

struct AgentNotificationCard: View {
    let session: AgentSession
    @ObservedObject var bridge: AgentBridgeController

    @State private var freeformAnswer: String = ""

    private var accent: Color { AgentBrandColor.color(for: session.tool) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Accent rail
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                header

                if let request = session.permissionRequest {
                    permissionBody(request)
                } else if let prompt = session.questionPrompt {
                    questionBody(prompt)
                }
            }
            .padding(.leading, 12)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            AgentBadge(tool: session.tool, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.spotlightWorkspaceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                AgentPhaseChip(phase: session.phase)
            }

            Spacer(minLength: 0)

            if session.jumpTarget != nil {
                Button {
                    bridge.jumpBack(to: session)
                } label: {
                    Image(systemName: "arrowshape.turn.up.forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Jump back to this session")
            }
        }
    }

    // MARK: Permission

    @ViewBuilder
    private func permissionBody(_ request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !request.title.isEmpty {
                Text(request.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            if !request.summary.isEmpty {
                Text(request.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !request.affectedPath.isEmpty {
                Label(request.affectedPath, systemImage: "folder")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                actionButton(
                    request.secondaryActionTitle.isEmpty ? "Deny" : request.secondaryActionTitle,
                    role: .deny
                ) {
                    bridge.resolve(session, .deny)
                }
                actionButton(
                    request.primaryActionTitle.isEmpty ? "Allow" : request.primaryActionTitle,
                    role: .primary
                ) {
                    bridge.resolve(session, .allowOnce)
                }
                if !request.suggestedUpdates.isEmpty {
                    actionButton("Always allow", role: .secondary) {
                        bridge.resolve(session, .allowWithUpdates(request.suggestedUpdates))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Question

    @ViewBuilder
    private func questionBody(_ prompt: QuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !prompt.title.isEmpty {
                Text(prompt.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !prompt.options.isEmpty {
                FlowOptions(options: prompt.options, accent: accent) { option in
                    bridge.answer(session, QuestionPromptResponse(answer: option))
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Type your answer…", text: $freeformAnswer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )
                        .onSubmit(submitFreeform)
                    actionButton("Send", role: .primary, action: submitFreeform)
                        .disabled(freeformAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func submitFreeform() {
        let trimmed = freeformAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bridge.answer(session, QuestionPromptResponse(answer: trimmed))
        freeformAnswer = ""
    }

    // MARK: Buttons

    private enum ButtonRole { case primary, secondary, deny }

    private func actionButton(_ title: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(foreground(for: role))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(background(for: role))
        }
        .buttonStyle(.plain)
    }

    private func foreground(for role: ButtonRole) -> Color {
        switch role {
        case .primary: return .black.opacity(0.9)
        case .secondary: return .white.opacity(0.85)
        case .deny: return .white.opacity(0.8)
        }
    }

    @ViewBuilder
    private func background(for role: ButtonRole) -> some View {
        switch role {
        case .primary:
            Capsule().fill(accent)
        case .secondary:
            Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1)
        case .deny:
            Capsule().fill(.white.opacity(0.1))
        }
    }
}

/// Wrapping row of selectable option chips for a question prompt.
private struct FlowOptions: View {
    let options: [String]
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        WrapHStack(spacing: 6, lineSpacing: 6) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.08))
                                .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping horizontal stack: lays children left-to-right, wrapping to
/// a new line when the available width is exceeded.
private struct WrapHStack: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Compact row (running / completed)

struct AgentSessionCompactRow: View {
    let session: AgentSession
    let onJumpBack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentBadge(tool: session.tool, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.spotlightWorkspaceName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    AgentPhaseChip(phase: session.phase)
                    Spacer(minLength: 0)
                    if session.jumpTarget != nil {
                        Button(action: onJumpBack) {
                            Image(systemName: "arrowshape.turn.up.forward.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.65))
                        .help("Jump back to this session")
                    }
                }
                if let activity = activityText, !activity.isEmpty {
                    Text(activity)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.055))
        )
        .padding(.horizontal, 8)
    }

    private var activityText: String? {
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? session.title : summary
    }
}
