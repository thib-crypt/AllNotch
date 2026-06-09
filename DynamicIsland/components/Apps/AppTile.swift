/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

/// iOS-home-screen-style launcher tile: a continuous-corner squircle on
/// `.ultraThinMaterial`, tinted by the item's accent, with a caption below, an
/// optional red badge, and a subtle accent ring when selected. Used for both
/// destinations and overflowed quick actions in `AppsGridView`.
struct AppTile: View {
    let icon: String
    let label: String
    var accentColor: Color = .white
    var badge: Int? = nil
    var isSelected: Bool = false
    /// Staggered-appearance index (0-based). Ignored when Reduce Motion is on.
    var appearIndex: Int = 0
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let tileSize: CGFloat = 52
    private let corner: CGFloat = 14

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                tile
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: tileSize + 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AppTilePressStyle(reduceMotion: reduceMotion))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)
                    .delay(Double(appearIndex) * 0.02)) {
                    appeared = true
                }
            }
        }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: tileSize, height: tileSize)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(accentColor.opacity(0.18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accentColor == .white ? Color.white : accentColor)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.9), lineWidth: 2)
                        .shadow(color: accentColor.opacity(0.5), radius: 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 5, y: -5)
                }
            }
    }
}

/// Press feedback: the tile scales down slightly while held (skipped under
/// Reduce Motion).
private struct AppTilePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
