#!/bin/sh
set -eu

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
