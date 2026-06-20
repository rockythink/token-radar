import SwiftUI
import TokenRadarCore

struct ProxyView: View {
    @ObservedObject var store: AppStore
    @State private var testModel = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("nav.proxy"))
                            .font(.system(size: 26, weight: .semibold))
                        Text(store.t("proxy.subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.toggleProxy()
                    } label: {
                        Label(store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"), systemImage: store.isProxyRunning ? "pause.circle" : "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ProxyStat(title: store.t("proxy.status"), value: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"), symbol: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle")
                        ProxyStat(title: store.t("proxy.endpoint"), value: "http://localhost:\(store.settings.proxyPort)", symbol: "network")
                        ProxyStat(title: store.t("proxy.upstream"), value: store.settings.defaultProxyProvider.displayName, symbol: "arrow.up.right.circle")
                    }

                    Divider()

                    Text(store.t("proxy.supported_paths"))
                        .font(.headline)
                    HStack {
                        CodePill(text: "/v1/chat/completions")
                        CodePill(text: "/v1/responses")
                    }

                    Text(store.t("proxy.streaming_note"))
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: store.t("live_test.proxy_title"), subtitle: store.t("live_test.proxy_subtitle"))
                        HStack(spacing: 10) {
                            TextField(store.t("live_test.model"), text: $testModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                            Button {
                                Task { await store.runProxyLiveTest(model: testModel) }
                            } label: {
                                Label(store.t("live_test.send_real_request"), systemImage: "paperplane")
                            }
                            .disabled(store.proxyLiveTestResult?.status == .running)
                        }
                        if let result = store.proxyLiveTestResult {
                            LiveTestStatusView(result: result)
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: store.t("proxy.tracked_ranking"), subtitle: store.t("proxy.tracked_ranking_subtitle"))
                    ForEach(ModelCatalog.imageRanking) { model in
                        HStack(spacing: 8) {
                            ProviderIconView(provider: model.provider, size: 20)
                            Text(model.displayName)
                                .frame(width: 130, alignment: .leading)
                            Text(model.defaultModelID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.provider.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(24)
        }
        .onAppear {
            if testModel.isEmpty {
                testModel = store.defaultProxyTestModel()
            }
        }
        .onChange(of: store.settings.defaultProxyProvider) { _, _ in
            testModel = store.defaultProxyTestModel()
        }
    }
}

struct ProxyStat: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodePill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
