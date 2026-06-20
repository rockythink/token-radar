# Contributing

Thanks for considering a contribution to Token Radar.

## Local setup

Requirements:

- macOS 14 or newer
- Xcode command line tools
- Swift 5.10 or newer

Run the core checks:

```bash
./script/test.sh
```

Build the app:

```bash
swift build
```

Build and launch the local app bundle:

```bash
./script/build_and_run.sh --verify
```

## Project layout

- `Sources/TokenRadar`: SwiftUI macOS app, menu bar UI, dashboard, settings,
  monitoring screens, localization, and app orchestration.
- `Sources/TokenRadarCore`: provider parsers, proxy core, storage, budget and
  quota calculators, session log importers, and shared models.
- `Sources/TokenRadarCoreChecks`: executable checks for parsers, calculators,
  proxy parsing, session importers, and SQLite round trips.
- `Docs`: product and monitoring source documentation.
- `Assets`: Token Radar brand assets and app icons.

## Pull request expectations

- Keep provider integrations read-only unless the change is explicitly about
  local capture or local settings.
- Store credentials only in Keychain.
- Do not add real provider responses, account identifiers, keys, tokens, or
  private session logs to fixtures.
- Update `Docs/monitoring-source-matrix.md` when a monitoring source changes.
- Add or update `TokenRadarCoreChecks` coverage for parsing, quota, storage, or
  proxy behavior changes.

## Coding style

Follow the existing Swift style in the touched files. Prefer small, explicit
types over broad helper abstractions unless the code path is shared by several
providers or UI surfaces.
