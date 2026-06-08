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
 */

import SwiftUI

/// Compact camera button shown in the notch header. Clicking opens a dropdown
/// with the screen-capture actions (area / full screen / OCR / scrolling
/// capture) plus quick access to the capture history.
///
/// Replaces the former dedicated "Capture" tab — the actions live in the header
/// alongside the other utility buttons so the notch stays a single surface.
/// Styled to match the sibling header buttons (black capsule, white glyph).
struct ScreenCaptureMenuButton: View {
    private let size: CGFloat = 30

    var body: some View {
        Menu {
            Button {
                MacshotManager.shared.startCapture(type: .area)
            } label: {
                Label("Capture Area", systemImage: "viewfinder.rectangular")
            }

            Button {
                MacshotManager.shared.startCapture(type: .full)
            } label: {
                Label("Capture Full Screen", systemImage: "desktopcomputer")
            }

            Button {
                MacshotManager.shared.startOCR()
            } label: {
                Label("Extract Text (OCR)", systemImage: "text.viewfinder")
            }

            Button {
                MacshotManager.shared.startScrollCapture()
            } label: {
                Label("Scrolling Capture", systemImage: "scroll")
            }

            Divider()

            Button {
                HistoryOverlayController().show()
            } label: {
                Label("History", systemImage: "clock.arrow.2.circlepath")
            }
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(.white)
                        .padding()
                        .imageScale(.medium)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // A SwiftUI `Menu` does not honor the label's inner `.foregroundColor`
        // the way a `Button` does, so the white glyph rendered black against the
        // black capsule (invisible). Forcing the tint keeps the glyph white,
        // matching the sibling header buttons.
        .tint(.white)
        .frame(width: size, height: size)
        .help("Screen Capture")
    }
}
