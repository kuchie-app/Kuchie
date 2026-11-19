#!/bin/sh
# Keeps the Mac-side extension runtime running for Simulator builds.
#
# The embedded OpenJDK runtime only has an iPhone slice, so a Simulator build
# runs extensions through the same bridge on Mac loopback. Xcode calls this
# from ios/MihonRuntime/embed.sh for Debug Simulator builds, so `flutter run`,
# Xcode's Run button and the Home Screen icon all find a runtime without any
# environment variables. The app reads the port and token files written here
# (see AppDelegate.swift).
#
# It never fails the build: without JDK 21 it prints a warning and Simulator
# extensions stay unavailable.
set -u

root_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
port="${KUCHIE_QA_EXTENSION_RUNTIME_PORT:-14569}"
data_dir="${KUCHIE_QA_EXTENSION_RUNTIME_DATA:-$HOME/development/kuchie-qa-extension-runtime}"
runtime_source="$root_dir/ios/MihonRuntime"

warn() { echo "warning: Simulator extension runtime: $*"; }

find_java_home() {
  for candidate in "${JAVA_HOME:-}" \
      "$(/usr/libexec/java_home -v 21 2>/dev/null || true)" \
      /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
      /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
    if [ -n "$candidate" ] && [ -x "$candidate/bin/javac" ] &&
       "$candidate/bin/java" -version 2>&1 | grep -q 'version "21'; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

umask 077
mkdir -p "$data_dir" || { warn "cannot create $data_dir"; exit 0; }

token_file="$data_dir/runtime.token"
if [ ! -s "$token_file" ]; then
  openssl rand -hex 32 > "$token_file" || { warn 'cannot create a token'; exit 0; }
fi
printf '%s\n' "$port" > "$data_dir/runtime.port"

# Restart the host when its sources change, so it always matches this build.
stamp="$(cat "$runtime_source/ExtensionRuntime.java" "$runtime_source/DexJarCache.java" \
  "$runtime_source/BytecodeOverlay.java" "$runtime_source/fetch_server.sh" \
  "$root_dir/tool/qa/extension_runtime_host.sh" | shasum -a 256 | cut -d ' ' -f 1)"
stamp_file="$data_dir/host.stamp"
listening_pid="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n 1)"

if [ -n "$listening_pid" ]; then
  if [ "$(cat "$stamp_file" 2>/dev/null)" = "$stamp" ]; then
    exit 0
  fi
  # Only stop a runtime host started from this tool, never another program.
  if ps -o command= -p "$listening_pid" | grep -q 'ExtensionRuntime'; then
    echo "Restarting the Simulator extension runtime (sources changed)"
    kill "$listening_pid" 2>/dev/null
    tries=0
    while kill -0 "$listening_pid" 2>/dev/null && [ "$tries" -lt 20 ]; do
      sleep 0.25
      tries=$((tries + 1))
    done
  else
    warn "port $port is used by another program"
    exit 0
  fi
fi

java_home="$(find_java_home)" || {
  warn 'install JDK 21 (brew install openjdk@21) to run extensions in the Simulator'
  exit 0
}

echo "Starting the Simulator extension runtime on 127.0.0.1:$port"
# A new session keeps the host running after Xcode's build ends.
KUCHIE_QA_EXTENSION_RUNTIME_TOKEN="$(cat "$token_file")" \
KUCHIE_QA_EXTENSION_RUNTIME_PORT="$port" \
KUCHIE_QA_EXTENSION_RUNTIME_DATA="$data_dir" \
JAVA_HOME="$java_home" \
  /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \
  /bin/sh "$root_dir/tool/qa/extension_runtime_host.sh" \
  > "$data_dir/host.log" 2>&1 < /dev/null &

tries=0
until lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -gt 120 ]; then
    warn "the host did not start; see $data_dir/host.log"
    exit 0
  fi
  sleep 0.5
done
printf '%s\n' "$stamp" > "$stamp_file"
