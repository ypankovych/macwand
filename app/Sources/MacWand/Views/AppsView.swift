import SwiftUI

/// Installed apps with their support files, sortable by size and last use.
@MainActor
struct AppsView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var selection = Set<AppInfo.ID>()
    @State private var sortOrder = [KeyPathComparator(\AppInfo.totalSize, order: .reverse)]
    @State private var onlyUnused = false
    @State private var confirming = false

    private var visibleApps: [AppInfo] {
        (onlyUnused ? store.unusedApps : store.apps).sorted(using: sortOrder)
    }
    private var selectedApps: [AppInfo] { store.apps.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if store.apps.isEmpty {
                    placeholder
                } else {
                    table
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActionBar(
                    count: selectedApps.count,
                    size: selectedApps.reduce(0) { $0 + $1.totalSize },
                    actionTitle: "Uninstall",
                    action: { confirming = true }
                )
            }
        }
        .navigationTitle("Applications")
        .confirmationDialog(confirmationTitle, isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                let targets = selectedApps
                selection.removeAll()
                Task { await store.uninstall(targets) }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "square.grid.2x2.fill", color: Theme.apps, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        AnimatedBytes(bytes: store.appsSize,
                                      font: .system(size: 28, weight: .bold, design: .rounded))
                        Text("\(store.apps.count) apps · \(store.unusedApps.count) unused").font(.callout).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                Text("Uninstalling moves the app and the files it keeps in ~/Library to the Trash.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Toggle("Only apps not used in 3 months", isOn: $onlyUnused.animation(.easeInOut))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
            if store.apps.count >= 2 {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 12) {
                        legend(Theme.apps, "App")
                        legend(Theme.supportFiles, "Support files")
                    }
                    SizeBars(bars: topBars)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(LinearGradient(colors: [Theme.apps.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var topBars: [SizeBar] {
        visibleApps.sorted { $0.totalSize > $1.totalSize }.prefix(6).map { app in
            SizeBar(id: app.id, name: app.name, segments: [
                .init(bytes: app.size, color: Theme.apps),
                .init(bytes: app.leftoversSize, color: Theme.supportFiles),
            ])
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var table: some View {
        Table(visibleApps, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { app in
                HStack(spacing: 8) {
                    FileIcon(url: app.url, size: 20)
                    Text(app.name)
                }
            }
            .width(min: 160, ideal: 220)
            TableColumn("Last Used", value: \.lastUsedSortKey) { app in
                Text(app.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "Unknown")
                    .foregroundStyle(app.isUnused ? .orange : .secondary)
            }
            .width(105)
            TableColumn("App", value: \.size) { app in
                sizeText(app.size)
            }
            .width(80)
            TableColumn("Support Files", value: \.leftoversSize) { app in
                sizeText(app.leftoversSize)
                    .help(app.leftovers.map(\.url.path.abbreviatingHome).joined(separator: "\n"))
            }
            .width(95)
            TableColumn("Total", value: \.totalSize) { app in
                sizeText(app.totalSize).font(.body.weight(.medium))
            }
            .width(80)
        }
        .selectionMenu(
            reveal: { ids in
                NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0, isDirectory: true) })
            },
            removeTitle: "Uninstall…",
            remove: { ids in
                selection = ids
                confirming = true
            }
        )
    }

    @ViewBuilder private var placeholder: some View {
        if store.isScanning {
            ProgressView(store.isMeasuringApps ? "Measuring apps…" : "Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: "No Apps Yet", symbol: "square.grid.2x2", message: "Run a scan to list installed apps.")
        }
    }

    private func sizeText(_ size: Int64) -> some View {
        Text(size > 0 ? size.formattedBytes : "—")
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var confirmationTitle: String {
        let apps = selectedApps
        let noun = apps.count == 1 ? apps[0].name : "\(apps.count) apps"
        return "Uninstall \(noun) (\(apps.reduce(0) { $0 + $1.totalSize }.formattedBytes))?"
    }

    private var confirmationMessage: String {
        let leftovers = selectedApps.flatMap(\.leftovers).map(\.url.path.abbreviatingHome)
        let list = leftovers.prefix(8).joined(separator: "\n")
        let more = leftovers.count > 8 ? "\n…and \(leftovers.count - 8) more" : ""
        let files = leftovers.isEmpty ? "" : "\n\nAlso moves:\n\(list)\(more)"
        return "Apps that are running are skipped. You can put everything back from the Trash.\(files)"
    }
}
