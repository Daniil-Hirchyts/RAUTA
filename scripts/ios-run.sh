#!/usr/bin/env bash
#
# Build, install and launch the native Rauta iOS app on a simulator or on a
# real iPhone, in one command. Incremental: the build folder is kept, so a run
# after a small change takes seconds, not minutes.
#
#   scripts/ios-run.sh sim                    # the iPhone 18 Pro Swift simulator
#   scripts/ios-run.sh device                 # the connected iPhone
#
# Options:
#   --no-build              install and launch the last build as it is
#   --no-launch             build and install, but do not launch
#   --release               Release configuration (default: Debug)
#   --console               stay attached to the app's output (Ctrl-C detaches)
#   --verbose               stream the whole xcodebuild log, not just the issues
#   --name <name>           simulator name (default: $RAUTA_SIM or "iPhone 18 Pro Swift")
#   --udid <udid>           simulator or iPhone UDID (default iPhone: $RAUTA_DEVICE,
#                           otherwise the first connected physical iPhone)
#   --appearance <mode>     simulator only: set its system appearance, light or dark
#   --env KEY=VALUE         environment variable for the launched app (repeatable)
#   --arg <value>           launch argument for the app (repeatable),
#                           e.g. --arg --onboarding
#   --clean                 start from an empty build folder
#
# Build output lives in build/ios/<sim|device>/, and the full log of the last
# build in build/ios/<sim|device>/build.log.
#
# Device builds sign automatically with the project's team. When ASC_KEY_ID and
# ASC_ISSUER are set — in the environment or in an untracked .env.ios at the repo
# root — the App Store Connect API key signs instead of an Xcode account, so a
# new iPhone is registered and its profile refreshed with no Xcode login.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/ios/Rauta/Rauta.xcodeproj"
SCHEME="Rauta"
BUNDLE_ID="com.hirchyts.gymlib"
APP_NAME="Rauta.app"

# Rauta needs the iOS/watchOS 27 SDKs bundled with Xcode Beta. Keep the
# caller's explicit choice, otherwise prefer Xcode Beta when present.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode Beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode Beta.app/Contents/Developer"
fi

if [[ -f "$ROOT/.env.ios" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env.ios"
  set +a
fi

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }
usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET="${1:-}"
case "$TARGET" in
  sim|device) shift ;;
  -h|--help) usage; exit 0 ;;
  "") usage; exit 2 ;;
  *) fail "unknown target: $TARGET (use sim or device)" ;;
esac

BUILD=true
LAUNCH=true
CONFIG="Debug"
CONSOLE=false
VERBOSE=false
CLEAN=false
SIM_NAME="${RAUTA_SIM:-iPhone 18 Pro Swift}"
UDID=""
APPEARANCE=""
APP_ENV=()
APP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=false; shift ;;
    --no-launch) LAUNCH=false; shift ;;
    --release) CONFIG="Release"; shift ;;
    --console) CONSOLE=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --clean) CLEAN=true; shift ;;
    --name) SIM_NAME="${2:?--name needs a simulator name}"; shift 2 ;;
    --udid) UDID="${2:?--udid needs a UDID}"; shift 2 ;;
    --appearance) APPEARANCE="${2:?--appearance needs light or dark}"; shift 2 ;;
    --env)
      [[ "${2:-}" == *=* ]] || fail "--env needs KEY=VALUE"
      APP_ENV+=("$2"); shift 2 ;;
    --arg) APP_ARGS+=("${2:?--arg needs a value}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

if [[ "$TARGET" == device && -z "$UDID" ]]; then UDID="${RAUTA_DEVICE:-}"; fi
if [[ -n "$APPEARANCE" && "$TARGET" != sim ]]; then fail "--appearance only applies to the simulator"; fi
if [[ -n "$APPEARANCE" && "$APPEARANCE" != light && "$APPEARANCE" != dark ]]; then
  fail "--appearance must be light or dark"
fi

BUILD_DIR="$ROOT/build/ios/$TARGET"
DERIVED="$BUILD_DIR/DerivedData"
LOG="$BUILD_DIR/build.log"
# Reuse the packages Xcode already resolved for the project when they are
# there; otherwise keep our own copy beside the build.
PACKAGES="$ROOT/ios/Rauta/build/DerivedData/SourcePackages"
[[ -d "$PACKAGES/checkouts" ]] || PACKAGES="$ROOT/build/ios/SourcePackages"
STARTED=$(date +%s)

# MARK: - Targets

resolve_simulator() {
  if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
name = sys.argv[1]
matches = [
    device
    for runtime, devices in json.load(sys.stdin)["devices"].items()
    if "iOS" in runtime
    for device in devices
    if device["name"] == name
]
matches.sort(key=lambda device: device["state"] != "Booted")
print(matches[0]["udid"] if matches else "")
' "$SIM_NAME")"
    [[ -n "$UDID" ]] || fail "no available simulator named \"$SIM_NAME\" (see: xcrun simctl list devices available)"
  fi
  local state
  state="$(xcrun simctl list devices --json | python3 -c '
import json, sys
udid = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == udid:
            print(device["state"])
' "$UDID")"
  [[ -n "$state" ]] || fail "no simulator with UDID $UDID"
  if [[ "$state" != "Booted" ]]; then
    step "Boot simulator"
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b >/dev/null
  fi
  # Show the device window without taking focus. Xcode 27 replaced the
  # Simulator app with DeviceHub; a missing viewer never fails the run.
  if ! pgrep -x Simulator >/dev/null && ! pgrep -x DeviceHub >/dev/null; then
    open -g -a Simulator 2>/dev/null || open -g -a DeviceHub 2>/dev/null || true
  fi
  if [[ -n "$APPEARANCE" ]]; then xcrun simctl ui "$UDID" appearance "$APPEARANCE"; fi
  echo "simulator $SIM_NAME ($UDID)"
}

resolve_device() {
  local listing
  listing="$(mktemp)"
  xcrun devicectl list devices --json-output "$listing" >/dev/null 2>&1 \
    || fail "could not list devices (is Xcode Beta installed?)"
  local found
  found="$(python3 - "$listing" "$UDID" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
wanted = sys.argv[2]
phones = []
for device in devices:
    hardware = device.get("hardwareProperties", {})
    if hardware.get("reality") != "physical" or hardware.get("deviceType") != "iPhone":
        continue
    connection = device.get("connectionProperties", {})
    phones.append((
        hardware.get("udid", ""),
        device.get("deviceProperties", {}).get("name", "iPhone"),
        connection.get("tunnelState", ""),
        connection.get("pairingState", ""),
    ))
if wanted:
    phones = [phone for phone in phones if phone[0] == wanted]
phones.sort(key=lambda phone: phone[2] != "connected")
if phones:
    print("\t".join(phones[0]))
PY
)"
  rm -f "$listing"
  [[ -n "$found" ]] || fail "no paired physical iPhone found${UDID:+ with UDID $UDID} (see: xcrun devicectl list devices)"
  local name tunnel pairing
  IFS=$'\t' read -r UDID name tunnel pairing <<<"$found"
  [[ "$pairing" == "paired" ]] || fail "$name is not paired with this Mac"
  echo "iPhone $name ($UDID, $tunnel)"
}

