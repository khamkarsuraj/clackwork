#!/usr/bin/env bash
#
# Imports a single-file sound pack (a folder with config.json and one audio file)
# into the app as clackwork/Sounds/<profile-id>.caf and <profile-id>.json.
#
# The audio is converted to lossless mono ALAC at its original sample rate. Slice
# timings in config.json are in milliseconds, so they stay valid.
#
# Usage:
#   scripts/import_soundpack.sh <pack-folder> <profile-id>
#
# Profile ids: mx-blue, mx-brown, mx-black, mx-red
#
# Keep each pack's license notice in clackwork/Sounds/ThirdPartyNotices.txt so it
# ships with the sounds.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

pack="$1"
profile="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/clackwork/Sounds"

case "$profile" in
  mx-blue|mx-brown|mx-black|mx-red) ;;
  *) echo "Unknown profile id: $profile"; exit 1 ;;
esac

config="$pack/config.json"
[[ -f "$config" ]] || { echo "No config.json in $pack"; exit 1; }

define_type="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("key_define_type",""))' "$config")"
if [[ "$define_type" != "single" ]]; then
  echo "Only single-file packs are supported (key_define_type \"single\"), this one is \"$define_type\"."
  exit 1
fi

sound_name="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["sound"])' "$config")"
audio="$pack/$sound_name"
[[ -f "$audio" ]] || { echo "Audio file not found: $audio"; exit 1; }

mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ALAC needs an integer source, so go through a 16-bit mono WAV first.
afconvert -f WAVE -d LEI16 -c 1 "$audio" "$tmp/mono.wav"
afconvert -f caff -d alac "$tmp/mono.wav" "$dest/$profile.caf"
cp "$config" "$dest/$profile.json"

echo "Imported $pack as $profile:"
afinfo "$dest/$profile.caf" | grep -E 'Data format|estimated duration' | sed 's/^/  /'
