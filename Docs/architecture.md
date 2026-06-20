# Architecture

Token Radar is a local-first macOS Swift package with three targets:

- `TokenRadar`: the SwiftUI menu bar app.
- `TokenRadarCore`: shared models, provider integrations, storage, quota
  logic, proxy parsing, and local session importers.
- `TokenRadarCoreChecks`: executable checks that exercise core behavior without
  requiring an Xcode project.

## Data Flow

Usage records can enter the app through four paths:

- local OpenAI-compatible proxy capture
- local Codex and Claude Code JSONL session imports
- official provider usage, billing, credit, or gateway log APIs
- user-defined subscription plans and quota windows

The app stores normalized `UsageRecord` values in local SQLite storage. The UI
derives budget, quota, runway, source coverage, and menu bar summaries from
those records plus the user's local settings.

## Security Boundaries

- Provider credentials are stored in macOS Keychain.
- Provider refreshes are read-only.
- Local session importers read files on this Mac only.
- The local proxy only observes clients explicitly configured to use it.
- Network egress proxy support is separate from capture proxy behavior.

## Provider Support

Provider implementations live under
`Sources/TokenRadarCore/Services/Providers`. Parser coverage should be added to
`Sources/TokenRadarCoreChecks` before new provider UI is exposed.

`Docs/monitoring-source-matrix.md` is the user-facing source of truth for
coverage level, auth requirements, and limitations.
