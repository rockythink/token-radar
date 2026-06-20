# Privacy

Token Radar is designed as a local-first macOS menu bar app for monitoring AI
model spend, token usage, quota windows, and budget risk.

## What stays local

- API credentials are stored in macOS Keychain.
- Usage records are stored in a local SQLite database.
- Settings are stored in local app support files.
- Local Codex and Claude Code imports read files on this Mac only.
- The local capture proxy only sees requests explicitly routed through Token
  Radar on this Mac.

## What can leave your Mac

Token Radar can call official provider usage, billing, credit, or gateway log
APIs when you configure provider credentials and trigger refreshes. Those
requests go to the provider you configured.

Token Radar does not run a hosted backend for telemetry, analytics, account
sync, or remote storage.

## Local proxy scope

The local proxy is opt-in and only records request metadata needed for usage
accounting when traffic is routed through Token Radar. It does not observe web
subscriptions, other devices, or API clients that bypass the proxy.

## Data removal

To remove local data, delete the app's local settings and SQLite files from
your macOS user account, and remove saved provider credentials from Keychain.
