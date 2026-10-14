// Renders README screenshots of the real UI with demo scan results, without scanning
// anything or showing windows on screen: windows are placed off-screen and captured
// directly. Run via scripts/screenshots.sh.
import AppKit
import SwiftUI

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots")
let home = NSHomeDirectory()
let gigabyte: Double = 1_000_000_000

/// Replays a fixed set of engine events instead of scanning the disk.
struct DemoEngine: ScanEngine {
    func scan() -> AsyncThrowingStream<[EngineEvent], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LineReader().consume(Data(demoLines().joined(separator: "\n").appending("\n").utf8)))
            continuation.finish()
        }
    }

    func sizes(of paths: [String]) -> AsyncThrowingStream<[EngineEvent], Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

func json(_ object: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

/// Seconds since 1970 for a date `days` ago.
func ago(_ days: Double) -> Int { Int(Date().timeIntervalSince1970 - days * 86_400) }

func demoLines() -> [String] {
    let categories: [(String, String, String, String)] = [
        ("user_caches", "App Caches", "Per-app caches in ~/Library/Caches. Apps rebuild them as needed.", "safe"),
        ("logs", "Logs", "Application and diagnostic logs.", "safe"),
        ("xcode", "Xcode Data", "DerivedData, old device support files and simulator caches.", "safe"),
        ("package_caches", "Package Caches", "npm, pnpm, Cargo, Gradle, Maven, Go and pip/uv download caches.", "safe"),
        ("downloads", "Downloads", "Everything in your Downloads folder.", "review"),
        ("trash", "Trash", "Items already in the Trash. Removing them deletes them permanently.", "safe"),
        ("dev_artifacts", "Build Artifacts", "node_modules, Rust targets, Python virtualenvs and similar folders that rebuild from source.", "safe"),
    ]
    var lines = categories.map { json(["type": "category", "id": $0.0, "name": $0.1, "description": $0.2, "safety": $0.3]) }

    func item(_ category: String, _ path: String, _ gb: Double, _ days: Double, _ label: String? = nil) {
        var object: [String: Any] = ["type": "category_item", "category": category, "path": home + "/" + path,
                                     "size": Int(gb * gigabyte), "modified": ago(days)]
        if let label { object["label"] = label }
        lines.append(json(object))
    }
    item("dev_artifacts", "Projects/api-gateway/target", 3.1, 12, "Rust target")
    item("dev_artifacts", "Projects/ml-experiments/.venv", 2.3, 95, "Python virtualenv")
    item("dev_artifacts", "Projects/storefront/node_modules", 1.42, 3, "node_modules")
    item("dev_artifacts", "Projects/analytics/.venv", 1.1, 140, "Python virtualenv")
    item("dev_artifacts", "Projects/design-system/node_modules", 0.96, 30, "node_modules")
    item("dev_artifacts", "Projects/mobile-app/Pods", 0.82, 60, "CocoaPods")
    item("dev_artifacts", "Projects/marketing-site/.next", 0.64, 21, "Next.js build")
    item("dev_artifacts", "Projects/infra/.terraform", 0.45, 200, "Terraform providers")
    item("dev_artifacts", "Archive/old-dashboard/node_modules", 0.38, 410, "node_modules")
    item("xcode", "Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)", 5.6, 180)
    item("xcode", "Library/Developer/Xcode/DerivedData/Storefront-bxkqzjv", 4.2, 2)
    item("xcode", "Library/Developer/Xcode/iOS DeviceSupport/16.6 (20G75)", 3.9, 400)
    item("user_caches", "Library/Caches/Homebrew", 2.6, 6)
    item("user_caches", "Library/Caches/com.spotify.client", 1.8, 1)
    item("user_caches", "Library/Caches/Google", 1.2, 1)
    item("user_caches", "Library/Caches/JetBrains", 0.95, 14)
    item("user_caches", "Library/Caches/com.tinyspeck.slackmacgap", 0.68, 1)
    item("logs", "Library/Logs/JetBrains", 0.31, 14)
    item("logs", "Library/Logs/DiagnosticReports", 0.12, 3)
    item("package_caches", ".npm/_cacache", 2.1, 3)
    item("package_caches", ".gradle/caches/modules-2", 1.6, 45)
    item("package_caches", ".cache/uv", 1.4, 9)
    item("package_caches", ".cargo/registry/cache", 0.9, 12)
    item("downloads", "Downloads/Xcode_15.4.xip", 7.8, 120)
    item("downloads", "Downloads/ubuntu-24.04-desktop-arm64.iso", 3.1, 75)
    item("downloads", "Downloads/conference-talk.mov", 2.4, 33)
    item("downloads", "Downloads/photos-export.zip", 1.9, 160)
    item("downloads", "Downloads/Figma-Installer.dmg", 0.41, 210)
    item("trash", ".Trash/Old Project Backup", 3.4, 8)

    func large(_ path: String, _ gb: Double, _ days: Double) {
        lines.append(json(["type": "large_file", "path": home + "/" + path, "size": Int(gb * gigabyte), "modified": ago(days)]))
    }
    large("Documents/Virtual Machines/Windows 11.vmdk", 24, 70)
    large("Movies/Family Trip 2025.mov", 6.2, 50)
    large("Documents/Archive/2023-photos.zip", 4.1, 300)
    large("Music/Logic/Album Stems.zip", 3.6, 140)
    large("Downloads/Xcode_15.4.xip", 7.8, 120)

    lines.append(json(["type": "done", "files": 1_284_512, "bytes": Int(412 * gigabyte), "errors": 0, "elapsed_ms": 6_800]))
    return lines
}

func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Places a window image on a soft wallpaper-like gradient with a drop shadow.
func compose(_ image: CGImage, dark: Bool, padding: Int = 120) -> Data {
    let width = image.width + padding * 2, height = image.height + padding * 2
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = dark
        ? [CGColor(red: 0.10, green: 0.11, blue: 0.26, alpha: 1), CGColor(red: 0.29, green: 0.16, blue: 0.42, alpha: 1)]
        : [CGColor(red: 0.62, green: 0.78, blue: 1.0, alpha: 1), CGColor(red: 0.86, green: 0.76, blue: 1.0, alpha: 1)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(gray: 0, alpha: dark ? 0.6 : 0.35))
    context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

@MainActor
func shoot(_ selection: SidebarItem, store: ScanStore, dark: Bool, name: String) {
    let controller = NSHostingController(rootView: ContentView(initialSelection: selection).environmentObject(store))
    if #available(macOS 14, *) { controller.sceneBridgingOptions = [.toolbars, .title] }
    let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1080, height: 790),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1080, height: 790))
    window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isReleasedWhenClosed = false
    // Key and active, so the window is drawn as focused (colored controls, bright sidebar).
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    pump(2.5)  // let entrance animations finish
    let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                        [.boundsIgnoreFraming, .bestResolution])!
    let url = output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try! compose(image, dark: dark).write(to: url)
    print("wrote \(url.path)")
    window.close()
}

@MainActor
func render() {
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let disk = DiskInfo(total: Int64(994.66 * gigabyte), available: Int64(152.4 * gigabyte))
    let store = ScanStore(engine: DemoEngine(), disk: { disk }, fullDiskAccess: { true })
    store.startScan()
    while store.isScanning || store.categories.isEmpty { pump(0.1) }

    for dark in [false, true] {
        shoot(.overview, store: store, dark: dark, name: "overview")
        shoot(.category("dev_artifacts"), store: store, dark: dark, name: "build-artifacts")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated { render() }
