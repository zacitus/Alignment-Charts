#!/bin/sh
# Xcode Cloud post-clone hook: stamp CURRENT_PROJECT_VERSION with CI_BUILD_NUMBER.
#
# This keeps every Xcode Cloud archive's build number unique and traceable to
# its cloud build. IMPORTANT: this script alone does NOT make a build
# TestFlight-eligible. Xcode Cloud manages the distributed build number
# itself and its counter starts at 1. Since build 1.0 (24) already shipped to
# TestFlight, Zach MUST set "Next Build Number" to 25 in App Store Connect
# (app > Xcode Cloud > Settings > Build Number) BEFORE the first distributed
# build — otherwise App Store Connect rejects the upload because its build
# number is lower than the shipped 24.
#
# We rewrite the build setting in project.pbxproj BEFORE Xcode reads the
# project because the container app's Info.plist is generated
# (GENERATE_INFOPLIST_FILE = YES) — a build-phase script cannot override
# CURRENT_PROJECT_VERSION, but a file edit ahead of the build can.
#
# When CI_BUILD_NUMBER is unset (e.g. a local clone on Zach's Mac), this
# script does nothing and always exits 0 so the build can never fail here.

set -eu

PBXPROJ="${CI_PRIMARY_REPOSITORY_PATH:-}/Alignment Charts/Alignment Charts.xcodeproj/project.pbxproj"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_post_clone: CI_BUILD_NUMBER is unset — leaving project.pbxproj untouched."
  exit 0
fi

case "${CI_BUILD_NUMBER}" in
  ''|*[!0-9]*)
    echo "ci_post_clone: WARNING: CI_BUILD_NUMBER='${CI_BUILD_NUMBER}' is not numeric — leaving project.pbxproj untouched."
    exit 0
    ;;
esac

if [ ! -f "${PBXPROJ}" ]; then
  echo "ci_post_clone: WARNING: project.pbxproj not found at '${PBXPROJ}' — nothing to stamp."
  exit 0
fi

BEFORE=$(grep -c 'CURRENT_PROJECT_VERSION = [0-9][0-9]*;' "${PBXPROJ}" || true)
# -i.bak (then remove the backup) works on both BSD sed (macOS runners)
/usr/bin/sed -i.bak "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "${PBXPROJ}"
rm -f "${PBXPROJ}.bak"
AFTER=$(grep -c "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};" "${PBXPROJ}" || true)

echo "ci_post_clone: stamped CURRENT_PROJECT_VERSION=${CI_BUILD_NUMBER} in ${AFTER} of ${BEFORE} occurrence(s) in project.pbxproj."
exit 0
