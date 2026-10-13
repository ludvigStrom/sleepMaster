#!/usr/bin/env bash
set -euo pipefail

# Build, sign, package, notarize, and staple SleepMaster.
#
# Usage:
#   bash Scripts/release_pkg_notarize.sh 1.0.0
#
# Copy Scripts/release.env.example → Scripts/release.env and set TEAM_ID
# and NOTARY_PROFILE. That file is gitignored.
#
# Signed installer only (skip notarytool / stapler):
#   SKIP_NOTARIZATION=1 bash Scripts/release_pkg_notarize.sh 1.0.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/release.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/release.env"
  set +a
fi

VERSION="${1:-1.0.0}"
APP_NAME="${APP_NAME:-SleepMaster}"
BUNDLE_ID="${BUNDLE_ID:-com.ludvigstrom.sleepmaster}"
PKG_ID="${PKG_ID:-${BUNDLE_ID}.pkg}"
PKG_FILE_BASENAME="${PKG_FILE_BASENAME:-SleepMaster}"

TEAM_ID="${TEAM_ID:-}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Developer ID Application}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-Developer ID Installer}"
APP_SIGN_IDENTITY_HASH="${APP_SIGN_IDENTITY_HASH:-}"
INSTALLER_SIGN_IDENTITY_HASH="${INSTALLER_SIGN_IDENTITY_HASH:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CONFIGURATION="${CONFIGURATION:-Release}"

STAPLE_RETRIES="${STAPLE_RETRIES:-24}"
STAPLE_RETRY_DELAY_SEC="${STAPLE_RETRY_DELAY_SEC:-}"
STAPLE_RETRY_RAMP_MIN_SEC="${STAPLE_RETRY_RAMP_MIN_SEC:-60}"
STAPLE_RETRY_RAMP_MAX_SEC="${STAPLE_RETRY_RAMP_MAX_SEC:-300}"
POST_NOTARIZE_SLEEP_SEC="${POST_NOTARIZE_SLEEP_SEC:-60}"
STAPLE_TMP_COPY="${STAPLE_TMP_COPY:-1}"
STAPLE_TMP_DIR="${STAPLE_TMP_DIR:-${TMPDIR:-/tmp}}"
STAPLE_ABORT_ON_C="${STAPLE_ABORT_ON_C:-1}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
STAPLE_VERBOSE="${STAPLE_VERBOSE:-0}"
STAPLE_VERBOSE_AFTER_FAIL="${STAPLE_VERBOSE_AFTER_FAIL:-1}"

MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
ARCHS="${ARCHS:-arm64 x86_64}"

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
  if [[ -z "${TEAM_ID}" || -z "${NOTARY_PROFILE}" ]]; then
    echo "ERROR: TEAM_ID and NOTARY_PROFILE are required to notarize." >&2
    echo "Copy Scripts/release.env.example to Scripts/release.env and fill them in." >&2
    exit 1
  fi
fi

DERIVED_DATA_DIR="${PROJECT_DIR}/Build/DerivedData"
DIST_DIR="${PROJECT_DIR}/Build/dist"
PAYLOAD_ROOT="${DIST_DIR}/payload"
SCRIPTS_DIR="${PROJECT_DIR}/Scripts/pkg_scripts"
ENTITLEMENTS_SRC="${PROJECT_DIR}/SleepMaster/SleepMaster.entitlements"
ENTITLEMENTS_TMP="${DIST_DIR}/SleepMaster.release.entitlements"
FINAL_PKG_PATH="${DIST_DIR}/${PKG_FILE_BASENAME}-${VERSION}.pkg"
APP_SRC=""

