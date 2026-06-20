# Token Radar Brand Assets

This folder contains reusable logo assets for Token Radar.

## Source

- `source/token-radar-app-icon.svg`: editable full-color app icon source.
- `source/token-radar-symbol-template.svg`: single-color symbol source for menu bar, favicon, docs, or template rendering.
- `concept/ai-generated-concept.png`: generated visual direction used as a concept reference.

## Exported PNG

- `png/token-radar-logo-16.png`
- `png/token-radar-logo-32.png`
- `png/token-radar-logo-64.png`
- `png/token-radar-logo-128.png`
- `png/token-radar-logo-256.png`
- `png/token-radar-logo-512.png`
- `png/token-radar-logo-1024.png`
- `png/token-radar-symbol-16.png`
- `png/token-radar-symbol-32.png`
- `png/token-radar-symbol-64.png`
- `png/token-radar-symbol-128.png`
- `png/token-radar-symbol-256.png`
- `png/token-radar-symbol-512.png`
- `png/token-radar-symbol-1024.png`
- `png/token-radar-symbol-white-16.png`
- `png/token-radar-symbol-white-32.png`
- `png/token-radar-symbol-white-64.png`
- `png/token-radar-symbol-white-128.png`
- `png/token-radar-symbol-white-256.png`
- `png/token-radar-symbol-white-512.png`
- `png/token-radar-symbol-white-1024.png`

## macOS

- `macOS/TokenRadar.icns`: icon file used by the local app bundle.
- `macOS/TokenRadar.iconset/`: source iconset for `iconutil`.
- `macOS/TokenRadar.appiconset/`: Xcode-ready AppIcon set for future migration to an `.xcassets` project.

## Notes

- The full-color icon should be used for app stores, app bundles, marketing images, and large surfaces.
- The black single-color symbol should be used as a template source or on light backgrounds.
- The white single-color symbol should be used on dark backgrounds.
- Keep the SVG files as the source of truth and run `./export-assets.sh` from this directory after changing the design.
