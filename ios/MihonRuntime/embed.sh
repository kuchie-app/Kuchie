#!/bin/sh
set -eu

# The OpenJDK runtime has no Simulator slice. Debug Simulator builds use the
# same bridge on Mac loopback instead, started (or refreshed) here.
if [ "${PLATFORM_NAME:-}" = iphonesimulator ]; then
  case "${CONFIGURATION:-}" in
    Debug*) /bin/sh "${SRCROOT}/../tool/qa/ensure_simulator_runtime.sh" || true ;;
  esac
  exit 0
fi
[ "${PLATFORM_NAME:-}" = iphoneos ] || exit 0
prepared="${SRCROOT}/MihonRuntime/.prepared"
resource_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/KuchieMihonRuntime"
framework_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/OpenJDKRuntime.framework"

if [ ! -f "$prepared/runtime/KuchieExtensionRuntime.jar" ] ||
   [ ! -f "$prepared/OpenJDKRuntime.framework/OpenJDKRuntime" ]; then
  rm -rf "$resource_dir" "$framework_dir"
  echo 'note: On-device extensions are disabled. Run ios/MihonRuntime/prepare.sh to include the runtime.'
  exit 0
fi

rm -rf "$resource_dir" "$framework_dir"
mkdir -p "$(dirname -- "$resource_dir")" "$(dirname -- "$framework_dir")"
/usr/bin/ditto "$prepared/runtime" "$resource_dir"
/usr/bin/ditto "$prepared/OpenJDKRuntime.framework" "$framework_dir"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$framework_dir"
fi
