import Foundation

/// A file or folder that can be removed to free space.
struct FileItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    /// Extra description, e.g. the artifact kind ("node_modules").
    let label: String?

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// Labeled items are build folders whose own name ("node_modules") says little,
    /// so they're shown under the project folder that contains them.
    private var shownURL: URL { label == nil ? url : url.deletingLastPathComponent() }

    /// Name shown in lists: the item itself, or its project for build folders.
    var displayName: String { shownURL.lastPathComponent }

    /// Folder containing `displayName`, with the home directory shortened to `~`.
    var location: String { shownURL.deletingLastPathComponent().path.abbreviatingHome }

    /// Sort key that orders unknown dates first.
    var modifiedSortKey: Date { modified ?? .distantPast }
}

/// How careful the user should be with a category.
enum Safety: String {
    /// Regenerated automatically; removing it is harmless.
    case safe
    /// Could hold something the user wants to keep.
    case review
}

/// A group of removable items such as app caches or Downloads.
struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let summary: String
    let safety: Safety
    private(set) var items: [FileItem] = []
    /// Kept in step with `items` so views never re-sum thousands of rows.
    private(set) var totalSize: Int64 = 0

    mutating func add(_ item: FileItem) {
        items.append(item)
        totalSize += item.size
    }

    /// Drops items whose URLs were removed from disk.
    mutating func remove(_ urls: Set<URL>) {
        items.removeAll { urls.contains($0.url) }
        totalSize = items.reduce(0) { $0 + $1.size }
    }

    /// Items here are already in the Trash, so removing them deletes them for good.
    var deletesPermanently: Bool { id == "trash" }

    /// SF Symbol shown next to the category.
    var symbol: String {
        switch id {
        case "user_caches": "internaldrive"
        case "logs": "doc.text"
        case "xcode", "xcode_archives", "simulators": "hammer"
        case "package_caches": "shippingbox"
        case "ios_backups": "iphone"
        case "mail_downloads": "envelope"
        case "downloads": "arrow.down.circle"
        case "trash": "trash"
        case "dev_artifacts": "chevron.left.forwardslash.chevron.right"
        default: "folder"
        }
    }
}

/// An installed application and the support files it left in ~/Library.
struct AppInfo: Identifiable {
    let url: URL
    let name: String
    let bundleID: String?
    let size: Int64
    var lastUsed: Date?
    var leftovers: [FileItem] = []

    var id: String { url.path }
    var leftoversSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { size + leftoversSize }
    var lastUsedSortKey: Date { lastUsed ?? .distantPast }

    /// Not opened for at least `AppInfo.unusedAfter`, according to Spotlight.
    var isUnused: Bool {
        guard let lastUsed else { return false }
        return lastUsed < Date.now.addingTimeInterval(-AppInfo.unusedAfter)
    }

    /// 90 days.
    static let unusedAfter: TimeInterval = 90 * 24 * 3600
}

extension String {
    /// Replaces the home directory prefix with `~`.
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

extension Int64 {
    /// Human-readable file size, e.g. "1.2 GB".
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
