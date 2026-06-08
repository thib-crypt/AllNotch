import Foundation

/// Small utility that walks a directory's immediate contents and deletes
/// entries matching a caller-supplied predicate, optionally restricted to
/// files older than a given age. Intended to run off the main thread.
enum DirectorySweeper {

    /// - Parameters:
    ///   - directory: Folder whose immediate contents are scanned (non-recursive).
    ///   - olderThan: Optional minimum age (in seconds since last modification)
    ///     before a file is eligible for deletion. `nil` disables the age filter.
    ///   - shouldDelete: Predicate receiving each entry's last path component;
    ///     return `true` to delete it.
    static func sweep(directory: URL,
                      olderThan: TimeInterval? = nil,
                      shouldDelete: (String) -> Bool) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        for url in contents {
            let name = url.lastPathComponent
            guard shouldDelete(name) else { continue }

            if let maxAge = olderThan {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? now
                guard now.timeIntervalSince(modified) >= maxAge else { continue }
            }

            try? fm.removeItem(at: url)
        }
    }
}
