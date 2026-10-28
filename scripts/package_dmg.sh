#!/usr/bin/env bash
#
# Packages a built clackwork.app into a signed, notarized DMG (issue #45).
#
# Makes Clackwork-<version>.dmg with an Applications shortcut and signs it with the
# Developer ID Application certificate. With notarization credentials it first notarizes
# the app and staples its ticket, then notarizes the DMG and staples that too, so Gatekeeper
# accepts both without a network round trip. The app must already be signed with Developer
# ID and the hardened runtime, as the release workflow's archive step does.
#
# Usage:
#   scripts/package_dmg.sh --app PATH/clackwork.app [--out DIR] [--identity NAME]
#       [--notary-profile NAME | --notary-key FILE --notary-key-id ID --notary-issuer ID]
#
#   --app PATH           the built, Developer ID signed app (required)
#   --out DIR            where the DMG goes (default dist)
#   --identity NAME      identity that signs the DMG (default "Developer ID Application")
#   --notary-profile     a notarytool keychain profile made with
#                        `xcrun notarytool store-credentials NAME`
#   --notary-key FILE    an App Store Connect API key (.p8), with --notary-key-id and
#                        --notary-issuer; what the release workflow uses
#
# Without notarization options the DMG is only signed, and the script says so. The last
# line printed is the DMG path.

set -euo pipefail

usage() { sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
fail() { echo "package_dmg: $*" >&2; exit 1; }

app=
out=dist
identity="Developer ID Application"
notary_profile=
notary_key=
notary_key_id=
notary_issuer=

while [[ $# -gt 0 ]]; do
  case $1 in
    --app) app=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --identity) identity=$2; shift 2 ;;
    --notary-profile) notary_profile=$2; shift 2 ;;
    --notary-key) notary_key=$2; shift 2 ;;
    --notary-key-id) notary_key_id=$2; shift 2 ;;
    --notary-issuer) notary_issuer=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -n $app ]] || usage
[[ -d $app && -f $app/Contents/Info.plist ]] || fail "$app is not an app bundle"

notary_args=()
if [[ -n $notary_profile ]]; then
  notary_args=(--keychain-profile "$notary_profile")
elif [[ -n $notary_key || -n $notary_key_id || -n $notary_issuer ]]; then
  [[ -n $notary_key && -n $notary_key_id && -n $notary_issuer ]] \
    || fail "--notary-key, --notary-key-id and --notary-issuer go together"
  [[ -f $notary_key ]] || fail "$notary_key does not exist"
  notary_args=(--key "$notary_key" --key-id "$notary_key_id" --issuer "$notary_issuer")
fi
notarize=$(( ${#notary_args[@]} > 0 ))

# Submits one file and fails loudly, with the notary log, unless Apple accepts it.
notarize_file() {
  local file=$1 result id status
  echo "Notarizing $(basename "$file") (this usually takes a few minutes)..."
  result=$(xcrun notarytool submit "$file" "${notary_args[@]}" --wait --output-format json) || true
  id=$(plutil -extract id raw -o - - <<< "$result" 2>/dev/null || true)
  status=$(plutil -extract status raw -o - - <<< "$result" 2>/dev/null || true)
  if [[ $status != Accepted ]]; then
    echo "$result" >&2
    [[ -n $id ]] && xcrun notarytool log "$id" "${notary_args[@]}" >&2
    fail "notarization of $(basename "$file") ended with status '${status:-unknown}'"
  fi
  echo "Accepted (submission $id)."
}

# The app's signature has to be right before anything is built on top of it.
codesign --verify --deep --strict --verbose=1 "$app" || fail "$app is not validly signed"
authority=$(codesign -dvv "$app" 2>&1 | grep -m1 '^Authority=' || true)
if [[ $authority != "Authority=Developer ID Application"* ]]; then
  (( notarize )) && fail "the app is signed with '${authority#Authority=}', not Developer ID; Apple will reject it"
  echo "Warning: the app is signed with '${authority#Authority=}', not Developer ID." >&2
fi
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.app-sandbox' \
  || echo "Warning: the app is not sandboxed." >&2

version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
build=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")
dmg_name="Clackwork-$version.dmg"
echo "Packaging $(basename "$app") $version ($build) as $dmg_name"

work=$(mktemp -d -t clackwork-dmg)
trap 'rm -rf "$work"' EXIT
stage=$work/stage
mkdir -p "$stage" "$out"
ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"
staged_app=$stage/$(basename "$app")

if (( notarize )); then
  # Notarize the app on its own first, so the copy Sparkle or the user drags out of the
  # DMG carries its own stapled ticket.
  ditto -c -k --keepParent "$staged_app" "$work/app.zip"
  notarize_file "$work/app.zip"
  xcrun stapler staple "$staged_app"
fi

dmg=$out/$dmg_name
rm -f "$dmg"
hdiutil create -volname "Clackwork $version" -srcfolder "$stage" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$dmg" > /dev/null
codesign --force --sign "$identity" --timestamp "$dmg"

if (( notarize )); then
  notarize_file "$dmg"
  xcrun stapler staple "$dmg"
  # Gatekeeper's own verdict on the disk image, as a user opening it would get.
  spctl --assess --type open --context context:primary-signature -v "$dmg"
else
  echo "Not notarized: pass --notary-profile or --notary-key to notarize and staple." >&2
fi

codesign --verify --verbose=1 "$dmg"
du -h "$dmg" | cut -f1 | sed 's/^/Size: /'
echo "$dmg"
