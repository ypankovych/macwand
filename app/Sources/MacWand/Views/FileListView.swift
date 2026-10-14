import SwiftUI

/// A sortable, multi-select table of removable files with a removal bar.
@MainActor
struct FileListView: View {
    let title: String
    let summary: String
    let safety: Safety
    let symbol: String
    let color: Color
    let items: [FileItem]
    /// True for items already in the Trash.
    let deletesPermanently: Bool

    @EnvironmentObject private var store: ScanStore
    @State private var selection = Set<FileItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileItem.size, order: .reverse)]
    @State private var confirming = false

    /// Sorted copy, refreshed only when the items or sort order change.
    @State private var sortedItems: [FileItem] = []
    private var selectedItems: [FileItem] { items.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(summary: summary, safety: safety, symbol: symbol, color: color, items: items)
            Divider()
            Table(sortedItems, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.displayName) { item in
                    HStack(spacing: 6) {
                        FileIcon(url: item.url)
                        Text(item.displayName).lineLimit(1).truncationMode(.middle)
                        if let label = item.label { Badge(text: label) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 180, ideal: 280)
                TableColumn("Location", value: \.location) { item in
                    Text(item.location).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(item.url.path.abbreviatingHome)
                }
                TableColumn("Modified", value: \.modifiedSortKey) { item in
                    Text(item.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                        .foregroundStyle(.secondary)
                }
                .width(110)
                TableColumn("Size", value: \.size) { item in
                    Text(item.size.formattedBytes)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(90)
            }
            .selectionMenu(
                reveal: { reveal($0) },
                removeTitle: deletesPermanently ? "Delete Permanently…" : "Move to Trash…",
                remove: { ids in
                    selection = ids
                    confirming = true
                }
            )
            .overlay {
                if items.isEmpty {
                    EmptyState(title: "Nothing Here", symbol: "checkmark.circle",
                               message: "Run a scan, or this spot is already clean.")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActionBar(
                    count: selectedItems.count,
                    size: selectedItems.reduce(0) { $0 + $1.size },
                    actionTitle: deletesPermanently ? "Delete Permanently" : "Move to Trash",
                    action: { confirming = true }
                )
            }
        }
        .navigationTitle(title)
        .onChangeAndAppear(of: items.count) { sortedItems = items.sorted(using: sortOrder) }
        .onChangeAndAppear(of: sortOrder) { sortedItems = items.sorted(using: sortOrder) }
        .confirmationDialog(confirmationTitle, isPresented: $confirming) {
            Button(deletesPermanently ? "Delete" : "Move to Trash", role: .destructive) {
                let targets = selectedItems
                selection.removeAll()
                Task { await store.remove(targets) }
            }
        } message: {
            Text(deletesPermanently
                 ? "This can't be undone."
                 : "You can put them back from the Trash. Space is freed when you empty the Trash.")
        }
    }

    private var confirmationTitle: String {
        let items = selectedItems
        let noun = items.count == 1 ? "“\(items[0].name)”" : "\(items.count) items"
        let size = items.reduce(0) { $0 + $1.size }.formattedBytes
        return deletesPermanently ? "Permanently delete \(noun) (\(size))?" : "Move \(noun) (\(size)) to the Trash?"
    }

    private func reveal(_ ids: Set<FileItem.ID>) {
        NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0, isDirectory: false) })
    }
}

extension View {
    /// Right-click menu for table rows, plus double-click to reveal (macOS 13+).
    /// On macOS 12 the action bar under the table covers removal.
    @ViewBuilder func selectionMenu(reveal: @escaping (Set<String>) -> Void, removeTitle: String,
                                    remove: @escaping (Set<String>) -> Void) -> some View {
        if #available(macOS 13, *) {
            contextMenu(forSelectionType: String.self) { ids in
                Button("Reveal in Finder") { reveal(ids) }
                Button(removeTitle) { remove(ids) }
            } primaryAction: { ids in
                reveal(ids)
            }
        } else {
            self
        }
    }
}

/// Category summary, safety hint, animated total and a chart of the biggest items.
@MainActor
struct ListHeader: View {
    let summary: String
    let safety: Safety
    let symbol: String
    let color: Color
    let items: [FileItem]

    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    private var topBars: [SizeBar] {
        items.sorted { $0.size > $1.size }.prefix(6).map { item in
            SizeBar(id: item.id, name: item.displayName, segments: [.init(bytes: item.size, color: color)])
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: symbol, color: color, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        AnimatedBytes(bytes: total, font: .system(size: 28, weight: .bold, design: .rounded))
                        Text("\(items.count) items").font(.callout).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                Text(summary).lineLimit(3).foregroundStyle(.secondary)
                Label(
                    safety == .safe ? "Safe to remove — rebuilt automatically" : "Review before removing",
                    systemImage: safety == .safe ? "checkmark.shield.fill" : "eye.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(safety == .safe ? .green : .orange)
            }
            .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
            if items.count >= 2 {
                SizeBars(bars: topBars)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [color.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}

/// Selection summary and the destructive action, pinned under a table.
@MainActor
struct ActionBar: View {
    let count: Int
    let size: Int64
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(count == 0 ? "Select items to remove. ⌘-click or ⇧-click to select several." : "\(count) selected — \(size.formattedBytes)")
                .foregroundStyle(count == 0 ? .secondary : .primary)
                .monospacedDigit()
            Spacer()
            Button(actionTitle, role: .destructive, action: action)
                .disabled(count == 0)
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Small rounded label, e.g. an artifact kind.
@MainActor
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .fixedSize()
    }
}

/// Finder icon for a file, cached because tables redraw rows often.
@MainActor
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 16

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: Self.icon(for: url.path))
            .resizable()
            .frame(width: size, height: size)
    }

    private static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
