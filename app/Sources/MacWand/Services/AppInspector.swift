import AppKit
import CoreServices

/// Reads app bundle metadata and finds the support files an app keeps in ~/Library.
struct AppInspector {
    private let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")

    /// Builds an `AppInfo` for a bundle the engine sized. Returns nil for apps
    /// that can't or shouldn't be removed.
    func inspect(bundleURL: URL, size: Int64) -> AppInfo? {
        let bundle = Bundle(url: bundleURL)
        let bundleID = bundle?.bundleIdentifier
        // Safari lives on the sealed system volume; macOS won't let it go.
        if bundleID == "com.apple.Safari" { return nil }
        let info = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let lastUsed = [spotlightLastUsed(bundleURL), bundle?.executableURL.flatMap(accessDate)].compactMap { $0 }.max()
        return AppInfo(url: bundleURL, name: name, bundleID: bundleID, size: size, lastUsed: lastUsed)
    }

    /// When the app was last opened according to Spotlight. Often missing when
    /// the Spotlight index is incomplete.
    private func spotlightLastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Last read of the app's executable, which happens on every launch.
    private func accessDate(_ executable: URL) -> Date? {
        try? executable.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
    }

    /// Existing ~/Library paths that belong to the app, matched by bundle id and name.
    func leftoverPaths(for app: AppInfo) -> [URL] {
        guard let bundleID = app.bundleID else { return [] }
        var candidates: [URL] = [
            library.appendingPathComponent("Application Support/\(bundleID)"),
            library.appendingPathComponent("Caches/\(bundleID)"),
            library.appendingPathComponent("Containers/\(bundleID)"),
            library.appendingPathComponent("HTTPStorages/\(bundleID)"),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            library.appendingPathComponent("Logs/\(bundleID)"),
            library.appendingPathComponent("Preferences/\(bundleID).plist"),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            library.appendingPathComponent("WebKit/\(bundleID)"),
            library.appendingPathComponent("Application Scripts/\(bundleID)"),
        ]
        // Folder names like "Slack" are only trusted when reasonably specific.
        if app.name.count >= 4 {
            candidates.append(library.appendingPathComponent("Application Support/\(app.name)"))
            candidates.append(library.appendingPathComponent("Caches/\(app.name)"))
            candidates.append(library.appendingPathComponent("Logs/\(app.name)"))
        }
        // Group containers are named "<TEAM ID>.<bundle id>".
        let groups = library.appendingPathComponent("Group Containers")
        let groupNames = (try? FileManager.default.contentsOfDirectory(atPath: groups.path)) ?? []
        candidates += groupNames
            .filter { $0.hasSuffix(".\(bundleID)") }
            .map { groups.appendingPathComponent($0) }

        var seen = Set<String>()
        return candidates.filter { url in
            seen.insert(url.path).inserted && FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Whether any instance of the app is running.
    func isRunning(_ app: AppInfo) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
