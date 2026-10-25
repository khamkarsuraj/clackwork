#!/usr/bin/env bash
#
# Measures key press to sound latency repeatably and saves the result (issue #46).
#
# Builds a Release app, runs its latency bench (simulated key presses, no typing or
# permissions needed), and saves the report to perf-results/latency-<commit>-<time>.json.
# The sound packs must be in clackwork/Sounds. Use wired or built-in output; Bluetooth
# adds its own latency.
#
# Usage:
#   scripts/latency_bench.sh [--keys N] [--interval MS] [--profile ID] [--compare FILE]
#
#   --keys N        simulated key presses (default 1000)
#   --interval MS   milliseconds between presses (default 30)
#   --profile ID    cobalt-clack, walnut-bump, onyx-thock or ember-tap (default walnut-bump)
#   --compare FILE  compare against an earlier report; exits 1 if total p95 is over
#                   20 ms or more than 1 ms worse

set -euo pipefail

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

keys=1000
interval=30
profile=walnut-bump
compare=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keys) keys="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --profile) profile="$2"; shift 2 ;;
    --compare) compare="$2"; shift 2 ;;
    *) usage ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="$root/build/latency"
app="$derived/Build/Products/Release/clackwork.app/Contents/MacOS/clackwork"

echo "Building Release…"
mkdir -p "$derived"
if ! xcodebuild build -quiet \
  -project "$root/clackwork.xcodeproj" -scheme clackwork -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$derived" > "$derived/build.log" 2>&1; then
  grep -E 'error:' "$derived/build.log" || tail -20 "$derived/build.log"
  echo "Build failed; full log in $derived/build.log"
  exit 1
fi

echo "Running $keys keys, ${interval} ms apart…"
line="$("$app" -latencyBench "$keys" -latencyBenchInterval "$interval" -latencyBenchProfile "$profile" \
  | sed -n 's/^latency-report: //p' | tail -1)"
[[ -n "$line" ]] || { echo "The bench printed no report."; exit 1; }

commit="$(git -C "$root" rev-parse --short HEAD)"
# Only tracked changes count: untracked files don't go into the build's sources.
if [[ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]]; then commit="$commit-dirty"; fi
mkdir -p "$root/perf-results"
out="$root/perf-results/latency-$commit-$(date +%Y%m%d-%H%M%S).json"

status=0
python3 -I "$root/scripts/latency_report.py" save "$out" --commit "$commit" <<< "$line" || status=$?
echo "Saved $out"

if [[ -n "$compare" ]]; then
  echo
  python3 -I "$root/scripts/latency_report.py" compare "$compare" "$out" || status=$?
fi
exit "$status"
