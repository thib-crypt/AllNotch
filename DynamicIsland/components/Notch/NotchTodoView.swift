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
import Defaults

/// Minimalist to-do list rendered inside the open notch when the Todo tab is active.
struct NotchTodoView: View {
    @Default(.enableTodoFeature) private var enableTodoFeature
    @Default(.todoTasks) private var tasks
    @Default(.todoAccentColor) private var accentColor
    @Default(.todoHideCompleted) private var hideCompleted

    @State private var draftTitle: String = ""
    @State private var hoveredTaskID: TodoTask.ID?
    @FocusState private var quickAddFocused: Bool

    /// Tasks honoring the "hide completed" preference, incomplete first.
    private var visibleTasks: [TodoTask] {
        let filtered = hideCompleted ? tasks.filter { !$0.isCompleted } : tasks
        return filtered.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        Group {
            if enableTodoFeature {
                content
            } else {
                disabledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var content: some View {
        VStack(spacing: 10) {
            quickAddField

            if visibleTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
    }

    // MARK: - Quick add

    private var quickAddField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(draftTitle.isEmpty ? Color.white.opacity(0.4) : accentColor)

            TextField("Add a task…", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($quickAddFocused)
                .onSubmit(addTask)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(quickAddFocused ? accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.smooth(duration: 0.2), value: quickAddFocused)
    }

    // MARK: - List

    private var taskList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(visibleTasks) { task in
                    taskRow(task)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: tasks)
    }

    private func taskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isCompleted ? accentColor : Color.white.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(task.isCompleted ? Color.white.opacity(0.45) : Color.white)
                .strikethrough(task.isCompleted, color: .white.opacity(0.45))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hoveredTaskID == task.id {
                Button {
                    delete(task)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredTaskID == task.id ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) {
                hoveredTaskID = hovering ? task.id : (hoveredTaskID == task.id ? nil : hoveredTaskID)
            }
        }
    }

    // MARK: - Empty / disabled states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accentColor.opacity(0.7))
            Text("No tasks yet. Add one to get started!")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.5))
            Text("Enable the Todo feature in Settings to use this tab.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mutations

    private func addTask() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.smooth(duration: 0.25)) {
            tasks.append(TodoTask(title: trimmed))
        }
        draftTitle = ""
        quickAddFocused = true
    }

    private func toggle(_ task: TodoTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(.smooth(duration: 0.25)) {
            tasks[index].isCompleted.toggle()
        }
    }

    private func delete(_ task: TodoTask) {
        withAnimation(.smooth(duration: 0.25)) {
            tasks.removeAll { $0.id == task.id }
        }
    }
}

#Preview {
    NotchTodoView()
        .frame(width: 420, height: 260)
        .background(.black)
}
