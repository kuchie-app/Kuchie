#!/bin/sh
set -eu

destination="$1"
# Built with -PiosRuntime=true and JDK 21 from 1Selxo/M-Extension-Server@6a11ad7
# (v1.0.8.1), which repairs allocations of R8-optimised classes.
server_url='https://github.com/kuchie-app/Kuchie/releases/download/ios-runtime-v17/MExtensionServer-ios.jar'
expected='8b9eb29430af3c16e4f88659069dc96a4abd8aa03297aafd1710bec7009d4af5'

verify() {
  [ -f "$1" ] && [ "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" = "$expected" ]
}

if ! verify "$destination"; then
  temporary="$(mktemp "$(dirname -- "$destination")/.server-jar.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT
  curl --fail --location --retry 3 --output "$temporary" "$server_url"
  if ! verify "$temporary"; then
    echo 'M-Extension-Server archive checksum mismatch' >&2
    exit 1
  fi
  mv "$temporary" "$destination"
fi
