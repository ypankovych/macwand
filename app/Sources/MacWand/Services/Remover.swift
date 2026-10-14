import Foundation

/// Removes files: moves them to the Trash, or deletes them if they're already there.
struct Remover {
    /// The outcome of a removal request.
    struct Report {
        var removed: [URL] = []
        var failures: [(url: URL, message: String)] = []
    }

    private let trashFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path

    /// Removes each URL, falling back to Finder for items the user can't
    /// trash directly (e.g. root-owned App Store apps), which asks for a password.
    func remove(_ urls: [URL]) -> Report {
        var report = Report()
        for url in urls {
            do {
                if url.path.hasPrefix(trashFolder + "/") {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try trash(url)
                }
                report.removed.append(url)
            } catch {
                report.failures.append((url, error.localizedDescription))
            }
        }
        return report
    }

    private func trash(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            try trashWithFinder(url)
        }
    }

    private func trashWithFinder(_ url: URL) throws {
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"\(escaped)\")")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder couldn't move it to the Trash."
            throw NSError(domain: "MacWand", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
