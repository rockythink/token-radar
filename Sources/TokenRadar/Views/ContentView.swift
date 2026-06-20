import SwiftUI
import TokenRadarCore

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            switch store.selectedSection {
            case .overview:
                DashboardView(store: store)
            case .monitoring:
                MonitoringView(store: store)
            case .providers:
                ProvidersView(store: store)
            case .proxy:
                ProxyView(store: store)
            case .settings:
                SettingsView(store: store, isEmbedded: true)
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: AppStore

    private let primarySections: [DashboardSection] = [.overview, .monitoring]
    private let configurationSections: [DashboardSection] = [.settings]

    var body: some View {
        List(selection: $store.selectedSection) {
            Section(store.t("sidebar.workspace")) {
                ForEach(primarySections) { section in
                    Label(localizedTitle(for: section), systemImage: section.symbol)
                        .tag(section)
                }
            }

            Section(store.t("sidebar.configuration")) {
                ForEach(configurationSections) { section in
                    Label(localizedTitle(for: section), systemImage: section.symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .tag(section)
                }
            }

            Section {
                SidebarStatusPanel(store: store)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    }

    private func localizedTitle(for section: DashboardSection) -> String {
        switch section {
        case .overview:
            store.t("nav.overview")
        case .monitoring:
            store.t("nav.monitoring")
        case .providers:
            store.t("nav.providers")
        case .proxy:
            store.t("nav.proxy")
        case .settings:
            store.t("nav.settings")
        }
    }
}

private struct SidebarStatusPanel: View {
    @ObservedObject var store: AppStore

    private var enabledMonitorCount: Int {
        store.settings.monitorTargets.filter(\.isEnabled).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.t("sidebar.status"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(store.isProxyRunning ? .green : .secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
            }

            HStack {
                sidebarMetric(
                    title: store.t("sidebar.monitors"),
                    value: "\(enabledMonitorCount)/\(store.settings.monitorTargets.count)"
                )
                Divider()
                    .frame(height: 26)
                sidebarMetric(
                    title: store.t("sidebar.fixed"),
                    value: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD)
                )
            }

            HStack(spacing: 6) {
                Image(systemName: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(store.isProxyRunning ? .green : .secondary)
                Text(store.isProxyRunning ? store.t("sidebar.proxy_on") : store.t("sidebar.proxy_off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private func sidebarMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
