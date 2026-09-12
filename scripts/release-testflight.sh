#!/usr/bin/env bash
#
# One-shot TestFlight release for the native Rauta iOS app and its embedded
# watchOS companion: pick the next free build number from App Store Connect,
# archive, export, validate, upload, and wait for processing to finish.
#
#   ASC_KEY_ID=... ASC_ISSUER=... ./scripts/release-testflight.sh
#
# Options:
#   --dry-run        stop after validation; nothing is uploaded
#   --checks         run typecheck, lint and tests before building
#   --build <n>      use this build number instead of asking App Store Connect
#   --no-wait        upload without waiting for processing
#
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.hirchyts.gymlib}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/ios/Rauta/Rauta.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
EXPORT_OPTIONS="$ROOT/ios/ExportOptions.plist"
EXPORT_DIR="$ROOT/build/ios/export"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"

# Rauta currently requires the iOS/watchOS 27 SDKs bundled with Xcode Beta.
# Keep the caller's explicit choice, otherwise prefer Xcode Beta when present.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode Beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode Beta.app/Contents/Developer"
fi

DRY_RUN=false
RUN_CHECKS=false
WAIT=true
FORCED_BUILD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --checks) RUN_CHECKS=true; shift ;;
    --no-wait) WAIT=false; shift ;;
    --build) FORCED_BUILD="${2:?--build needs a number}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

[[ -n "${ASC_KEY_ID:-}" ]] || fail "ASC_KEY_ID is not set"
[[ -n "${ASC_ISSUER:-}" ]] || fail "ASC_ISSUER is not set"
[[ -f "$ASC_KEY_PATH" ]] || fail "API key not found at $ASC_KEY_PATH"
export ASC_KEY_ID ASC_ISSUER ASC_KEY_PATH

cd "$ROOT"

if [[ "$RUN_CHECKS" == true ]]; then
  step "Checks"
  bun run typecheck
  bun run lint
  bun run test
fi

step "Build number"
if [[ -n "$FORCED_BUILD" ]]; then
  NEXT="$FORCED_BUILD"
  APP_ID="$(node scripts/asc-api.mjs app-id "$BUNDLE_ID")"
else
  APP_ID="$(node scripts/asc-api.mjs app-id "$BUNDLE_ID")"
  REMOTE_NEXT="$(node scripts/asc-api.mjs next-build "$APP_ID")"
  # A freshly uploaded build takes a few minutes to appear in the API, so the
  # remote answer can be stale. The number already in the project is the one
  # last built here, so never reuse it.
  LOCAL_NEXT=$(( $(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PBXPROJ" | grep -o '[0-9]*') + 1 ))
  NEXT=$(( REMOTE_NEXT > LOCAL_NEXT ? REMOTE_NEXT : LOCAL_NEXT ))
fi
# Applies to every target/config, so the widget extension stays in step.
perl -pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEXT;/g" "$PBXPROJ"
MARKETING="$(grep -m1 -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | cut -d' ' -f3)"
echo "app $APP_ID — version $MARKETING build $NEXT"

ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Rauta-b${NEXT}.xcarchive"
SIGNING=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER"
)

step "Archive"
rm -rf "$ARCHIVE"
xcodebuild -project "$PROJECT" -scheme Rauta -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  "${SIGNING[@]}" archive
[[ -d "$ARCHIVE" ]] || fail "archive was not produced"
WATCH_APP="$ARCHIVE/Products/Applications/Rauta.app/Watch/RautaWatch.app"
[[ -d "$WATCH_APP" ]] || fail "archive does not contain the Rauta watch app"

step "Export"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_DIR" \
  "${SIGNING[@]}"
IPA="$EXPORT_DIR/Rauta.ipa"
if [[ ! -f "$IPA" ]]; then
  IPA="$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
fi
[[ -f "$IPA" ]] || fail "no .ipa was exported"

step "Validate"
# Validation re-uploads the package to Apple, so run it once and keep the log.
VALIDATE_LOG="$(mktemp)"
if xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER" >"$VALIDATE_LOG" 2>&1; then
  grep -E 'VERIFY SUCCEEDED' "$VALIDATE_LOG" || true
  rm -f "$VALIDATE_LOG"
else
  grep -E 'ERROR' "$VALIDATE_LOG" | head -10 || true
  rm -f "$VALIDATE_LOG"
  fail "validation failed"
fi

if [[ "$DRY_RUN" == true ]]; then
  step "Dry run"
  echo "validated build $NEXT at $IPA (not uploaded)"
  exit 0
fi

step "Upload"
UPLOAD_LOG="$(mktemp)"
if xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER" >"$UPLOAD_LOG" 2>&1; then
  grep -E 'UPLOAD SUCCEEDED|Delivery UUID|Transferred' "$UPLOAD_LOG" || true
  rm -f "$UPLOAD_LOG"
else
  grep -E 'ERROR' "$UPLOAD_LOG" | head -10 || true
  rm -f "$UPLOAD_LOG"
  fail "upload failed"
fi

if [[ "$WAIT" != true ]]; then
  echo "uploaded build $NEXT; not waiting for processing"
  exit 0
fi

step "Processing"
for _ in $(seq 1 30); do
  read -r PROCESSING INTERNAL <<<"$(node scripts/asc-api.mjs build-state "$APP_ID" "$NEXT")"
  case "$PROCESSING" in
    VALID)
      echo "build $NEXT is VALID (internal: $INTERNAL)"
      exit 0 ;;
    INVALID|FAILED)
      fail "build $NEXT finished as $PROCESSING" ;;
    *)
      echo "waiting… ($PROCESSING)"
      sleep 30 ;;
  esac
done
fail "timed out waiting for build $NEXT to process"
