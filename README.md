# Gym Lib

A deliberately simple, mobile-first exercise finder. Move through three focused stages: choose muscles, select equipment or reuse a saved preset, then browse visual matching exercises from the bundled dataset.

## Local development

```bash
bun install
bun run dev
```

Run the full validation suite with:

```bash
bun run typecheck
bun run lint
bun run test
bun run build
```

## iOS app

The same web build ships as a native iOS app through Capacitor. `dist` is
bundled into the app, so it runs fully offline with no server URL.

```bash
bun run ios        # build, sync, and open Xcode
bun run ios:run    # build, sync, and run on a simulator or device
bun run ios:sync   # build and copy the web assets into the Xcode project
bun run ios:archive # build a Release .xcarchive for distribution
bun run ios:export  # export the archive as an App Store .ipa
```

To install on a device, open the project with `bun run ios`, pick your iPhone
as the run destination, and press Run. Signing is already configured for the
`Daniil Hirchyts` team (`89NA3C53R8`) with bundle ID `com.hirchyts.gymlib`.
The first install also needs the developer certificate trusted on the phone,
under Settings → General → VPN & Device Management.

Anything that changes the web app needs a `bun run ios:sync` before it shows
up in the native shell.

The app icon is an Icon Composer document at `ios/App/App/AppIcon.icon` — open
it with Icon Composer (bundled in Xcode) to edit the layers. Xcode renders the
default, dark, and tinted appearances from it at build time, so there is no
`AppIcon.appiconset` to keep in sync.

The launch screen is a real storyboard — `ios/App/App/Base.lproj/LaunchScreen.storyboard`
— showing the logo, wordmark and a spinner on the app background, with the
logo art in the `SplashLogo` image set. Do not run `capacitor-assets` against
this project: it rewrites that storyboard and would replace the loading screen
with a bare centred image.

### TestFlight

Distribution is wired up: the App ID `com.hirchyts.gymlib` is registered, an
Apple Distribution certificate and App Store profile exist, and
`ios/ExportOptions.plist` targets team `89NA3C53R8`.
`ITSAppUsesNonExemptEncryption` is declared `false` in `App/Info.plist`, so
builds skip the export-compliance prompt — Gym Lib has no backend and no
custom cryptography.

Uploads authenticate with an App Store Connect API key. Keep the `.p8` in
`~/.appstoreconnect/private_keys/` (never in the repo) and export the two
identifiers before uploading:

```bash
export ASC_KEY_ID=<key id>
export ASC_ISSUER=<issuer id>

bun run ios:archive
bun run ios:export
bun run ios:upload
```

Bump `CURRENT_PROJECT_VERSION` for every upload — App Store Connect rejects a
build number it has already seen.

Inside the native shell, haptics call straight into UIKit's feedback
generators; the web build keeps using the Vibration API and the Safari
switch-overlay fallback in `src/lib/haptics.ts`.

Gym Lib uses React, TypeScript, Vite, Tailwind CSS, shadcn/ui, and Zustand. It has no backend and stores filter selections and equipment presets only in the browser's local storage.

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for dataset and anatomy-map attribution.

## Deterministic training engine

The independent offline TypeScript engine lives in `src/training`; no UI or
persistence migration is required to run it. Start with
[the architecture and API](docs/training-engine/ARCHITECTURE.md),
[scientific evidence](docs/training-engine/EVIDENCE.md), and
[supported boundaries](docs/training-engine/LIMITATIONS.md).

```bash
bun run training:example
bun run training:test
bun run training:audit
bun run training:benchmark
```
