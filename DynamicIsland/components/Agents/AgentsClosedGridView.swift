//
//  AgentsClosedGridView.swift
//  AllNotch
//
//  The closed-notch "space invaders" agents grid, ported faithfully from Open
//  Vibe Island (Sources/OpenIslandApp/Views/V6NotchContent.swift, GPL v3).
//
//  A balanced matrix of rounded tiles, one per live agent session:
//    running = full brand color, idle = dim, waiting = breathing pulse.
//  AllNotch only surfaces this in the closed notch when a session needs the
//  user's attention; tapping it opens the Agents tab.
//

import OpenIslandCore
import SwiftUI

/// Per-cell state for the closed-island agents grid.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

// MARK: - Cell building

enum AgentsClosedGrid {
    /// Maximum number of session tiles before we collapse the tail into a
    /// single `.overflow` cell. Mirrors Open Island: 7 sessions + 1 overflow
    /// lays out as a clean [4,4] matrix.
    private static let maxSessionTiles = 7

    /// Builds the balanced grid cells for the given sessions (already filtered
    /// to the visible ones). Returns an empty array when there is nothing to
    /// show.
    static func cells(for sessions: [AgentSession]) -> [AgentGridCell] {
        guard !sessions.isEmpty else { return [] }

        if sessions.count <= maxSessionTiles + 1 {
            return sessions.map(cell(for:))
        }

        let head = sessions.prefix(maxSessionTiles).map(cell(for:))
        let overflow = sessions.count - maxSessionTiles
        return head + [.overflow(overflow)]
    }

    private static func cell(for session: AgentSession) -> AgentGridCell {
        let color = Color(agentHex: session.tool.brandColorHex) ?? IslandDesignPalette.Status.running
        let state: AgentGridCellState
        switch session.phase {
        case .waitingForApproval, .waitingForAnswer:
            state = .waiting
        case .running:
            state = .running
        case .completed:
            state = .idle
        }
        return .session(color: color, state: state)
    }
}

// MARK: - Layout math (ported from V6RightSlotView)

enum AgentsGridLayout {
    /// Hand-tuned per-row cell counts so the matrix reads as a deliberate shape
    /// instead of a wrap-at-4-columns grid.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still fits
    /// inside the pill's internal vertical budget.
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }

    /// Intrinsic width of the rendered grid, used by the host layout to reserve
    /// horizontal room in the closed notch.
    static func intrinsicWidth(_ cells: [AgentGridCell]) -> CGFloat {
        let n = cells.count
        guard n > 0 else { return 0 }
        let rows = balancedRows(n)
        let maxRow = rows.max() ?? 0
        let geom = cellGeometry(rowCount: rows.count)
        return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
    }
}

// MARK: - Grid body

/// Dense grid renderer. 2D matrix of rounded squares, each row horizontally
/// centered. Running = full color, idle = 22% alpha, waiting = breathing pulse.
struct AgentsClosedGridView: View {
    let cells: [AgentGridCell]

    var body: some View {
        let rowSizes = AgentsGridLayout.balancedRows(cells.count)
        let geom = AgentsGridLayout.cellGeometry(rowCount: rowSizes.count)
        let rows = AgentsGridLayout.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
