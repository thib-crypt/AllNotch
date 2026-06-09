/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AppKit

private struct ShelfBackgroundClickCatcher: NSViewRepresentable {
    let onClick: () -> Void
    let onRightClick: (NSEvent, NSView) -> Void

    func makeNSView(context: Context) -> BackgroundClickView {
        let view = BackgroundClickView()
        view.onClick = onClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: BackgroundClickView, context: Context) {
        nsView.onClick = onClick
        nsView.onRightClick = onRightClick
    }

    final class BackgroundClickView: NSView {
        var onClick: (() -> Void)?
        var onRightClick: ((NSEvent, NSView) -> Void)?

        override func mouseUp(with event: NSEvent) {
            onClick?()
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(event, self)
        }
    }
}

/// Target for the shelf background context menu (right-click on empty area).
@MainActor
private final class ShelfBackgroundMenuTarget: NSObject {
    @objc func addFromClipboard(_ sender: NSMenuItem) {
        ShelfFileActionsService.addFromClipboard()
    }

    @objc func clearShelf(_ sender: NSMenuItem) {
        let count = ShelfStateViewModel.shared.items.count
        guard count > 0 else { return }
        if count > 1 {
            let alert = NSAlert()
            alert.messageText = "Clear Shelf?"
            alert.informativeText = "This removes all \(count) items from the shelf. Files on disk are not deleted."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        ShelfStateViewModel.shared.clearAll()
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        SettingsWindowController.shared.showWindow()
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var keyMonitor: Any?
    @State private var backgroundMenuTarget = ShelfBackgroundMenuTarget()
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
        .onAppear {
            // Discover share providers so the context menu can pin them.
            QuickShareService.shared.ensureDiscovered()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Spacebar Quick Look

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 49 = space. Finder-style: space opens Quick Look for the selection.
            if event.keyCode == 49, handleSpaceKey() { return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns true if the space key was consumed to open Quick Look.
    private func handleSpaceKey() -> Bool {
        // Don't steal space while editing text (e.g. inline rename field).
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
            return false
        }
        // If Quick Look is already open, let the panel handle space (it closes itself).
        guard !quickLookService.isQuickLookOpen else { return false }

        let urls = selectedURLs()
        guard !urls.isEmpty else { return false }
        quickLookService.show(urls: urls, selectFirst: true)
        return true
    }

    private func selectedURLs() -> [URL] {
        selection.selectedItems(in: tvm.items).compactMap { item in
            if let fileURL = item.fileURL { return fileURL }
            if case .link(let url) = item.kind { return url }
            return nil
        }
    }
    
    // MARK: - Background Context Menu

    private func presentBackgroundMenu(event: NSEvent, in view: NSView) {
        let menu = NSMenu()

        let pasteboardHasContent = NSPasteboard.general.canReadObject(forClasses: [NSURL.self, NSString.self], options: nil)
        let addItem = NSMenuItem(title: "Add From Clipboard",
                                 action: #selector(ShelfBackgroundMenuTarget.addFromClipboard(_:)),
                                 keyEquivalent: "")
        addItem.target = backgroundMenuTarget
        addItem.isEnabled = pasteboardHasContent
        menu.addItem(addItem)

        if !tvm.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Shelf",
                                       action: #selector(ShelfBackgroundMenuTarget.clearShelf(_:)),
                                       keyEquivalent: "")
            clearItem.target = backgroundMenuTarget
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(ShelfBackgroundMenuTarget.openSettings(_:)),
                                      keyEquivalent: "")
        settingsItem.target = backgroundMenuTarget
        menu.addItem(settingsItem)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                ZStack {
                    ShelfBackgroundClickCatcher(
                        onClick: {
                            guard !selection.isDragging else { return }
                            selection.clear()
                        },
                        onRightClick: { event, view in
                            presentBackgroundMenu(event: event, in: view)
                        }
                    )

                    content
                        .padding()
                }
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