# MARK: - Build

build() {
  local destination
  if [[ "$TARGET" == sim ]]; then
    destination="platform=iOS Simulator,id=$UDID"
  else
    destination="platform=iOS,id=$UDID"
  fi

  local signing=()
  if [[ "$TARGET" == device ]]; then
    signing+=(-allowProvisioningUpdates)
    local key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"
    if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER:-}" && -f "$key" ]]; then
      signing+=(
        -authenticationKeyPath "$key"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER"
      )
    fi
  fi

  if [[ "$CLEAN" == true ]]; then rm -rf "$BUILD_DIR"; fi
  mkdir -p "$BUILD_DIR"

  step "Build ($CONFIG)"
  local status=0
  if [[ "$VERBOSE" == true ]]; then
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
      -destination "$destination" -derivedDataPath "$DERIVED" \
      -clonedSourcePackagesDirPath "$PACKAGES" -skipPackagePluginValidation \
      ${signing[@]+"${signing[@]}"} 2>&1 | tee "$LOG" || status=$?
  else
    # Only what needs a person: errors, warnings in our own sources, signing
    # trouble, and the verdict. Everything else is in the log.
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
      -destination "$destination" -derivedDataPath "$DERIVED" \
      -clonedSourcePackagesDirPath "$PACKAGES" -skipPackagePluginValidation \
      ${signing[@]+"${signing[@]}"} >"$LOG" 2>&1 || status=$?
    grep -E "error:|/ios/Rauta/.*warning:|[Pp]rovisioning profile|[Ss]igning for|\*\* BUILD" "$LOG" \
      | grep -v "^note:" | sort -u || true
  fi
  if [[ $status -ne 0 ]]; then
    fail "build failed — full log: $LOG"
  fi
}

app_path() {
  local platform
  if [[ "$TARGET" == sim ]]; then platform="iphonesimulator"; else platform="iphoneos"; fi
  echo "$DERIVED/Build/Products/$CONFIG-$platform/$APP_NAME"
}

# MARK: - Install and launch

install_and_launch() {
  local app
  app="$(app_path)"
  [[ -d "$app" ]] || fail "no build at $app — run without --no-build first"

  step "Install"
  if [[ "$TARGET" == sim ]]; then
    xcrun simctl install "$UDID" "$app"
  else
    xcrun devicectl device install app --device "$UDID" "$app" >/dev/null
  fi
  echo "installed $app"

  [[ "$LAUNCH" == true ]] || return 0

  step "Launch"
  local prefix child_env=()
  if [[ "$TARGET" == sim ]]; then prefix="SIMCTL_CHILD_"; else prefix="DEVICECTL_CHILD_"; fi
  local pair
  for pair in ${APP_ENV[@]+"${APP_ENV[@]}"}; do child_env+=("$prefix$pair"); done

  if [[ "$TARGET" == sim ]]; then
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    if [[ "$CONSOLE" == true ]]; then
      echo "attached to $BUNDLE_ID — Ctrl-C to detach"
      exec env ${child_env[@]+"${child_env[@]}"} xcrun simctl launch --console-pty \
        "$UDID" "$BUNDLE_ID" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
    fi
    env ${child_env[@]+"${child_env[@]}"} xcrun simctl launch \
      "$UDID" "$BUNDLE_ID" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
  else
    if [[ "$CONSOLE" == true ]]; then
      echo "attached to $BUNDLE_ID — Ctrl-C to detach"
      exec env ${child_env[@]+"${child_env[@]}"} xcrun devicectl device process launch \
        --device "$UDID" --terminate-existing --console \
        "$BUNDLE_ID" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
    fi
    env ${child_env[@]+"${child_env[@]}"} xcrun devicectl device process launch \
      --device "$UDID" --terminate-existing \
      "$BUNDLE_ID" ${APP_ARGS[@]+"${APP_ARGS[@]}"} >/dev/null
    echo "launched $BUNDLE_ID"
  fi
}

step "Target"
if [[ "$TARGET" == sim ]]; then resolve_simulator; else resolve_device; fi
if [[ "$BUILD" == true ]]; then build; fi
install_and_launch
printf '\n\033[32mdone in %ss\033[0m\n' "$(( $(date +%s) - STARTED ))"
