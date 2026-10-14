import SwiftUI

/// App entry point: a single window driven by one `ScanStore`.
@main
@MainActor
struct MacWandApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup("MacWand") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 920, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan") { store.startScan() }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning)
                Button("Stop Scan") { store.cancelScan() }
                    .keyboardShortcut(".")
                    .disabled(!store.isScanning)
            }
        }
    }
}

/// Quits when the window closes: MacWand is a single-window utility.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
