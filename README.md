# RAUTA

A native SwiftUI training app for iPhone, with a Live Activity widget and an
embedded watchOS companion. It runs fully offline and has no backend.

The Xcode project is `ios/Rauta/Rauta.xcodeproj`:

| Target | Folder | Bundle ID |
|---|---|---|
| Rauta (iPhone) | `ios/Rauta/Rauta` | `com.hirchyts.gymlib` |
| RautaWidgets (Live Activity) | `ios/Rauta/RautaWidgets` | `com.hirchyts.gymlib.GymLibWidgets` |
| RautaWatch | `ios/Rauta/RautaWatch` | `com.hirchyts.gymlib.watchkitapp` |

`ios/Rauta/Shared` and `ios/Rauta/WatchShared` hold code shared between targets.
Bundled exercise data, fonts and the app icon live in `ios/Rauta/Rauta/Resources`,
and exercise, equipment and goal media in `ios/Rauta/Media`.

The app needs the iOS/watchOS 27 SDKs bundled with **Xcode Beta**; the regular
Xcode cannot build the embedded watch app.

The original React/Capacitor web app, and the TypeScript training engine and
catalogue tooling the Swift code was ported from, now live in a separate
`gym-lib-react` folder.

## Run

```bash
scripts/ios-run.sh sim       # the iPhone 18 Pro Swift simulator
scripts/ios-run.sh device    # the connected iPhone
scripts/ios-run.sh test      # RautaTests on the simulator (--only <Suite> for one suite)
```

Builds are incremental and kept in `build/ios/<sim|device>/`. Run
`scripts/ios-run.sh --help` for every option.

Signing is automatic for team `89NA3C53R8`. When `ASC_KEY_ID` and `ASC_ISSUER`
are set, in the environment or in an untracked `.env.ios` at the repo root, device
builds sign with the App Store Connect API key, so a new iPhone is registered
without an Xcode account login.

### Force the onboarding flow

Debug builds accept a `--onboarding` launch argument that forces the onboarding
route on every launch without deleting the training profile or app data:

```bash
scripts/ios-run.sh sim --arg --onboarding
```

In Xcode, add it under Product → Scheme → Edit Scheme → Run → Arguments →
"Arguments Passed On Launch" for the `Rauta` scheme.

### RAUTA agent debug arguments

Debug builds also take these, each applied once the launch intro has played:

| Argument | Effect |
|---|---|
| `--agent-chat` | Opens the chat with RAUTA. |
| `--agent-prompt "<text>"` | Opens the chat and sends `<text>`. |
| `--agent-demo <page>` | Opens the chat on a sample conversation, held in memory only; the saved conversation and training data are untouched. `0` a swap with Undo and a plan preview, `1` facts, exercises and a Health request, `2` a week's schedule, `3` RAUTA mid-turn, then its answer landing, `4` the empty chat. |
| `--rauta-menu` | Opens RAUTA's tab-bar menu. |
| `--policies` | Opens Settings → Policies & credits, even before onboarding. |
| `--agent-lab [--agent-lab-autorun] [--agent-lab-only <id>]` | The on-device model bench (see `docs/research/agent-model-spike-2026-09-26.md`). |

On the simulator the agent thinks with Apple's on-device model when the Mac
has Apple Intelligence. On an iPhone it uses the downloaded MLX model.

### Licences in Settings

Settings → Policies & credits lists every Swift package and bundled font with
its licence text, from `ios/Rauta/Rauta/Lib/OpenSourceNotices.swift`. The file
is generated; after adding or updating a package or a font, build once and run:

```bash
scripts/generate-open-source-notices.py
```

## TestFlight

```bash
ASC_KEY_ID=<key id> ASC_ISSUER=<issuer id> scripts/release-testflight.sh
```

The script picks the next free build number from App Store Connect, archives,
exports with `ios/ExportOptions.plist`, validates, uploads, and waits for
processing. `--dry-run` stops after validation. Keep the `.p8` key in
`~/.appstoreconnect/private_keys/` and never in the repo.

`ITSAppUsesNonExemptEncryption` is `false` in `ios/Rauta/Config/Rauta-Info.plist`,
so builds skip the export-compliance prompt.

## App icon

The iPhone and watch icons are Icon Composer documents at
`ios/Rauta/Rauta/Resources/AppIcon.icon` and `ios/Rauta/RautaWatch/AppIcon.icon`.
The source document and its exports are in `icon/`.
