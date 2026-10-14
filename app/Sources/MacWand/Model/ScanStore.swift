import Foundation

/// Owns scan results and the actions that change them. All UI state flows from here.
@MainActor
final class ScanStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case finished(elapsed: TimeInterval, unreadable: Int64)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var scannedFiles: Int64 = 0
    @Published private(set) var scannedBytes: Int64 = 0
    @Published private(set) var currentPath = ""
    @Published private(set) var largeFiles: [FileItem] = []
    @Published private(set) var categories: [CleanupCategory] = []
    @Published private(set) var apps: [AppInfo] = []
    /// True between the end of the file scan and the app list being ready.
    @Published private(set) var isMeasuringApps = false
    @Published private(set) var disk = DiskInfo.current()
    /// Checked when a scan starts, not on every render: the check lists a folder.
    @Published private(set) var hasFullDiskAccess = DiskInfo.hasFullDiskAccess
    /// Message for the last removal that didn't fully succeed.
    @Published var removalError: String?
    /// Space freed by the most recent removal, shown briefly as a confirmation.
    @Published private(set) var freedNotice: FreedNotice?

    /// A completed removal, identified so repeated equal amounts still re-trigger the UI.
    struct FreedNotice: Equatable {
        let id = UUID()
        let bytes: Int64
        let count: Int
        let permanently: Bool
    }

    // Derived values, recomputed once per change batch rather than on every view
    // read: views read them many times per frame and the inputs hold thousands of items.

    /// Categories that have something to clean, in engine order.
    @Published private(set) var nonEmptyCategories: [CleanupCategory] = []
    @Published private(set) var largeFilesSize: Int64 = 0
    @Published private(set) var unusedApps: [AppInfo] = []
    @Published private(set) var appsSize: Int64 = 0
    /// Large files that aren't inside an item already listed in a cleanup category,
    /// so totals can add both without counting anything twice.
    @Published private(set) var looseLargeFiles: [FileItem] = []
    /// Everything the scan suggests removing, without double counting.
    @Published private(set) var reclaimableSize: Int64 = 0

    var isScanning: Bool { phase == .scanning || isMeasuringApps }

    /// Hides the freed-space confirmation.
    func dismissFreedNotice() { freedNotice = nil }

    private let engine: EngineClient
    private let inspector: AppInspector
    private let remover: Remover
    private var scanTask: Task<Void, Never>?
    /// Sizes of direct children of app-data folders, reported by the engine.
    private var sizeIndex: [String: Int64] = [:]
    private var pendingApps: [(path: String, size: Int64)] = []

    init(engine: EngineClient = EngineClient(), inspector: AppInspector = AppInspector(), remover: Remover = Remover()) {
        self.engine = engine
        self.inspector = inspector
        self.remover = remover
    }

    // MARK: Scanning

    /// Starts a fresh scan, discarding previous results.
    func startScan() {
        scanTask?.cancel()
        reset()
        phase = .scanning
        scanTask = Task {
            do {
                for try await batch in engine.scan() {
                    apply(batch)
                }
                if !Task.isCancelled { await finishApps() }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a running scan, keeping what was found so far.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isMeasuringApps = false
        if phase == .scanning { phase = .idle }
    }

    private func reset() {
        scannedFiles = 0
        scannedBytes = 0
        currentPath = ""
        largeFiles = []
        categories = []
        apps = []
        sizeIndex = [:]
        pendingApps = []
        disk = DiskInfo.current()
        hasFullDiskAccess = DiskInfo.hasFullDiskAccess
        refreshDerived()
    }

    /// Applies one batch of engine events. Changes are collected in local copies and
    /// published once, so observers see a single update per batch and arrays aren't
    /// copied for every event.
    private func apply(_ batch: [EngineEvent]) {
        var large = largeFiles
        var cats = categories
        var resultsChanged = false
        for event in batch {
            switch event.type {
            case "progress":
                scannedFiles = event.files ?? scannedFiles
                scannedBytes = event.bytes ?? scannedBytes
                currentPath = event.current?.abbreviatingHome ?? ""
            case "large_file":
                if let item = fileItem(from: event) {
                    large.append(item)
                    resultsChanged = true
                }
            case "category":
                guard let id = event.id else { continue }
                cats.append(CleanupCategory(
                    id: id,
                    name: event.name ?? id,
                    summary: event.description ?? "",
                    safety: Safety(rawValue: event.safety ?? "") ?? .review
                ))
                resultsChanged = true
            case "category_item":
                guard let item = fileItem(from: event),
                      let index = cats.firstIndex(where: { $0.id == event.category })
                else { continue }
                cats[index].add(item)
                resultsChanged = true
            case "app":
                if let path = event.path { pendingApps.append((path, event.size ?? 0)) }
            case "size":
                if let path = event.path { sizeIndex[path] = event.size ?? 0 }
            case "done":
                let elapsed = TimeInterval(event.elapsedMs ?? 0) / 1000
                phase = .finished(elapsed: elapsed, unreadable: event.errors ?? 0)
            default:
                break
            }
        }
        guard resultsChanged else { return }
        largeFiles = large
        categories = cats
        refreshDerived()
    }

    private func refreshDerived() {
        nonEmptyCategories = categories.filter { !$0.items.isEmpty }
        largeFilesSize = largeFiles.reduce(0) { $0 + $1.size }
        unusedApps = apps.filter(\.isUnused)
        appsSize = apps.reduce(0) { $0 + $1.totalSize }

        let claimed = Set(categories.lazy.flatMap(\.items).map(\.id))
        looseLargeFiles = largeFiles.filter { file in
            var folder = file.url
            while folder.pathComponents.count > 1 {
                if claimed.contains(folder.path) { return false }
                folder.deleteLastPathComponent()
            }
            return true
        }
        reclaimableSize = nonEmptyCategories.reduce(0) { $0 + $1.totalSize }
            + looseLargeFiles.reduce(0) { $0 + $1.size }
            + unusedApps.reduce(0) { $0 + $1.totalSize }
    }

    private func fileItem(from event: EngineEvent) -> FileItem? {
        guard let path = event.path else { return nil }
        return FileItem(
            url: URL(fileURLWithPath: path, isDirectory: false),
            size: event.size ?? 0,
            modified: event.modified.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            label: event.label
        )
    }

    /// Reads app metadata and sizes leftovers once the scan has finished.
    private func finishApps() async {
        isMeasuringApps = true
        defer { isMeasuringApps = false }
        let inspector = inspector
        let pending = pendingApps
        var found = await Task.detached {
            pending.compactMap { inspector.inspect(bundleURL: URL(fileURLWithPath: $0.path, isDirectory: true), size: $0.size) }
        }.value

        let leftoverURLs = await Task.detached { [found] in found.map { inspector.leftoverPaths(for: $0) } }.value
        let unknown = leftoverURLs.joined().map(\.path).filter { sizeIndex[$0] == nil }
        if !unknown.isEmpty {
            // Small files and folders outside the indexed Library folders. A failure
            // here only leaves those leftovers unsized.
            do {
                for try await batch in engine.sizes(of: unknown) { apply(batch) }
            } catch {}
        }
        for index in found.indices {
            found[index].leftovers = leftoverURLs[index].map { url in
                FileItem(url: url, size: sizeIndex[url.path] ?? 0, modified: nil, label: nil)
            }
        }
        apps = found.sorted { $0.totalSize > $1.totalSize }
        refreshDerived()
    }

    // MARK: Removal

    /// Moves the given items to the Trash (or deletes them if already there)
    /// and drops whatever was removed from the results.
    func remove(_ items: [FileItem]) async {
        let removed = await perform(items.map(\.url))
        let freed = items.filter { removed.contains($0.url) }
        announce(freed.reduce(0) { $0 + $1.size }, count: freed.count,
                 permanently: items.contains { $0.url.path.hasPrefix(trashFolder) })
        largeFiles.removeAll { removed.contains($0.url) }
        var cats = categories
        for index in cats.indices { cats[index].remove(removed) }
        categories = cats
        refreshDerived()
    }

    /// Moves apps and their leftovers to the Trash. Running apps are skipped.
    func uninstall(_ selected: [AppInfo]) async {
        let running = selected.filter(inspector.isRunning)
        let removable = selected.filter { !inspector.isRunning($0) }
        let urls = removable.flatMap { [$0.url] + $0.leftovers.map(\.url) }
        let removed = await perform(urls)
        let gone = removable.filter { removed.contains($0.url) }
        announce(gone.reduce(0) { $0 + $1.totalSize }, count: gone.count, permanently: false)
        apps.removeAll { removed.contains($0.url) }
        refreshDerived()
        if !running.isEmpty {
            let names = running.map(\.name).joined(separator: ", ")
            removalError = [removalError, "Quit \(names) before uninstalling."].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private var trashFolder: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path + "/"
    }

    private func announce(_ bytes: Int64, count: Int, permanently: Bool) {
        guard count > 0 else { return }
        freedNotice = FreedNotice(bytes: bytes, count: count, permanently: permanently)
    }

    private func perform(_ urls: [URL]) async -> Set<URL> {
        let remover = remover
        let report = await Task.detached { remover.remove(urls) }.value
        if !report.failures.isEmpty {
            let lines = report.failures.prefix(5).map { "\($0.url.lastPathComponent): \($0.message)" }
            let more = report.failures.count > 5 ? ["…and \(report.failures.count - 5) more"] : []
            removalError = (lines + more).joined(separator: "\n")
        }
        disk = DiskInfo.current()
        return Set(report.removed)
    }
}
