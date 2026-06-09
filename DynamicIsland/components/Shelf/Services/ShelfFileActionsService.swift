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

import AppKit
import Foundation
import UniformTypeIdentifiers

/// File-system and cloud actions for shelf items that don't belong in the
/// lightweight `ShelfActionService` (Copy to…/Move to…, cloud upload,
/// add-from-clipboard).
@MainActor
enum ShelfFileActionsService {

    // MARK: - Copy to… / Move to…

    /// Prompts for a destination folder, then copies or moves the given file
    /// items into it. On move, the shelf item is re-pointed at the new location.
    static func copyOrMove(_ items: [ShelfItem], move: Bool, relativeTo view: NSView?) {
        let fileItems = items.filter { if case .file = $0.kind { return true }; return false }
        guard !fileItems.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move Here" : "Copy Here"
        panel.message = move
            ? "Choose a destination folder to move the file(s) into."
            : "Choose a destination folder to copy the file(s) into."

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { await perform(fileItems, destination: destination, move: move) }
        }

        if let window = view?.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private static func perform(_ items: [ShelfItem], destination: URL, move: Bool) async {
        let didStartDest = destination.startAccessingSecurityScopedResource()
        defer { if didStartDest { destination.stopAccessingSecurityScopedResource() } }

        for item in items {
            guard let source = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else { continue }

            await source.accessSecurityScopedResource { src in
                let target = uniqueDestinationURL(for: src.lastPathComponent, in: destination)
                do {
                    if move {
                        try FileManager.default.moveItem(at: src, to: target)
                        if let bookmark = try? Bookmark(url: target) {
                            ShelfStateViewModel.shared.updateBookmark(for: item, bookmark: bookmark.data)
                        }
                    } else {
                        try FileManager.default.copyItem(at: src, to: target)
                    }
                } catch {
                    NSLog("❌ \(move ? "Move" : "Copy") to failed: \(error.localizedDescription)")
                    presentError(
                        title: move ? "Move Failed" : "Copy Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    /// Returns a non-colliding URL inside `directory`, appending " 2", " 3"… if needed.
    private static func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let name = filename as NSString
        let base = name.deletingPathExtension
        let ext = name.pathExtension

        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    // MARK: - Copy Cloud Link (S3)

    /// Retains the in-flight upload toast for the duration of the upload.
    private static var activeToast: UploadToastController?

    /// Uploads the selected file items to the configured S3 storage and copies
    /// the resulting public link(s) to the pasteboard.
    static func copyCloudLink(_ items: [ShelfItem]) {
        let fileItems = items.filter { if case .file = $0.kind { return true }; return false }
        guard !fileItems.isEmpty else { return }

        guard S3Uploader.shared.isConfigured else {
            presentError(
                title: "Cloud Storage Not Configured",
                message: "Set up S3-compatible storage in Settings → Capture → Cloud Upload to copy cloud links."
            )
            return
        }

        let toast = UploadToastController()
        activeToast = toast
        toast.onDismiss = { activeToast = nil }
        toast.show(status: "Uploading…")

        Task {
            var links: [String] = []
            var lastError: Error?

            for (index, item) in fileItems.enumerated() {
                guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else { continue }

                let result: Result<String, Error> = await withCheckedContinuation { continuation in
                    // The data is read synchronously inside `uploadFile`, so holding
                    // the security scope across this call is sufficient.
                    url.accessSecurityScopedResource { scoped in
                        S3Uploader.shared.onProgress = { fraction in
                            let overall = (Double(index) + fraction) / Double(fileItems.count)
                            toast.updateProgress(overall)
                        }
                        S3Uploader.shared.uploadFile(url: scoped) { res in
                            continuation.resume(returning: res)
                        }
                    }
                }

                switch result {
                case .success(let link): links.append(link)
                case .failure(let error): lastError = error
                }
            }

            if !links.isEmpty {
                let joined = links.joined(separator: "\n")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(joined, forType: .string)
                toast.showSuccess(link: links[0], deleteURL: "")
            } else {
                toast.showError(message: lastError?.localizedDescription ?? "Upload failed")
            }
        }
    }

    // MARK: - Add From Clipboard

    /// Adds the current pasteboard contents (files, a web URL, or text) to the shelf.
    static func addFromClipboard() {
        let pb = NSPasteboard.general

        // 1) File URLs take priority
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            Task {
                let items = await ShelfDropService.items(from: urls)
                ShelfStateViewModel.shared.add(items)
            }
            return
        }

        // 2) A web URL
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let web = urls.first(where: { !$0.isFileURL }) {
            ShelfStateViewModel.shared.add([ShelfItem(kind: .link(url: web))])
            return
        }

        // 3) Plain text
        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ShelfStateViewModel.shared.add([ShelfItem(kind: .text(string: text))])
        }
    }

    // MARK: - Helpers

    private static func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