pkg_sha256 () {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

resolve_codesign_identity_hash () {
  local wanted="$1"
  local usage="$2"
  local policy="${3:-codesigning}"
  local matches=()

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    matches+=("${line}")
  done < <(security find-identity -v -p "${policy}" \
    | awk -v wanted="${wanted}" '
        /^[[:space:]]*[0-9]+\)/ {
          hash=$2;
          line=$0;
          q1=index(line, "\"");
          q2=0;
          if (q1 > 0) {
            rest=substr(line, q1 + 1);
            q2=index(rest, "\"");
          }
          if (q1 > 0 && q2 > 0) {
            name=substr(line, q1 + 1, q2 - 1);
            if (index(name, wanted) > 0)
              print hash;
          }
        }')

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "ERROR: Could not resolve ${usage} identity matching: ${wanted}" >&2
    echo "Available identities for policy '${policy}':" >&2
    security find-identity -v -p "${policy}" >&2 || true
    exit 1
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "WARN: Multiple ${usage} identities matched '${wanted}'. Using first hash: ${matches[0]}" >&2
  fi

  echo "${matches[0]}"
}

format_clock_time_from_now_secs () {
  local add_secs="$1"
  date -v+${add_secs}S "+%H:%M"
}

staple_wait_secs_after_failed_attempt () {
  local failed_attempt="$1"
  if [[ -n "${STAPLE_RETRY_DELAY_SEC}" ]]; then
    echo "${STAPLE_RETRY_DELAY_SEC}"
    return
  fi
  local min_s="${STAPLE_RETRY_RAMP_MIN_SEC}"
  local max_s="${STAPLE_RETRY_RAMP_MAX_SEC}"
  local exp=$(( failed_attempt - 1 ))
  local mult=1
  local i
  for (( i = 0; i < exp; i++ )); do
    mult=$(( mult * 2 ))
  done
  local d=$(( min_s * mult ))
  if (( d > max_s )); then
    d="${max_s}"
  fi
  echo "${d}"
}

sleep_with_optional_abort () {
  local total_secs="$1"
  local remaining="${total_secs}"

  if [[ ! -t 0 ]] || [[ "${STAPLE_ABORT_ON_C}" != "1" ]]; then
    sleep "${remaining}"
    return 0
  fi

  while (( remaining > 0 )); do
    if read -r -t 1 -n 1 key 2>/dev/null; then
      if [[ "${key}" == "c" || "${key}" == "C" ]]; then
        return 1
      fi
    fi
    remaining=$(( remaining - 1 ))
  done
  return 0
}

write_staple_status_file () {
  local status_line="$1"
  local path="${DIST_DIR}/last_release_staple_status.txt"
  {
    echo "$(date "+%Y-%m-%d %H:%M:%S %z")  ${status_line}"
    echo "  installer: ${FINAL_PKG_PATH}"
    if [[ -n "${SUBMISSION_ID:-}" ]]; then
      echo "  notary submission id: ${SUBMISSION_ID}"
    fi
  } >> "${path}"
}

run_manual_staple_sequence () {
  local pkg_path="$1"
  shift
  local -a staple_extra=()
  if [[ $# -gt 0 ]]; then
    staple_extra=("$@")
  fi

  if [[ ${#staple_extra[@]} -gt 0 ]]; then
    echo "    — stapler staple ${staple_extra[*]} \"${pkg_path}\""
    xcrun stapler staple "${staple_extra[@]}" "${pkg_path}"
  else
    echo "    — stapler staple \"${pkg_path}\""
    xcrun stapler staple "${pkg_path}"
  fi
  local staple_ec=$?
  if [[ "${staple_ec}" -ne 0 ]]; then
    return "${staple_ec}"
  fi
  echo "    — stapler validate \"${pkg_path}\""
  xcrun stapler validate "${pkg_path}"
}

staple_pkg_with_optional_tmp_copy () {
  local dest_pkg="$1"
  shift
  local -a staple_extra=()
  if [[ $# -gt 0 ]]; then
    staple_extra=("$@")
  fi

  if [[ "${STAPLE_TMP_COPY}" != "1" ]]; then
    run_manual_staple_sequence "${dest_pkg}" ${staple_extra[@]+"${staple_extra[@]}"}
    return
  fi

  local tmp_pkg
  tmp_pkg="$(mktemp "${STAPLE_TMP_DIR}/sleepmaster-staple.XXXXXX.pkg")" || return 1
  echo "    (stapling via temp file: ${tmp_pkg})"
  if ! ditto "${dest_pkg}" "${tmp_pkg}"; then
    rm -f "${tmp_pkg}"
    return 1
  fi
  if run_manual_staple_sequence "${tmp_pkg}" ${staple_extra[@]+"${staple_extra[@]}"}; then
    if ditto "${tmp_pkg}" "${dest_pkg}"; then
      rm -f "${tmp_pkg}"
      return 0
    fi
    rm -f "${tmp_pkg}"
    return 1
  fi
  rm -f "${tmp_pkg}"
  return 1
}

write_release_entitlements () {
  cat > "${ENTITLEMENTS_TMP}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.get-task-allow</key>
	<false/>
</dict>
</plist>
EOF
}

echo "==> Cleaning previous distribution artifacts"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p "${PAYLOAD_ROOT}/Applications"

if [[ -z "${APP_SIGN_IDENTITY_HASH}" ]]; then
  APP_SIGN_IDENTITY_HASH="$(resolve_codesign_identity_hash "${APP_SIGN_IDENTITY}" "application signing" "codesigning")"
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY_HASH}" ]]; then
  INSTALLER_SIGN_IDENTITY_HASH="$(resolve_codesign_identity_hash "${INSTALLER_SIGN_IDENTITY}" "installer signing" "basic")"
fi

echo "==> Using application signing identity hash: ${APP_SIGN_IDENTITY_HASH}"
echo "==> Using installer signing identity hash: ${INSTALLER_SIGN_IDENTITY_HASH}"

if [[ "${DIST_DIR}" == *"Mobile Documents"* || "${DIST_DIR}" == *"iCloud"* ]]; then
  echo "WARN: Build/dist appears to be under iCloud Drive. Stapler/notary can fail (error 65)." >&2
fi

echo "==> Building ${APP_NAME} ${VERSION} (${ARCHS})"
rm -rf "${DERIVED_DATA_DIR}"
xcodebuild \
  -project "${PROJECT_DIR}/SleepMaster.xcodeproj" \
  -scheme SleepMaster \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  ARCHS="${ARCHS}" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

APP_SRC="$(find "${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}" -maxdepth 1 -name "${APP_NAME}.app" -print -quit)"
if [[ -z "${APP_SRC}" || ! -d "${APP_SRC}" ]]; then
  echo "ERROR: Built app not found under ${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}" >&2
  exit 1
fi

echo "==> Built app: ${APP_SRC}"
lipo -info "${APP_SRC}/Contents/MacOS/${APP_NAME}" || true

echo "==> Preparing release entitlements"
write_release_entitlements

echo "==> Re-signing with Developer ID + hardened runtime"
xattr -cr "${APP_SRC}"
codesign --force --sign "${APP_SIGN_IDENTITY_HASH}" --timestamp --options runtime \
  --entitlements "${ENTITLEMENTS_TMP}" "${APP_SRC}"
codesign --verify --deep --strict --verbose=2 "${APP_SRC}"

echo "==> Staging installer payload"
ditto "${APP_SRC}" "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app"
xattr -cr "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app"

chmod +x "${SCRIPTS_DIR}/postinstall"

echo "==> Building signed installer pkg"
pkgbuild \
  --root "${PAYLOAD_ROOT}" \
  --install-location / \
  --scripts "${SCRIPTS_DIR}" \
  --identifier "${PKG_ID}" \
  --version "${VERSION}" \
  --sign "${INSTALLER_SIGN_IDENTITY_HASH}" \
  "${FINAL_PKG_PATH}"

echo "==> Installer: ${FINAL_PKG_PATH}"
echo "    SHA256: $(pkg_sha256 "${FINAL_PKG_PATH}")"

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
  echo "==> SKIP_NOTARIZATION=1 — leaving signed .pkg without notary/staple"
  exit 0
fi

echo "==> Submitting to notarytool (profile ${NOTARY_PROFILE})"
xcrun notarytool submit "${FINAL_PKG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --team-id "${TEAM_ID}" \
  --wait \
  --output-format json > "${DIST_DIR}/last_notary_submit.json"

SUBMISSION_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "${DIST_DIR}/last_notary_submit.json")"
NOTARY_STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "${DIST_DIR}/last_notary_submit.json")"
echo "==> Notary status: ${NOTARY_STATUS}  id: ${SUBMISSION_ID}"

if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
  echo "ERROR: Notarization did not succeed. See ${DIST_DIR}/last_notary_submit.json" >&2
  if [[ -n "${SUBMISSION_ID}" ]]; then
    xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${NOTARY_PROFILE}" || true
  fi
  exit 1
fi

if (( POST_NOTARIZE_SLEEP_SEC > 0 )); then
  echo "==> Waiting ${POST_NOTARIZE_SLEEP_SEC}s for Apple ticket propagation (press C to abort)"
  if ! sleep_with_optional_abort "${POST_NOTARIZE_SLEEP_SEC}"; then
    echo "Aborted during post-notary wait." >&2
    exit 1
  fi
fi

echo "==> Stapling"
staple_ok=0
for (( attempt = 1; attempt <= STAPLE_RETRIES; attempt++ )); do
  extra=()
  if [[ "${STAPLE_VERBOSE}" == "1" ]] || { [[ "${STAPLE_VERBOSE_AFTER_FAIL}" == "1" ]] && (( attempt > 1 )); }; then
    extra+=(-v)
  fi
  echo "  attempt ${attempt}/${STAPLE_RETRIES}"
  if staple_pkg_with_optional_tmp_copy "${FINAL_PKG_PATH}" ${extra[@]+"${extra[@]}"}; then
    staple_ok=1
    write_staple_status_file "stapled ok on attempt ${attempt}"
    break
  fi
  if (( attempt == STAPLE_RETRIES )); then
    break
  fi
  wait_secs="$(staple_wait_secs_after_failed_attempt "${attempt}")"
  echo "  staple failed; retrying at $(format_clock_time_from_now_secs "${wait_secs}") (wait ${wait_secs}s, press C to abort)"
  if ! sleep_with_optional_abort "${wait_secs}"; then
    echo "Aborted during staple retry wait." >&2
    exit 1
  fi
done

if [[ "${staple_ok}" != "1" ]]; then
  write_staple_status_file "staple FAILED after ${STAPLE_RETRIES} attempts"
  echo "ERROR: stapler could not staple/validate ${FINAL_PKG_PATH}" >&2
  exit 1
fi

echo "==> Done: ${FINAL_PKG_PATH}"
