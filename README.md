# Token Radar

![Token Radar logo](Assets/Brand/TokenRadar/png/token-radar-logo-128.png)

Token Radar is a local-first macOS menu bar app for independent developers who
want a clearer view of AI model spend, token usage, remaining quota, and budget
risk across API providers, gateways, coding CLIs, and subscription-style plans.

The app is built with SwiftUI and Swift Package Manager. It stores credentials
in macOS Keychain, usage records in local SQLite storage, and settings on the
current Mac.

> Status: early preview. Core monitoring flows are usable, but provider coverage
> and subscription quota support are still evolving.

## Why

AI usage is now split across API keys, gateways, coding assistants, CLI tools,
and subscriptions. Provider dashboards are useful, but they are fragmented,
delayed, and usually do not answer simple local questions:

- How much did this Mac spend today?
- Which model burned the most tokens?
- How much quota is left before the next reset?
- Which traffic is official provider data, local capture, or only an estimate?

Token Radar makes those sources visible in one local app.

## Current Capabilities

- Native macOS menu bar app with SwiftUI dashboard, monitoring, proxy, provider,
  and settings views.
- Budget ring, spend and token trends, provider distribution, model ranking,
  quota runway, and source coverage summaries.
- Local SQLite usage storage and Keychain-backed provider credentials.
- UI language support for English, Simplified Chinese, and Traditional Chinese.
- Read-only provider connectors and parsers for OpenAI, Anthropic, OpenRouter,
  Vercel AI Gateway, Cloudflare AI Gateway logs, DeepSeek, and estimate modes
  for Gemini, Cloudflare Workers AI, and OpenAI-compatible providers.
- Local OpenAI-compatible capture proxy for `/v1/chat/completions` and
  `/v1/responses`.
- Network egress proxy compatibility for macOS system proxy, direct connection,
  HTTP/HTTPS proxy, and SOCKS proxy.
- Local Claude Code JSONL import from `~/.claude/projects`.
- Local Codex JSONL import from `~/.codex/sessions`, including quota snapshots
  when the official client writes rate limit metadata.
- Subscription plan calculation for monthly fees, included quota, reset windows,
  amortized cost, projected overage, and stacked quota windows.

See [Docs/monitoring-source-matrix.md](Docs/monitoring-source-matrix.md) for
the coverage matrix, refresh behavior, auth requirements, and source
limitations.

## Privacy Model

Token Radar does not require a hosted backend.

- API credentials are stored in macOS Keychain.
- Usage records are stored locally.
- Local session imports read files on this Mac only.
- The local proxy only sees clients explicitly routed through Token Radar.
- Official provider refreshes call the provider APIs you configure.

Read [PRIVACY.md](PRIVACY.md) before routing real traffic or connecting provider
credentials.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- Swift 5.10 or newer

## Build and Run

Run the core checks:

```bash
./script/test.sh
```

Build the package:

```bash
swift build
```

Build and launch the local app bundle:

```bash
./script/build_and_run.sh
```

Launch and verify the app process started:

```bash
./script/build_and_run.sh --verify
```

## Development

The package has three targets:

- `TokenRadar`: SwiftUI macOS app.
- `TokenRadarCore`: shared models, provider parsers, storage, proxy core,
  calculators, and local session importers.
- `TokenRadarCoreChecks`: executable checks for core behavior.

Read [Docs/architecture.md](Docs/architecture.md) for the module map and data
flow.

## Contributing

Issues and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first.

Important contribution rules:

- Do not include real API keys, account tokens, private session logs, provider
  secrets, or personal billing data.
- Keep provider integrations read-only unless the change is explicitly about
  local capture or local settings.
- Update the monitoring source matrix when provider coverage changes.

## Security

Please report suspected vulnerabilities privately. See
[SECURITY.md](SECURITY.md).

## Trademark Notice

Token Radar is independent and is not affiliated with, endorsed by, or sponsored
by any provider shown in the app. Provider names, logos, product names, and
trademarks belong to their respective owners. See [NOTICE](NOTICE) and
[TRADEMARKS.md](TRADEMARKS.md).

## License

Token Radar is released under the [MIT License](LICENSE).
