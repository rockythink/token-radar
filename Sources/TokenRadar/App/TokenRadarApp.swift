import AppKit
import SwiftUI
import TokenRadarCore

@main
struct TokenRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var store = AppStore.live()

    var body: some Scene {
        WindowGroup("Token Radar", id: "dashboard") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .id(store.settings.language.rawValue)
                .task {
                    await store.bootstrap()
                }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(store.t("menu.settings")) {
                    openDashboard(section: .settings)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Token Radar") {
                Button("Refresh Providers") {
                    Task { await store.refreshAllProviders() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(store.isProxyRunning ? "Pause Proxy" : "Start Proxy") {
                    store.toggleProxy()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button(store.t("menu.settings")) {
                    openDashboard(section: .settings)
                }
            }
        }

        MenuBarExtra {
            MenuBarView(store: store)
                .id(store.settings.language.rawValue)
        } label: {
            MenuBarLabelView(store: store)
                .id(store.settings.language.rawValue)
        }
        .menuBarExtraStyle(.window)
    }

    private func openDashboard(section: DashboardSection) {
        store.selectedSection = section
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
