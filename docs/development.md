# Development guide

Everything needed to build, run, test and ship RAUTA. The [README](../README.md) covers what the app is
and how it works.

1. [Requirements](#1-requirements)
2. [Build and run](#2-build-and-run)
3. [Signing](#3-signing)
4. [Tests](#4-tests)
5. [Debug launch arguments](#5-debug-launch-arguments)
6. [Generated files](#6-generated-files)
7. [TestFlight](#7-testflight)

## 1. Requirements

- **Xcode Beta** with the iOS 27 and watchOS 27 SDKs. The release Xcode cannot build the embedded watch app.
- An Apple Silicon Mac. On the simulator, RAUTA's free-form answers use Apple's on-device model, which needs
  Apple Intelligence enabled on the Mac. Without it, every request the intent router recognises still works.
- For the language model itself: an iPhone with at least 6 GB of RAM (measured on an iPhone 14 Pro Max).
- Python 3 with Pillow, fontTools, numpy and scipy, only to regenerate the files in [section 6](#6-generated-files).

The Xcode project is `ios/Rauta/Rauta.xcodeproj`. Swift packages resolve on the first build.

| Target | Folder | Bundle ID |
|---|---|---|
| Rauta (iPhone) | `ios/Rauta/Rauta` | `com.hirchyts.gymlib` |
| RautaWidgets (Live Activity) | `ios/Rauta/RautaWidgets` | `com.hirchyts.gymlib.GymLibWidgets` |
| RautaWatch | `ios/Rauta/RautaWatch` | `com.hirchyts.gymlib.watchkitapp` |
| RautaTests | `ios/Rauta/RautaTests` | |

The bundle IDs keep the project's first name. Changing them would orphan the iCloud key-value data and the
App Store Connect record.

## 2. Build and run

```bash
scripts/ios-run.sh sim       # build, install and launch on the default simulator
scripts/ios-run.sh device    # the connected iPhone
```

Builds are incremental and kept in `build/ios/<sim|device>/`; the full log of the last build is
`build/ios/<sim|device>/build.log`. Useful options:

| Option | Effect |
|---|---|
| `--name <simulator>` | Simulator to use (default `$RAUTA_SIM`, then "iPhone 18 Pro Swift") |
| `--arg <value>` | Launch argument for the app, repeatable (see [section 5](#5-debug-launch-arguments)) |
| `--appearance light\|dark` | Set the simulator's appearance first |
| `--release` | Release configuration |
| `--console` | Stay attached to the app's output |
| `--no-build` | Reinstall and launch the last build |
| `--clean` | Start from an empty build folder |

`scripts/ios-run.sh --help` lists every option.

## 3. Signing

Signing is automatic for team `89NA3C53R8`. When `ASC_KEY_ID` and `ASC_ISSUER` are set, in the environment or in
an untracked `.env.ios` at the repo root, device builds sign with the App Store Connect API key, so a new iPhone
is registered without an Xcode account login. Keep the `.p8` key in `~/.appstoreconnect/private_keys/`, never in
the repo.

To build under your own team, change the team and the bundle ID prefix in the project's signing settings. The
iCloud key-value store identifier in `ios/Rauta/Config/Rauta.entitlements` is derived from the bundle ID.

## 4. Tests

```bash
scripts/ios-run.sh test --name "Rauta Tests"                        # every suite
scripts/ios-run.sh test --name "Rauta Tests" --only PersistenceTests  # one suite, repeatable
```

The suites use Swift Testing (`@Suite`, `@Test`). Tests that touch persistence run through `IsolatedStores`: the
stores point at a throwaway folder for the test and are put back afterwards, a running workout included. The
`--demo-history` and `--demo-workout` arguments below do write real data, so give them a simulator you do not
train on.

The test log and result bundle go to `build/ios/test/`.

## 5. Debug launch arguments

Debug builds read these at launch. Pass them with `--arg`, or in Xcode under Product → Scheme → Edit Scheme →
Run → Arguments for the `Rauta` scheme. Each one applies once the launch intro has played.

### Onboarding

| Argument | Effect |
|---|---|
| `--onboarding` | Forces the onboarding route on every launch, without deleting the profile or any data. |
| `--onboarding-step <step>` | Opens onboarding at one step: `goal`, `experience`, `gym`, `duration`, `days`, `about` or `ready`. |

```bash
scripts/ios-run.sh sim --name "Rauta Tests" --arg --onboarding --arg --onboarding-step days
```

### RAUTA and the agent

| Argument | Effect |
|---|---|
| `--agent-chat` | Opens the chat with RAUTA. |
| `--agent-prompt "<text>"` | Opens the chat and sends `<text>`. |
| `--agent-demo <page>` | Opens the chat on a sample conversation, held in memory only; saved conversations and training data are untouched. `0` a swap with Undo and a plan preview, `1` facts, exercises and a Health request, `2` a week's schedule, `3` RAUTA mid-turn, then its answer landing, `4` the empty chat. |
| `--rauta-menu` | Opens RAUTA's tab-bar menu. |
| `--policies` | Opens Settings → Policies & credits, even before onboarding. |
| `--agent-lab [--agent-lab-autorun] [--agent-lab-only <id>]` | The on-device model bench. Results go to `Documents/agent-lab/<id>.json` in the app container. See the [model spike](research/agent-model-spike-2026-09-26.md). |

On the simulator the agent uses Apple's on-device model. On an iPhone it uses the downloaded MLX model.

### Screenshots and history

| Argument | Effect |
|---|---|
| `--demo-history` | Adds ten weeks of logged push, pull and legs workouts, once; a later launch finds them and adds nothing. |
| `--demo-workout` | Starts a demo workout, for the Lock Screen, the Dynamic Island and the watch. |
| `--summary activity\|time\|streak\|muscles\|records` | Opens that page behind a Summary card. Add `--summary-month 2026-09` for another month. |

```bash
scripts/ios-run.sh sim --name "Rauta Tests" --arg --demo-history --arg --summary --arg activity
```

### Demo clips

The clips in [`docs/demo`](demo) are simulator screen recordings, launched with `--demo-history` and
`--demo-workout`, with the app's data container copied aside first and put back afterwards. Each one is kept as an
MP4 and as an animated WebP for the README:

```bash
xcrun simctl io booted recordVideo --codec=h264 clip.mov          # Ctrl-C to stop
ffmpeg -ss 1 -to 12 -i clip.mov -vf "fps=30,scale=590:-2" -c:v libx264 -crf 27 -pix_fmt yuv420p -an clip.mp4
ffmpeg -ss 1 -to 12 -i clip.mov -vf "fps=20,scale=320:-1" frames/%04d.png
img2webp -loop 0 -lossy -q 72 -d 50 frames/*.png -o clip.webp
```

## 6. Generated files

Four kinds of file in the repo are generated. Edit the source, then regenerate; never edit the output by hand.

### Exercise catalogue

`ios/Rauta/Rauta/Resources/exercises.generated.json` and `exercise-metadata.curated.complete.json` come from the
catalogue tooling in the separate `gym-lib-react` project, which also holds the original TypeScript engine.
Corrections made since the last export live in `Training/DataSource/ReviewedRequirements.swift`. Each one names
the source fingerprint it was reviewed against: if an exercise's name or instructions change upstream, the
correction stops applying and the exercise drops out of automatic planning until someone reviews it again.

### RAUTA on the watch and the Lock Screen

RAUTA is a Rive rig (`ios/Rauta/Media/rauta.riv`, built in the separate `kettlebell-bot` project). RiveRuntime has
no watchOS build and WidgetKit cannot draw its Metal view, so the watch and the Live Activity play frames of the
real rig instead: a sprite sheet per mood for the watch, and timer fonts for the Lock Screen, where stacked
`Text(date, style: .timer)` views in fonts whose digits are frames play the loop with no updates from the app.
After changing the rig:

```bash
python3 scripts/rauta-frames/build.py
```

It needs Pillow, fontTools and the `rive-mcp` renderer on the `PATH`, and writes `RautaWatch/RautaFrames/`,
`RautaWidgets/RautaFonts/`, `RautaWidgets/RautaSpriteFonts.swift` and the fonts list in
`Config/RautaWidgets-Info.plist`. The script's header explains the timing.

### Sounds

```bash
python3 scripts/sounds/packs.py      # every candidate pack, plus a listening page in build/sounds/audition/
python3 scripts/sounds/generate.py   # the chosen sounds, into Resources/Sounds/rauta-<name>.caf
```

Both are deterministic: every noise source is seeded by the sound it belongs to, so a rerun changes nothing in
git. Sounds the app makes on the spot (`Native/SoundSynth.swift`) follow the same recipe as the "Pure" pack.

### Licences

Settings → Policies & credits lists every Swift package and bundled font with its licence text, from
`ios/Rauta/Rauta/Lib/Generated/OpenSourceNotices.swift`. After adding or updating a package or a font, build once
and run:

```bash
scripts/generate-open-source-notices.py
```

## 7. TestFlight

```bash
ASC_KEY_ID=<key id> ASC_ISSUER=<issuer id> scripts/release-testflight.sh
```

The script picks the next free build number from App Store Connect, archives, exports with
`ios/ExportOptions.plist`, validates, uploads and waits for processing. `--dry-run` stops after validation.

`ITSAppUsesNonExemptEncryption` is `false` in `ios/Rauta/Config/Rauta-Info.plist`, so builds skip the
export-compliance prompt.

### App icon

The iPhone and watch icons are Icon Composer documents at `ios/Rauta/Rauta/Resources/AppIcon.icon` and
`ios/Rauta/RautaWatch/AppIcon.icon`. The source document and its exports are in `icon/`.
