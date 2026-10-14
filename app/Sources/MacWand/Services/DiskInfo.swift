import Foundation

/// Capacity of the startup volume.
struct DiskInfo {
    let total: Int64
    /// Space available for new files, including purgeable space macOS can reclaim.
    let available: Int64

    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Reads the current numbers for the volume that holds the home folder.
    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskInfo(total: Int64(total), available: available)
    }

    /// Whether the app can read folders that need Full Disk Access.
    static var hasFullDiskAccess: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari").path
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }
}
