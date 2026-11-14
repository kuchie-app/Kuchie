#!/bin/sh
set -eu

destination="$1"
server_url='https://github.com/1Selxo/M-Extension-Server/releases/download/ios-runtime-v16/MExtensionServer-ios.jar'
expected='5c06eaabc1230ccff914421c3692509094247596872bb0f76fecd0d5f5cfee29'

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
