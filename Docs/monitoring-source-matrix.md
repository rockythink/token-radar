# Token Radar Monitoring Source Matrix

Token Radar starts with no monitor items. Users add one monitor at a time, first choosing the provider and then whether they are a subscription user or an API user. Only the fields required for that identity are shown.

API user monitors collect provider credentials, resource identifiers where needed, budget settings, and an optional local proxy switch. Subscription monitors reserve browser/OAuth login as the correct account connection path and can optionally add local proxy capture for this Mac.

Many macOS developer machines already run Surge, Clash, Mihomo, or another network proxy. Token Radar treats those as network egress proxies, not as the LLM capture proxy. The capture proxy can forward upstream traffic through macOS system proxy, direct connection, HTTP/HTTPS proxy, or SOCKS proxy.

## Real Account Test Path

Token Radar now treats real account testing as the default path. Runtime sample loaders are not exposed in the app. If an earlier build created demo monitors, the Monitoring page includes a cleanup action that removes demo monitor targets and records with the `token-radar-demo` project label.

| Path | What it verifies |
| --- | --- |
| Provider card `Test Connection` | Reads the API key from Keychain, calls the provider's official usage/balance endpoint, stores the returned snapshot locally, and refreshes the dashboard. |
| Local Proxy `Real Request Test` | Starts the local proxy when needed, sends one non-streaming OpenAI-compatible request through `localhost`, verifies the upstream response contains `usage`, and records a local proxy usage row. |
| Monitor item creation | Saves the user's real provider configuration and credential, then routes all following refresh/proxy actions through that account. |

## Refresh Behavior

Token Radar uses a mixed refresh model:

| Source | Refresh behavior |
| --- | --- |
| Local proxy | Request-driven. A matching non-streaming request is recorded as soon as the upstream response includes `usage`. |
| Codex and Claude Code local logs | Near real-time. The app watches `~/.codex/sessions` and `~/.claude/projects` for directory and `.jsonl` file changes, debounces events, then imports new local records and quota snapshots. |
| Official provider usage/billing APIs | Optional polling. Users can enable automatic provider refresh and choose a 15 minute to 6 hour interval in Settings. Provider-side reporting can still lag behind real traffic. |
| Manual subscription plans | User-maintained. They update when the user edits the plan or when matched local records change the computed usage. |

OpenAI API usage/cost testing requires a key with access to the Organization usage/cost endpoints. ChatGPT/Codex consumer subscription quota is a separate product surface. For Codex, Token Radar auto-detects the local CLI/session state and creates an `OpenAI Codex` monitor item without asking the user to enter API settings. It reads the local `~/.codex/sessions/**/*.jsonl` snapshots written by the official Codex client: `payload.rate_limits` updates 5-hour and weekly remaining quota, while `payload.info.last_token_usage` imports historical token activity for the dashboard. A direct ChatGPT backend usage call remains experimental because it is not a documented public OpenAI API.

## Quota Windows

Subscription and coding-plan limits are not a single monthly number. Token Radar models them as one monitor item with zero or more stacked quota windows:

| Window | Why it exists | Current product behavior |
| --- | --- | --- |
| 5-hour / short session | Claude Pro, Claude Code, ChatGPT/Gemini short-window limits, and similar capacity controls. | Codex reads official-client local `rate_limits`; other providers use local proxy/CLI logs or manual fallback until stable auth exists. |
| Daily | API free tiers, model-specific daily message limits, gateway/day quotas. | Used for request, message, token, or USD quotas. |
| Weekly | ChatGPT thinking/reasoning limits, Claude Code weekly caps, Copilot weekly token/session limits. | Used alongside short windows on the same monitor item; Codex session logs expose both general and model-specific weekly windows. |
| Monthly | Subscription allowances, premium request buckets, account credits, or user-defined monthly budgets. | Still shown separately from monthly spend budget. |
| Custom hours | Provider-specific windows such as 3-hour or 60-minute model limits. | User-defined hour count, tracked with the same calculator. |

Units can be messages, tokens, requests, or USD. Consumer subscriptions remain best-effort unless a provider exposes a stable authorized endpoint; the UI should say when a value is a local estimate, this-device-only capture, or official remote data.

## Coverage Levels

| Coverage | Meaning | Product wording |
| --- | --- | --- |
| Official remote data | Provider or gateway exposes usage, credits, request logs, or costs through an authenticated API. | Best source when credentials are configured. |
| Delayed remote data | Cloud billing or billing export exists, but cost data can lag behind requests. | Good for monthly control, not for hard real-time blocking. |
| This device only | Local proxy or local CLI logs on the current Mac. | Accurate for this Mac, invisible for other devices and clients that bypass Token Radar. |
| Estimate | Token metadata or subscription quota is converted with local pricing / user-entered plan rules. | Useful for trends and warnings, not invoice reconciliation. |
| Manual | User enters budget/quota/spend manually. | Fallback when no stable API exists. |

## Initial Connectors

