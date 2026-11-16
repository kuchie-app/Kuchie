#!/bin/sh
# Runs Kuchie on an iOS Simulator with the Local extension runtime attached.
#
# The embedded OpenJDK runtime only has an iPhone slice, so on the Simulator
# every Keiyoushi APK extension fails and only the built-in Shinigami adapter
# installs. This starts (or reuses) the same bridge on Mac loopback and passes
# its port and token to the Debug app.
#
# Usage: tool/qa/run_simulator_local.sh [simulator-udid] [extra flutter args]
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
device="${1:-booted}"
[ $# -gt 0 ] && shift
port="${KUCHIE_QA_EXTENSION_RUNTIME_PORT:-14569}"
data_dir="${KUCHIE_QA_EXTENSION_RUNTIME_DATA:-$HOME/development/kuchie-qa-extension-runtime}"
umask 077
mkdir -p "$data_dir"

if [ "$device" = booted ]; then
  device="$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -n 1)"
  [ -n "$device" ] || { echo 'Boot a simulator first.' >&2; exit 1; }
fi

# One token per data directory, so a running host stays usable across launches.
token_file="$data_dir/runtime.token"
if [ ! -s "$token_file" ]; then
  openssl rand -hex 32 > "$token_file"
fi
token="$(cat "$token_file")"

if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Starting the extension runtime host on 127.0.0.1:$port"
  KUCHIE_QA_EXTENSION_RUNTIME_TOKEN="$token" \
  KUCHIE_QA_EXTENSION_RUNTIME_PORT="$port" \
  KUCHIE_QA_EXTENSION_RUNTIME_DATA="$data_dir" \
    nohup "$root_dir/tool/qa/extension_runtime_host.sh" >"$data_dir/host.log" 2>&1 &
  tries=0
  until lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 120 ]; then
      echo "The runtime host did not start; see $data_dir/host.log" >&2
      exit 1
    fi
    sleep 1
  done
else
  echo "Reusing the extension runtime host on 127.0.0.1:$port"
fi

cd "$root_dir"
SIMCTL_CHILD_KUCHIE_QA_EXTENSION_RUNTIME_PORT="$port" \
SIMCTL_CHILD_KUCHIE_QA_EXTENSION_RUNTIME_TOKEN="$token" \
  exec flutter run -d "$device" "$@"
