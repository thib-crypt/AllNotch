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

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !enableMinimalisticUI {
                    let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                    if shouldShowTabs {
                        TabSelectionView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(enableMinimalisticUI ? .clear : (NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear))
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            NotchHeaderActionsCluster()
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .animation(.smooth.delay(0.1), value: vm.notchState)
                .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

/// The right cluster of the open notch: customizable quick actions (mirror,
/// clipboard, color picker, timer, screenshot, settings) in user order, followed
/// by the always-anchored status indicators and battery. Quick actions that
/// don't fit overflow into the Apps grid (`NotchLauncherModel.overflowedQuickActions`).
private struct NotchHeaderActionsCluster: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var launcher = NotchLauncherModel.shared

    @State private var showClipboardPopover = false
    @State private var showColorPickerPopover = false
    @State private var showTimerPopover = false
    @State private var clusterWidth: CGFloat = 0

    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.notchQuickActionsOrder) private var quickActionsOrder
    @Default(.showMirror) private var showMirror
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.showClipboardIcon) private var showClipboardIcon
    @Default(.clipboardDisplayMode) private var clipboardDisplayMode
    @Default(.enableColorPickerFeature) private var enableColorPickerFeature
    @Default(.showColorPickerIcon) private var showColorPickerIcon
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.enableScreenshotFeature) private var enableScreenshotFeature
    @Default(.settingsIconInNotch) private var settingsIconInNotch

    private let slot: CGFloat = 34

    var body: some View {
        let isActive = vm.notchState == .open && !enableMinimalisticUI
        let actions = isActive ? launcher.quickActions() : []
        let capacity = actionCapacity()
        let visible = Array(actions.prefix(capacity))
        let overflow = Array(actions.dropFirst(capacity))

        return HStack(spacing: 4) {
            if isActive {
                ForEach(visible, id: \.self) { actionButton($0) }
                statusIndicators
            }
            batteryView
        }
        .font(.system(.headline, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { clusterWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in clusterWidth = newValue }
            }
        )
        .onAppear { launcher.setOverflowedQuickActions(overflow) }
        .onChange(of: overflow) { _, newValue in launcher.setOverflowedQuickActions(newValue) }
        .onChange(of: coordinator.shouldToggleClipboardPopover) { _, _ in
            guard Defaults[.enableClipboardManager] else { return }
            switch clipboardDisplayMode {
            case .panel:
                ClipboardPanelManager.shared.toggleClipboardPanel()
            case .popover:
                showClipboardPopover.toggle()
            case .separateTab:
                coordinator.currentView = coordinator.currentView == .notes ? .home : .notes
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleClipboardPopover"))) { _ in
            if Defaults[.enableClipboardManager] && clipboardDisplayMode == .popover {
                showClipboardPopover.toggle()
            }
        }
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }

    // MARK: - Capacity

    /// Number of quick-action slots that fit after reserving space for the
    /// always-anchored status indicators and battery. Over-reserving simply
    /// pushes a borderline action into the grid (safe).
    private func actionCapacity() -> Int {
        let available = clusterWidth - batteryReserve - statusReserve
        guard available > 0 else { return 0 }
        return max(0, Int((available + 4) / slot))
    }

    private var batteryReserve: CGFloat {
        guard vm.notchState == .open && showBatteryIndicator else { return 0 }
        return enableMinimalisticUI ? 44 : 76
    }

    private var statusReserve: CGFloat {
        guard vm.notchState == .open && !enableMinimalisticUI else { return 0 }
        var count = 0
        if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !shouldSuppressStatusIndicators {
            count += 1
        }
        if Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && !shouldSuppressStatusIndicators {
            count += 1
        }
        return CGFloat(count) * slot
    }

    private var shouldSuppressStatusIndicators: Bool {
        Defaults[.settingsIconInNotch]
            && Defaults[.enableClipboardManager]
            && Defaults[.showClipboardIcon]
            && Defaults[.showColorPickerIcon]
            && Defaults[.enableTimerFeature]
    }

    // MARK: - Status & battery (never overflow)

    @ViewBuilder
    private var statusIndicators: some View {
        if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !shouldSuppressStatusIndicators {
            RecordingIndicator()
                .frame(width: 30, height: 30)
        }
        if Defaults[.enableDoNotDisturbDetection]
            && Defaults[.showDoNotDisturbIndicator]
            && doNotDisturbManager.isDoNotDisturbActive
            && !shouldSuppressStatusIndicators {
            FocusIndicator()
                .frame(width: 30, height: 30)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var batteryView: some View {
        if vm.notchState == .open && showBatteryIndicator {
            if enableMinimalisticUI {
                MinimalisticBatteryView(
                    levelBattery: batteryModel.levelBattery,
                    isPluggedIn: batteryModel.isPluggedIn,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    bodyWidth: 28,
                    bodyHeight: 14,
                    isForNotification: false,
                    showPercentInside: showBatteryPercentInside
                )
                .padding(.trailing, 4)
            } else {
                DynamicIslandBatteryView(
                    batteryWidth: 30,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    isForNotification: false
                )
            }
        }
    }

    // MARK: - Quick-action buttons (visible in the bar)

    @ViewBuilder
    private func actionButton(_ kind: QuickActionKind) -> some View {
        switch kind {
        case .mirror:
            Button(action: { vm.toggleCameraPreview() }) {
                headerButtonShell(icon: "web.camera")
            }
            .buttonStyle(PlainButtonStyle())

        case .clipboard:
            Button(action: {
                switch clipboardDisplayMode {
                case .panel:
                    ClipboardPanelManager.shared.toggleClipboardPanel()
                case .popover:
                    showClipboardPopover.toggle()
                case .separateTab:
                    coordinator.currentView = .notes
                }
            }) {
                headerButtonShell(icon: "doc.on.clipboard")
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showClipboardPopover, arrowEdge: .bottom) {
                ClipboardPopover()
            }
            .onChange(of: showClipboardPopover) { _, isActive in
                vm.isClipboardPopoverActive = isActive
                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }
            .onAppear {
                if Defaults[.enableClipboardManager] && !clipboardManager.isMonitoring {
                    clipboardManager.startMonitoring()
                }
            }

        case .colorPicker:
            Button(action: {
                switch Defaults[.colorPickerDisplayMode] {
                case .panel:
                    ColorPickerPanelManager.shared.toggleColorPickerPanel()
                case .popover:
                    showColorPickerPopover.toggle()
                }
            }) {
                headerButtonShell(icon: "eyedropper")
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showColorPickerPopover, arrowEdge: .bottom) {
                ColorPickerPopover()
            }
            .onChange(of: showColorPickerPopover) { _, isActive in
                vm.isColorPickerPopoverActive = isActive
                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }

        case .timer:
            Button(action: {
                withAnimation(.smooth) { showTimerPopover.toggle() }
            }) {
                headerButtonShell(icon: "timer")
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                TimerPopover()
            }
            .onChange(of: showTimerPopover) { _, isActive in
                vm.isTimerPopoverActive = isActive
                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }

        case .screenshot:
            ScreenCaptureMenuButton()

        case .settings:
            Button(action: { SettingsWindowController.shared.showWindow() }) {
                headerButtonShell(icon: "gear")
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func headerButtonShell(icon: String) -> some View {
        Capsule()
            .fill(.black)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .padding()
                    .imageScale(.medium)
            }
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
