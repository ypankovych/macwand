import SwiftUI

/// Colors and shared styling for findings, so charts, tiles and the sidebar agree.
enum Theme {
    static let largeFiles = Color(red: 0.98, green: 0.45, blue: 0.35)
    static let apps = Color(red: 0.36, green: 0.52, blue: 0.98)
    static let supportFiles = Color(red: 0.66, green: 0.40, blue: 0.98)
    static let reclaimableDot = Color(red: 0.75, green: 0.37, blue: 0.80)
    static let reclaimable = LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.98), Color(red: 0.95, green: 0.38, blue: 0.62)],
                                            startPoint: .leading, endPoint: .trailing)
    static let brand = LinearGradient(colors: [Color(red: 0.42, green: 0.27, blue: 0.95), Color(red: 0.13, green: 0.55, blue: 0.98)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Card fill that works in light and dark mode.
    static let card = Color.primary.opacity(0.05)

    /// Accent color for a cleanup category.
    static func color(forCategory id: String) -> Color {
        switch id {
        case "user_caches": return Color(red: 0.20, green: 0.70, blue: 0.95)
        case "logs": return Color(red: 0.55, green: 0.60, blue: 0.68)
        case "xcode", "xcode_archives", "simulators": return Color(red: 0.25, green: 0.55, blue: 1.00)
        case "package_caches": return Color(red: 0.96, green: 0.70, blue: 0.20)
        case "ios_backups": return Color(red: 0.45, green: 0.80, blue: 0.45)
        case "mail_downloads": return Color(red: 0.30, green: 0.75, blue: 0.85)
        case "downloads": return Color(red: 0.20, green: 0.78, blue: 0.62)
        case "trash": return Color(red: 0.62, green: 0.62, blue: 0.66)
        case "dev_artifacts": return supportFiles
        default: return .accentColor
        }
    }
}

extension CleanupCategory {
    var color: Color { Theme.color(forCategory: id) }
}

extension Color {
    /// A soft top-to-bottom gradient of the color (like `Color.gradient`, which needs macOS 13).
    var soft: LinearGradient {
        LinearGradient(colors: [opacity(0.78), self], startPoint: .top, endPoint: .bottom)
    }
}

extension Animation {
    /// Quick, slightly bouncy motion used across the app.
    static let lively = Animation.spring(response: 0.45, dampingFraction: 0.8)
    /// Slower entrance motion for charts and bars.
    static let entrance = Animation.spring(response: 0.8, dampingFraction: 0.85)
}

// MARK: - Version compatibility

extension View {
    /// Rolls digits when the text changes (macOS 13+); a plain update on older systems.
    @ViewBuilder func rollingDigits(_ enabled: Bool = true) -> some View {
        if #available(macOS 13, *), enabled {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    /// Repeating pulse on SF Symbols (macOS 14+).
    @ViewBuilder func pulsing() -> some View {
        if #available(macOS 14, *) {
            symbolEffect(.pulse, options: .repeating)
        } else {
            self
        }
    }

    /// Runs `action` now and whenever `value` changes, without the deprecation
    /// warning the single-argument `onChange` raises on macOS 14.
    @ViewBuilder func onChangeAndAppear<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14, *) {
            onChange(of: value, initial: true) { action() }
        } else {
            onAppear(perform: action).onChange(of: value) { _ in action() }
        }
    }
}

/// Placeholder for an empty list (stands in for `ContentUnavailableView`, macOS 14+).
struct EmptyState: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared pieces

/// An SF Symbol on a soft colored circle, used for tiles and legends.
struct SymbolBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.soft, in: Circle())
            .shadow(color: color.opacity(0.35), radius: 4, y: 2)
    }
}

private struct LiveUpdatingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a scan streams results. Numbers then change several times a second,
    /// and rolling-digit transitions (rasterized on the CPU) are skipped.
    var isLiveUpdating: Bool {
        get { self[LiveUpdatingKey.self] }
        set { self[LiveUpdatingKey.self] = newValue }
    }
}

/// Byte count that rolls its digits when it changes, except during live updates.
struct AnimatedBytes: View {
    let bytes: Int64
    var font: Font = .title2.weight(.semibold)
    @Environment(\.isLiveUpdating) private var isLiveUpdating

    var body: some View {
        Text(bytes.formattedBytes)
            .font(font)
            .monospacedDigit()
            .rollingDigits(!isLiveUpdating)
            .animation(isLiveUpdating ? nil : .lively, value: bytes)
    }
}

/// A row in `SizeBars`: a label and one or more colored segments.
struct SizeBar: Identifiable {
    struct Segment {
        let bytes: Int64
        let color: Color
    }

    let id: String
    let name: String
    let segments: [Segment]

    var total: Int64 { segments.reduce(0) { $0 + $1.bytes } }
}

/// Horizontal size bars that grow in when shown.
struct SizeBars: View {
    let bars: [SizeBar]
    @State private var progress = 0.0

    var body: some View {
        let maxTotal = max(1, bars.map(\.total).max() ?? 1)
        VStack(spacing: 7) {
            ForEach(bars) { bar in
                HStack(spacing: 10) {
                    Text(bar.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 150, alignment: .trailing)
                    GeometryReader { geometry in
                        let full = geometry.size.width * CGFloat(bar.total) / CGFloat(maxTotal) * progress
                        HStack(spacing: 0) {
                            ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                                Rectangle()
                                    .fill(segment.color.soft)
                                    .frame(width: bar.total > 0 ? full * CGFloat(segment.bytes) / CGFloat(bar.total) : 0)
                            }
                        }
                        .frame(width: max(full, 3), alignment: .leading)
                        .clipShape(Capsule())
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)
                    Text(bar.total.formattedBytes)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .onAppear {
            withAnimation(.entrance) { progress = 1 }
        }
    }
}
