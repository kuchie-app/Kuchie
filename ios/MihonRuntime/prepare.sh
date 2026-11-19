#!/bin/sh
set -eu

source_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
archives="${KUCHIE_EXTENSION_ARCHIVES:-$source_dir/.archives}"
release='https://github.com/1Selxo/Mangatan/releases/download/embedded-openjdk-ios13-v16'
java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ]; then
  java_home="$(/usr/libexec/java_home -v 21)"
fi

mkdir -p "$archives"
work="$(mktemp -d "$source_dir/.prepare.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fetch() {
  artifact="$1"
  expected="$2"
  url="${3:-$release/$artifact}"
  if [ ! -f "$archives/$artifact" ] ||
     [ "$(shasum -a 256 "$archives/$artifact" | cut -d ' ' -f 1)" != "$expected" ]; then
    curl --fail --location --retry 3 --output "$work/$artifact" "$url"
    if [ "$(shasum -a 256 "$work/$artifact" | cut -d ' ' -f 1)" != "$expected" ]; then
      echo "OpenJDK archive checksum mismatch ($artifact)" >&2
      exit 1
    fi
    mv "$work/$artifact" "$archives/$artifact"
  fi
}

fetch OpenJDK.xcframework.zip f21681caae40e508647e7f18c9082f27fa9aa67ee7f1376725eae528fa2d38cb
fetch java_bundle-device.zip 15369b9bb9dfdd400c18c56b30e2f6cf316b81d4e0bae5ddd6b1fe72355c4b0b
fetch OpenJDK-LICENSE.txt 4b9abebc4338048a7c2dc184e9f800deb349366bdf28eb23c2677a77b4c87726 \
  'https://raw.githubusercontent.com/openjdk/mobile/fc10224720ee1c109b1207daeba8878822bb5363/LICENSE'
fetch MExtensionServer-LICENSE.txt 3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04 \
  'https://raw.githubusercontent.com/1Selxo/M-Extension-Server/6a11ad771bc1c59303ce5d1e2b6f610211dcb819/LICENSE'
"$source_dir/fetch_server.sh" "$archives/MExtensionServer-ios.jar"
unzip -q "$archives/OpenJDK.xcframework.zip" -d "$work"
unzip -q "$archives/java_bundle-device.zip" -d "$work"

prepared="$work/prepared"
framework="$prepared/OpenJDKRuntime.framework"
runtime="$prepared/runtime"
mkdir -p "$framework/lib" "$runtime" "$work/bridge-classes" "$work/logging-classes"
/usr/bin/ditto "$work/java_bundle-device" "$framework/lib"
/usr/bin/ditto "$work/OpenJDK.xcframework/ios-arm64/Headers" "$prepared/Headers"
cp "$source_dir/OpenJDKRuntime-Info.plist" "$framework/Info.plist"

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -target arm64-apple-ios15.0 -isysroot "$sdk" -dynamiclib \
  -Wl,-force_load,"$work/OpenJDK.xcframework/ios-arm64/libdevice.a" \
  "$source_dir/OpenJDKExports.cpp" \
  -Wl,-install_name,@rpath/OpenJDKRuntime.framework/OpenJDKRuntime \
  -lz -framework Foundation -framework CoreFoundation -o "$framework/OpenJDKRuntime"

cp "$archives/MExtensionServer-ios.jar" "$runtime/MExtensionServer.jar"
"$java_home/bin/java" --class-path "$runtime/MExtensionServer.jar" \
  "$source_dir/BytecodeOverlay.java" "$runtime/MExtensionServer.jar" "$runtime/ExtCompat.jar"
"$java_home/bin/javac" --release 21 -proc:none -classpath "$runtime/MExtensionServer.jar" \
  -d "$work/bridge-classes" "$source_dir/ExtensionRuntime.java" "$source_dir/DexJarCache.java"
"$java_home/bin/jar" --create --file "$runtime/KuchieExtensionRuntime.jar" \
  -C "$work/bridge-classes" .
"$java_home/bin/javac" --release 21 --patch-module "java.logging=$source_dir/logging" \
  -d "$work/logging-classes" "$source_dir/logging/java/util/logging/"*.java
"$java_home/bin/jar" --create --file "$runtime/JavaLogging.jar" -C "$work/logging-classes" .
cp "$source_dir/THIRD_PARTY_NOTICES.md" "$runtime/"
cp "$archives/OpenJDK-LICENSE.txt" "$archives/MExtensionServer-LICENSE.txt" "$runtime/"

rm -rf "$source_dir/.prepared"
mv "$prepared" "$source_dir/.prepared"
# The bridge picks the runtime up with __has_include, which Xcode does not
# track: without this, an incremental build after the first one keeps the
# bridge compiled without OpenJDK while still embedding the framework.
touch "$source_dir/../Runner/MihonRuntimeBridge.mm"
echo 'Prepared arm64 iOS extension runtime for Kuchie.'
