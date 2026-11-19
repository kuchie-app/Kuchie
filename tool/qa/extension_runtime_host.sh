#!/bin/sh
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ]; then
  java_home="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
fi
if [ -z "$java_home" ]; then
  for candidate in /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
      /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
    [ -x "$candidate/bin/java" ] && java_home="$candidate" && break
  done
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

bridge_classes="$data_dir/bridge-classes"
rm -rf "$bridge_classes"
"$java_home/bin/javac" --release 21 -proc:none -classpath "$server_jar" -d "$bridge_classes" \
  "$runtime_source/ExtensionRuntime.java" "$runtime_source/DexJarCache.java"

# Default verification, as on iPhone: every class outside the JDK.
exec "$java_home/bin/java" -Xmx512m -Djava.awt.headless=true \
  "-Duser.home=$data_dir/home" "-Djava.io.tmpdir=$data_dir/tmp" \
  "-Dsuwayomi.tachidesk.config.server.rootDir=$data_dir" \
  --class-path "$bridge_classes:$overlay:$server_jar" io.kuchie.runtime.ExtensionRuntime "$port" "$data_dir"
