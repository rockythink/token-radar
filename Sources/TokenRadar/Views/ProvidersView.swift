import SwiftUI
import TokenRadarCore

struct ProvidersView: View {
    @ObservedObject var store: AppStore

    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("nav.providers"))
                            .font(.system(size: 26, weight: .semibold))
                        Text(store.t("providers.subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshAllProviders() }
                    } label: {
                        Label(store.t("menu.refresh"), systemImage: "arrow.clockwise")
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ProviderKind.allCases) { provider in
                        ProviderCardView(
                            provider: provider,
                            configuration: store.providerConfiguration(for: provider),
                            snapshot: store.snapshots[provider],
                            summary: store.providerSummary(for: provider),
                            hasCredential: store.credentialState[provider] == true,
                            officialText: store.t("providers.official"),
                            estimateText: store.t("providers.estimate"),
                            credentialSavedText: store.t("providers.credential_saved"),
                            noCredentialText: store.t("providers.no_credential"),
                            enabledText: store.t("providers.enabled"),
                            disabledText: store.t("providers.disabled"),
                            readyBillingText: store.t("providers.ready_billing"),
                            proxyEstimateText: store.t("providers.proxy_estimate"),
                            liveTestResult: store.providerLiveTestResults[provider],
                            testConnectionText: store.t("live_test.test_connection"),
                            onTestConnection: {
                                Task { await store.testProviderConnection(provider) }
                            }
                        )
                    }
                }
            }
            .padding(24)
        }
    }
}

struct ProviderCardView: View {
    var provider: ProviderKind
    var configuration: ProviderConfiguration
    var snapshot: ProviderUsageSnapshot?
    var summary: BudgetSummary
    var hasCredential: Bool
    var officialText: String
    var estimateText: String
    var credentialSavedText: String
    var noCredentialText: String
    var enabledText: String
    var disabledText: String
    var readyBillingText: String
    var proxyEstimateText: String
    var liveTestResult: LiveTestResult?
    var testConnectionText: String
    var onTestConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProviderIconView(provider: provider, size: 26)
                Text(provider.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(MoneyFormatter.usd(summary.monthSpendUSD))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(MoneyFormatter.usd(summary.remainingBudgetUSD))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(hasCredential ? credentialSavedText : noCredentialText, systemImage: hasCredential ? "key.fill" : "key")
                Label(configuration.isEnabled ? enabledText : disabledText, systemImage: configuration.isEnabled ? "checkmark.circle" : "circle")
                Label(confidenceText, systemImage: "scope")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = snapshot?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Button(action: onTestConnection) {
                    Label(testConnectionText, systemImage: "bolt.horizontal.circle")
                }
                .disabled(liveTestResult?.status == .running)
                Spacer()
            }
            .buttonStyle(.bordered)

            if let liveTestResult {
                LiveTestStatusView(result: liveTestResult)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 222, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        if !hasCredential { return .secondary }
        if configuration.isEnabled { return .green }
        return .orange
    }

    private var confidenceText: String {
        snapshot?.quotaConfidence.displayName ?? (provider.supportsProviderBillingAPI ? readyBillingText : proxyEstimateText)
    }
}