| Source | Current implementation | Auth/resource requirement | Notes |
| --- | --- | --- | --- |
| OpenAI API | Organization costs endpoint, budget-derived remaining quota. | Admin API key. | Costs reconcile better than granular usage for financial reporting. |
| Anthropic API | Admin Messages usage report, cost estimated from local price catalog. | Anthropic Admin API key. | Tokens can be grouped by workspace, model, API key where available. |
| OpenRouter | Key endpoint for credit limit, remaining credits, and usage. | API key. | Exact remaining credits when `limit_remaining` is present. |
| Vercel AI Gateway | `/v1/credits` endpoint and dashboard observability model/project/API key logs. | AI Gateway API key or Vercel OIDC token. | Generation-level details require generation IDs. |
| Cloudflare AI Gateway | Logs API, parsed by model/provider/tokens/cost/status. | Cloudflare API token plus `account_id/gateway_id`. | Request-level logs are official gateway data. |
| Cloudflare Workers AI | Delayed cloud billing / dashboard Neuron usage. | Cloudflare account access; future billing export integration. | Workers AI bills in Neurons, not direct token dollars. |
| Gemini API | Cloud Billing / AI Studio usage; proxy token metadata estimate. | Google project billing setup for official cost view. | Billing data can appear with delay. |
| Local OpenAI-compatible proxy | `/v1/chat/completions` and `/v1/responses` capture on this Mac. | Provider API key stored in Keychain. | Only sees requests routed through Token Radar on the current device. |
| Network egress proxy | macOS system proxy, direct, HTTP/HTTPS, or SOCKS. | Optional host/port for manual modes. | Lets Token Radar coexist with Surge/Clash instead of replacing them. |
| Claude Code local logs | Reads `~/.claude/projects/**/*.jsonl`. | Local filesystem access. | Mirrors the local-log approach used by ccusage-style tools; other coding CLIs need source-specific adapters. |
| Codex subscription quota + activity | Auto-detects Codex CLI/auth/session state and reads `~/.codex/sessions/**/*.jsonl` `payload.rate_limits` plus `payload.info.last_token_usage`. | Local filesystem access after Codex has run on this Mac. | Automatically creates an `OpenAI Codex` monitor item, syncs general/model-specific 5-hour and weekly remaining quota, and imports local historical token activity at zero variable API cost. |
| Consumer subscriptions | Manual plan, local logs, future browser/OAuth auth. | Browser/OAuth when implemented. | ChatGPT Plus/Pro and Claude Pro/Max still need source-specific adapters because public billing APIs do not expose all consumer quota windows. |

## References Checked

- OpenAI Usage and Costs API: https://platform.openai.com/docs/api-reference/usage/cost
- OpenAI API rate limits: https://platform.openai.com/docs/guides/rate-limits
- OpenAI Codex issue requesting non-interactive `/status`: https://github.com/openai/codex/issues/10233
- codex-cli-usage reference implementation: https://github.com/wakamex/codex-cli-usage
- ChatGPT model usage limits: https://help.openai.com/en/articles/11909943-gpt-53-and-gpt-54-in-chatgpt
- Anthropic Admin Messages Usage Report: https://docs.anthropic.com/zh-CN/api/admin-api/usage-cost/get-messages-usage-report
- Claude Pro plan usage: https://support.claude.com/en/articles/8324991-about-claude-s-pro-plan-usage
- Claude Code with Pro/Max plan: https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan
- OpenRouter Limits API: https://openrouter.ai/docs/api-reference/limits/
- Vercel AI Gateway Usage and Billing: https://vercel.com/docs/ai-gateway/usage
- Vercel AI Gateway Observability: https://vercel.com/docs/ai-gateway/capabilities/observability/
- Cloudflare AI Gateway Logs API: https://developers.cloudflare.com/api/resources/ai_gateway/subresources/logs/
- Cloudflare AI Gateway spend limits: https://developers.cloudflare.com/ai-gateway/features/spend-limits/
- Cloudflare Workers AI limits: https://developers.cloudflare.com/workers-ai/platform/limits/
- Cloudflare Workers AI Pricing: https://developers.cloudflare.com/workers-ai/platform/pricing/
- Gemini API Billing: https://ai.google.dev/gemini-api/docs/billing/
- Gemini API rate limits: https://ai.google.dev/gemini-api/docs/rate-limits
- Claude Code usage/error guidance: https://code.claude.com/docs/en/errors
- GitHub Copilot request allowances: https://docs.github.com/en/copilot/concepts/billing/copilot-requests
- GitHub Copilot usage limits: https://docs.github.com/en/copilot/concepts/usage-limits
- GitHub Billing Usage API, including Copilot usage reporting: https://docs.github.com/en/rest/billing/usage
- ccusage local CLI usage analysis: https://ccusage.com/
- cc-switch provider switching reference: https://github.com/adithya-13/cc-switch
- cc-switch-web local SQLite/provider/proxy inspiration: https://github.com/Laliet/cc-switch-web
- Langfuse token and cost tracking model: https://langfuse.com/docs/model-usage-and-cost/
