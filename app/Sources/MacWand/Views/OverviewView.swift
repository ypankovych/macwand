import SwiftUI

/// One non-overlapping slice of reclaimable space, linked to where it can be cleaned.
struct Finding: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let size: Int64
    let detail: String
    let destination: SidebarItem
}

/// Disk usage, scan status, a chart of reclaimable space and a tile per finding.
@MainActor
struct OverviewView: View {
    @EnvironmentObject private var store: ScanStore
    @Binding var selection: SidebarItem?

    var body: some View {
        let findings = findings
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let disk = store.disk {
                    DiskBar(disk: disk, reclaimable: store.reclaimableSize)
                }
                if !store.hasFullDiskAccess { FullDiskAccessBanner() }
                hero(findings)
                if !findings.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(findings) { finding in
                            Button { selection = finding.destination } label: {
                                FindingTile(finding: finding, share: share(of: finding))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .animation(.lively, value: findings.count)
                }
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }

    @ViewBuilder private func hero(_ findings: [Finding]) -> some View {
        switch store.phase {
        case .idle where store.categories.isEmpty:
            WelcomeHero { store.startScan() }
        case .scanning:
            ScanningHero(files: store.scannedFiles, bytes: store.scannedBytes, path: store.currentPath,
                         found: store.reclaimableSize, title: "Scanning your Mac…")
        case .finished where store.isMeasuringApps:
            ScanningHero(files: store.scannedFiles, bytes: store.scannedBytes, path: "Reading app details",
                         found: store.reclaimableSize, title: "Measuring apps…")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        default:
            ReclaimableCard(findings: findings, total: store.reclaimableSize, footnote: footnote, selection: $selection)
        }
    }

    private var footnote: String {
        guard case .finished(let elapsed, let unreadable) = store.phase else {
            return "Scan stopped — showing what was found so far."
        }
        let seconds = String(format: "%.1f s", elapsed)
        let skipped = unreadable > 0 ? " · \(unreadable) folders unreadable" : ""
        return "\(store.scannedFiles.formatted()) files · \(store.scannedBytes.formattedBytes) checked in \(seconds)\(skipped)"
    }

    /// Non-overlapping findings, largest first.
    private var findings: [Finding] {
        var findings = store.nonEmptyCategories.map { category in
            Finding(id: category.id, title: category.name, symbol: category.symbol, color: category.color,
                    size: category.totalSize, detail: "\(category.items.count) items", destination: .category(category.id))
        }
        let loose = store.looseLargeFiles
        if !loose.isEmpty {
            findings.append(Finding(id: "large", title: "Large Files", symbol: "doc.on.doc.fill", color: Theme.largeFiles,
                                    size: loose.reduce(0) { $0 + $1.size }, detail: "\(loose.count) files over 100 MB",
                                    destination: .largeFiles))
        }
        let unused = store.unusedApps
        if !unused.isEmpty {
            findings.append(Finding(id: "apps", title: "Unused Apps", symbol: "square.grid.2x2.fill", color: Theme.apps,
                                    size: unused.reduce(0) { $0 + $1.totalSize }, detail: "\(unused.count) not used in 3 months",
                                    destination: .apps))
        }
        return findings.sorted { $0.size > $1.size }
    }

    private func share(of finding: Finding) -> Double {
        let total = store.reclaimableSize
        return total > 0 ? Double(finding.size) / Double(total) : 0
    }
}

// MARK: - Heroes

/// First-launch call to action.
@MainActor
private struct WelcomeHero: View {
    let onScan: () -> Void
    @State private var glow = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 120, height: 120)
                    .blur(radius: glow ? 34 : 22)
                    .opacity(glow ? 0.75 : 0.45)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .pulsing()
            }
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glow)
            .onAppear { glow = true }

            VStack(spacing: 6) {
                Text("Find what's taking up space")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Large files, caches, old downloads, build folders and apps you no longer use.\nNothing is removed until you choose, and it goes to the Trash first.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(action: onScan) {
                Label("Scan My Mac", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Live scan progress with a radar animation.
@MainActor
private struct ScanningHero: View {
    let files: Int64
    let bytes: Int64
    let path: String
    let found: Int64
    let title: String

    var body: some View {
        HStack(spacing: 28) {
            Radar()
                .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                HStack(spacing: 28) {
                    stat("Files checked", Text(files.formatted()))
                    stat("Data checked", Text(bytes.formattedBytes))
                    stat("Can be freed", Text(found.formattedBytes).foregroundStyle(Theme.reclaimable))
                }
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(_ label: String, _ value: some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Expanding rings and a sweeping beam behind a magnifier.
@MainActor
private struct Radar: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { ring in
                    let phase = (t / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Theme.brand, lineWidth: 2)
                        .scaleEffect(0.3 + phase * 0.7)
                        .opacity(1 - phase)
                }
                Circle()
                    .fill(AngularGradient(gradient: Gradient(colors: [.clear, Color.accentColor.opacity(0.45)]), center: .center))
                    .rotationEffect(.degrees(t * 140))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.brand, in: Circle())
            }
            // Rasterize on the GPU in one pass; redrawn ~30 times a second.
            .drawingGroup()
        }
    }
}

// MARK: - Results

/// Donut chart of reclaimable space with an interactive legend.
@MainActor
private struct ReclaimableCard: View {
    let findings: [Finding]
    let total: Int64
    let footnote: String
    @Binding var selection: SidebarItem?

    @State private var hovered: String?
    @State private var appeared = false

    private var highlighted: Finding? { findings.first { $0.id == hovered } }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            Donut(findings: findings, hovered: $hovered, onSelect: { selection = $0.destination }) {
                donutCenter
            }
            .frame(width: 230, height: 230)
            .scaleEffect(appeared ? 1 : 0.7)
            .rotationEffect(.degrees(appeared ? 0 : -60))
            .opacity(appeared ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to clean").font(.headline).foregroundStyle(.secondary)
                AnimatedBytes(bytes: total, font: .system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.reclaimable)
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
                ForEach(findings.prefix(7)) { finding in
                    legendRow(finding)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            withAnimation(.entrance) { appeared = true }
        }
    }

    @ViewBuilder private var donutCenter: some View {
        VStack(spacing: 2) {
            if let highlighted = highlighted {
                Image(systemName: highlighted.symbol).foregroundStyle(highlighted.color)
                Text(highlighted.size.formattedBytes)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(highlighted.title).font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles").foregroundStyle(Theme.reclaimable)
                Text("\(findings.count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("findings").font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: 120)
    }

    private func legendRow(_ finding: Finding) -> some View {
        Button { selection = finding.destination } label: {
            HStack(spacing: 8) {
                Circle().fill(finding.color.soft).frame(width: 9, height: 9)
                Text(finding.title)
                Spacer(minLength: 16)
                Text(finding.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(hovered == finding.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320)
        .onHover { inside in
            if inside { hovered = finding.id } else if hovered == finding.id { hovered = nil }
        }
    }
}

/// A donut chart drawn with shapes. Hovering a slice highlights it, clicking opens it.
@MainActor
private struct Donut<Center: View>: View {
    let findings: [Finding]
    @Binding var hovered: String?
    let onSelect: (Finding) -> Void
    @ViewBuilder let center: () -> Center

    /// Start and end of each slice as fractions of the full circle.
    private var slices: [(finding: Finding, start: Double, end: Double)] {
        let total = Double(max(1, findings.reduce(0) { $0 + $1.size }))
        var start = 0.0
        return findings.map { finding in
            let end = start + Double(finding.size) / total
            defer { start = end }
            return (finding, start, end)
        }
    }

    private var innerRatio: CGFloat { 0.64 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(slices, id: \.finding.id) { slice in
                    let isHot = hovered == slice.finding.id
                    DonutSlice(start: slice.start, end: slice.end, innerRatio: innerRatio)
                        .fill(slice.finding.color.soft)
                        .opacity(hovered == nil || isHot ? 1 : 0.35)
                        .scaleEffect(isHot ? 1.05 : 0.97)
                }
                center()
            }
            .contentShape(Rectangle())
            // Slices overlap as full-size views, so hit-test by angle and radius instead
            // of per-slice hover, which would always report the topmost slice.
            .onPointerMove { point in
                hovered = point.flatMap { finding(at: $0, in: geometry.size)?.id }
            }
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                if let finding = finding(at: value.location, in: geometry.size) { onSelect(finding) }
            })
        }
        .animation(.lively, value: hovered)
    }

    /// The slice under `point`, or nil for the hole and the outside.
    private func finding(at point: CGPoint, in size: CGSize) -> Finding? {
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        let radius = (dx * dx + dy * dy).squareRoot()
        let outer = min(size.width, size.height) / 2
        guard radius >= outer * innerRatio, radius <= outer * 1.05 else { return nil }
        // Fraction of a turn, clockwise from 12 o'clock, matching DonutSlice.
        var turn = atan2(Double(dx), Double(-dy)) / (2 * .pi)
        if turn < 0 { turn += 1 }
        return slices.first { turn >= $0.start && turn < $0.end }?.finding
    }
}

extension View {
    /// Reports the pointer location while it's over the view, nil when it leaves (macOS 13+;
    /// on macOS 12 the legend still highlights slices).
    @ViewBuilder func onPointerMove(_ action: @escaping (CGPoint?) -> Void) -> some View {
        if #available(macOS 13, *) {
            onContinuousHover { phase in
                switch phase {
                case .active(let point): action(point)
                case .ended: action(nil)
                }
            }
        } else {
            self
        }
    }
}

/// One ring segment, from `start` to `end` (fractions of a turn, clockwise from 12 o'clock).
private struct DonutSlice: Shape {
    let start: Double
    let end: Double
    let innerRatio: CGFloat
    /// Gap between slices, in degrees.
    var gap: Double = 1.6

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let span = (end - start) * 360
        let inset = min(gap / 2, span / 4)
        let from = Angle.degrees(start * 360 - 90 + inset)
        let to = Angle.degrees(end * 360 - 90 - inset)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A clickable card summarizing one finding.
@MainActor
private struct FindingTile: View {
    let finding: Finding
    let share: Double
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SymbolBadge(symbol: finding.symbol, color: finding.color, size: 34)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .offset(x: hovering ? 3 : 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.headline)
                AnimatedBytes(bytes: finding.size, font: .system(size: 24, weight: .bold, design: .rounded))
                Text(finding.detail).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(finding.color.opacity(0.15))
                    Capsule().fill(finding.color.soft)
                        .frame(width: max(4, geometry.size.width * share))
                }
            }
            .frame(height: 5)
            .animation(.lively, value: share)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(finding.color.opacity(hovering ? 0.55 : 0), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.06), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.lively, value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering = $0 }
    }
}

