#!/usr/bin/env bash
# Developer ID signing + Apple notarization for Document Studio.app and its
# DMG — what makes Gatekeeper stop saying "Apple could not verify … is free
# of malware". Sourced by scripts/macos/package_release.sh.
#
# Signing (needs an Apple Developer Program membership):
#   DS_MACOS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   (the certificate must be in the keychain; CI imports it, see release.yml)
# Without it the app is only ad-hoc signed (runs, but Gatekeeper warns).
#
# Notarization — ONE of:
#   DS_NOTARY_PROFILE=<keychain profile made with `xcrun notarytool store-credentials`>
#   DS_APPLE_ID + DS_APPLE_TEAM_ID + DS_APPLE_APP_PASSWORD (app-specific password)
#   DS_NOTARY_KEY_PATH + DS_NOTARY_KEY_ID + DS_NOTARY_ISSUER (App Store Connect API key)

DS_MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_ENGINE_ENTITLEMENTS="$DS_MACOS_DIR/engines.entitlements"
DS_APP_ENTITLEMENTS="$DS_MACOS_DIR/../../macos/Runner/Release.entitlements"

ds_has_identity() { [[ -n "${DS_MACOS_SIGN_IDENTITY:-}" ]]; }

ds_has_notary() {
  [[ -n "${DS_NOTARY_PROFILE:-}" ]] ||
    [[ -n "${DS_APPLE_ID:-}" && -n "${DS_APPLE_TEAM_ID:-}" && -n "${DS_APPLE_APP_PASSWORD:-}" ]] ||
    [[ -n "${DS_NOTARY_KEY_PATH:-}" && -n "${DS_NOTARY_KEY_ID:-}" && -n "${DS_NOTARY_ISSUER:-}" ]]
}

_ds_codesign() {
  local entitlements="$1" target="$2"
  codesign --force --timestamp --options runtime \
    --entitlements "$entitlements" \
    --sign "$DS_MACOS_SIGN_IDENTITY" "$target"
}

# Signs every nested binary first (inside-out), then the app.
ds_sign_app() {
  local app="$1"
  if ! ds_has_identity; then
    echo "==> ad-hoc codesign (set DS_MACOS_SIGN_IDENTITY for a Developer ID signature)"
    codesign --force --deep --sign - "$app" || echo "WARNING: ad-hoc codesign failed; continuing." >&2
    return 0
  fi
  echo "==> Developer ID signing: $DS_MACOS_SIGN_IDENTITY"
  local f main
  main="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
  # 1. Loose Mach-O files (dylibs, .so, engine executables). The main
  #    executable is signed with the app at the end.
  while IFS= read -r -d '' f; do
    [[ "$f" == "$main" ]] && continue
    if file -b "$f" | grep -q 'Mach-O'; then
      _ds_codesign "$DS_ENGINE_ENTITLEMENTS" "$f"
    fi
  done < <(find "$app/Contents" -type f -print0)
  # 2. Bundles (frameworks, plug-ins, nested apps such as LibreOffice);
  #    -depth lists inner bundles before the ones containing them.
  while IFS= read -r -d '' f; do
    _ds_codesign "$DS_ENGINE_ENTITLEMENTS" "$f"
  done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.bundle' -o -name '*.plugin' -o -name '*.xpc' \) -print0)
  # 3. The app itself.
  _ds_codesign "$DS_APP_ENTITLEMENTS" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
}

ds_sign_file() {
  ds_has_identity || return 0
  codesign --force --timestamp --sign "$DS_MACOS_SIGN_IDENTITY" "$1"
}

# Submits [file] (zip or dmg) to Apple, waits, and staples [staple_target].
ds_notarize() {
  local file="$1" staple_target="$2"
  if ! ds_has_identity || ! ds_has_notary; then
    echo "==> Notarization skipped (needs DS_MACOS_SIGN_IDENTITY and notary credentials)"
    return 0
  fi
  echo "==> Notarizing $(basename "$file") (this takes a few minutes)"
  local auth=()
  if [[ -n "${DS_NOTARY_PROFILE:-}" ]]; then
    auth=(--keychain-profile "$DS_NOTARY_PROFILE")
  elif [[ -n "${DS_NOTARY_KEY_PATH:-}" ]]; then
    auth=(--key "$DS_NOTARY_KEY_PATH" --key-id "$DS_NOTARY_KEY_ID" --issuer "$DS_NOTARY_ISSUER")
  else
    auth=(--apple-id "$DS_APPLE_ID" --team-id "$DS_APPLE_TEAM_ID" --password "$DS_APPLE_APP_PASSWORD")
  fi
  local out id status
  out="$(xcrun notarytool submit "$file" "${auth[@]}" --wait --output-format json)"
  echo "$out"
  id="$(echo "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
  status="$(echo "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed ($status). Apple's log:" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${auth[@]}" >&2 || true
    return 1
  fi
  xcrun stapler staple "$staple_target"
  xcrun stapler validate "$staple_target"
}
