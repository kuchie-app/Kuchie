#!/bin/sh
set -eu

destination="$1"
# Built with -PiosRuntime=true and JDK 21 from 1Selxo/M-Extension-Server@6a11ad7
# (v1.0.8.1, which repairs allocations of R8-optimised classes) plus
# patches/0001-keep-extension-user-agent.patch. See README.md.
server_url='https://github.com/kuchie-app/Kuchie/releases/download/ios-runtime-v17/MExtensionServer-ios.jar'
expected='859e92899db83be544b23f745214292ad2adf4c039142be16c4c66a94457e742'

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