// MARK: - Disk

/// Startup disk usage, with the reclaimable part of "used" called out.
@MainActor
private struct DiskBar: View {
    let disk: DiskInfo
    let reclaimable: Int64
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Macintosh HD", systemImage: "internaldrive.fill").font(.title3.weight(.semibold))
                Spacer()
                AnimatedBytes(bytes: disk.available, font: .title3.weight(.semibold))
                Text("free of \(disk.total.formattedBytes)").foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let usedWidth = width * disk.usedFraction * (appeared ? 1 : 0)
                let reclaimWidth = min(usedWidth, width * fraction(reclaimable))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(usedColor.soft).frame(width: usedWidth)
                    // The reclaimable slice sits at the end of the used segment.
                    Rectangle()
                        .fill(Theme.reclaimable)
                        .frame(width: reclaimWidth)
                        .offset(x: usedWidth - reclaimWidth)
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
            .animation(.entrance, value: appeared)
            .animation(.lively, value: reclaimable)
            HStack(spacing: 16) {
                legend(usedColor, "Used \(disk.used.formattedBytes)")
                if reclaimable > 0 { legend(Theme.reclaimableDot, "Can be freed \(reclaimable.formattedBytes)") }
                legend(Color.secondary.opacity(0.4), "Free \(disk.available.formattedBytes)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear { appeared = true }
    }

    private func fraction(_ bytes: Int64) -> Double {
        disk.total > 0 ? Double(bytes) / Double(disk.total) : 0
    }

    private var usedColor: Color {
        switch disk.usedFraction {
        case ..<0.75: return Theme.apps
        case ..<0.9: return .orange
        default: return .red
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).monospacedDigit()
        }
    }
}

/// Explains why some folders are skipped and links to the privacy setting.
@MainActor
private struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: "lock.shield.fill", color: .orange, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Full Disk Access for a complete scan").font(.headline)
                Text("Without it, macOS hides Mail, Safari and some app data from MacWand.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
