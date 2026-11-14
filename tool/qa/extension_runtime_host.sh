#!/bin/sh
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ]; then
  java_home="$(/usr/libexec/java_home -v 21)"
fi

: "${KUCHIE_QA_EXTENSION_RUNTIME_TOKEN:?Set a random token and pass it to the simulator app}"
port="${KUCHIE_QA_EXTENSION_RUNTIME_PORT:-14569}"
data_dir="${KUCHIE_QA_EXTENSION_RUNTIME_DATA:-${TMPDIR:-/tmp}/kuchie-qa-extension-runtime}"
umask 077
mkdir -p "$data_dir/home" "$data_dir/tmp"
server_jar="$data_dir/MExtensionServer-ios.jar"
"$root_dir/ios/MihonRuntime/fetch_server.sh" "$server_jar"
runtime_source="$root_dir/ios/MihonRuntime"
overlay="$data_dir/ExtCompat.jar"
"$java_home/bin/java" --class-path "$server_jar" \
  "$runtime_source/BytecodeOverlay.java" "$server_jar" "$overlay"

exec "$java_home/bin/java" -Xmx512m -Xverify:all -Djava.awt.headless=true \
  "-Duser.home=$data_dir/home" "-Djava.io.tmpdir=$data_dir/tmp" \
  "-Dsuwayomi.tachidesk.config.server.rootDir=$data_dir" \
  --class-path "$overlay:$server_jar" "$runtime_source/ExtensionRuntime.java" "$port" "$data_dir"
