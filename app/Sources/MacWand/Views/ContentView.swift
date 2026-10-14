import SwiftUI

/// Sidebar destinations.
enum SidebarItem: Hashable {
    case overview
    case largeFiles
    case apps
    case category(String)
}

/// Main window: sidebar of findings and a detail pane.
@MainActor
struct ContentView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var selection: SidebarItem?

    /// - Parameter initialSelection: The sidebar item shown first.
    init(initialSelection: SidebarItem = .overview) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        split
        .toolbar {
            ToolbarItem(placement: .primaryAction) { scanButton }
        }
        .environment(\.isLiveUpdating, store.isScanning)
        .overlay(alignment: .bottom) {
            if let notice = store.freedNotice {
                FreedToast(notice: notice)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice.id) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        withAnimation(.easeInOut) { store.dismissFreedNotice() }
                    }
            }
        }
        .animation(.lively, value: store.freedNotice)
        .alert("Some items weren't removed", isPresented: removalErrorShown) {
            Button("OK") { store.removalError = nil }
        } message: {
            Text(store.removalError ?? "")
        }
    }

    /// NavigationSplitView on macOS 13+, the equivalent two-column NavigationView before.
    @ViewBuilder private var split: some View {
        if #available(macOS 13, *) {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 260)
            } detail: {
                detail.id(selection)
            }
        } else {
            NavigationView {
                SidebarView(selection: $selection)
                    .frame(minWidth: 240, idealWidth: 260)
                detail.id(selection)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(selection: $selection)
        case .largeFiles:
            FileListView(
                title: "Large Files",
                summary: "Files of 100 MB or more in your home folder.",
                safety: .review,
                symbol: "doc.on.doc.fill",
                color: Theme.largeFiles,
                items: store.largeFiles,
                deletesPermanently: false
            )
        case .apps:
            AppsView()
        case .category(let id):
            if let category = store.categories.first(where: { $0.id == id }) {
                FileListView(
                    title: category.name,
                    summary: category.summary,
                    safety: category.safety,
                    symbol: category.symbol,
                    color: category.color,
                    items: category.items,
                    deletesPermanently: category.deletesPermanently
                )
            } else {
                OverviewView(selection: $selection)
            }
        }
    }

    @ViewBuilder private var scanButton: some View {
        if store.isScanning {
            Button { store.cancelScan() } label: { Label("Stop", systemImage: "stop.fill") }
                .help("Stop scanning")
        } else {
            Button { store.startScan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                .help("Scan this Mac")
        }
    }

    private var removalErrorShown: Binding<Bool> {
        Binding(get: { store.removalError != nil }, set: { if !$0 { store.removalError = nil } })
    }
}

/// Navigation list with a size next to every finding.
@MainActor
struct SidebarView: View {
    @EnvironmentObject private var store: ScanStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                row("Overview", symbol: "chart.pie.fill", color: .accentColor, size: nil)
                    .tag(SidebarItem.overview)
                row("Large Files", symbol: "doc.on.doc.fill", color: Theme.largeFiles, size: store.largeFilesSize)
                    .tag(SidebarItem.largeFiles)
                row("Applications", symbol: "square.grid.2x2.fill", color: Theme.apps,
                    size: store.apps.isEmpty ? nil : store.appsSize,
                    busy: store.isMeasuringApps)
                    .tag(SidebarItem.apps)
            }
            if !store.nonEmptyCategories.isEmpty {
                Section("Cleanup") {
                    ForEach(store.nonEmptyCategories) { category in
                        row(category.name, symbol: category.symbol, color: category.color, size: category.totalSize)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .tag(SidebarItem.category(category.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut, value: store.nonEmptyCategories.count)
    }

    private func row(_ title: String, symbol: String, color: Color, size: Int64?, busy: Bool = false) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.mini)
            } else if let size = size, size > 0 {
                Text(size.formattedBytes)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Brief confirmation after a removal, with the space freed.
@MainActor
struct FreedToast: View {
    let notice: ScanStore.FreedNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.permanently ? "Freed \(notice.bytes.formattedBytes)" : "\(notice.bytes.formattedBytes) moved to the Trash")
                    .font(.headline)
                Text(notice.permanently
                     ? "\(notice.count) items deleted."
                     : "\(notice.count) items. Empty the Trash to get the space back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}
