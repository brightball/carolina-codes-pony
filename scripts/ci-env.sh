#!/bin/sh
# Prepare/restore the Gitea CI workspace without Node or an OCI push.
#
# The ponyc:0.71.0 Alpine job image has no Node, so actions/upload-artifact
# cannot run inside it. Gitea job tokens also cannot publish container
# packages. This helper talks to Gitea's artifact API with curl instead.
#
# Prepare and the five check jobs share this image family so restored
# musl binaries (semgrep, osv-scanner, gitleaks, python) actually run.
set -euo pipefail

ARTIFACT_NAME="${CI_ENV_ARTIFACT_NAME:-prepared-env}"
TAR_PATH="${CI_ENV_TAR:-/tmp/prepared-env.tar.gz}"
TOOLS_DIR="${CI_ENV_TOOLS_DIR:-/opt/ci-tools}"
OVERLAY_DIR="${CI_ENV_OVERLAY_DIR:-/opt/ci-overlay}"
GITLEAKS_VERSION="${CI_ENV_GITLEAKS_VERSION:-8.30.1}"
OSV_VERSION="${CI_ENV_OSV_VERSION:-2.6.0}"
APK_PACKAGES="${CI_ENV_APK_PACKAGES:-openssl-dev libpq-dev python3 py3-pip openssl ca-certificates}"

json_string() {
  key="$1"
  file="$2"
  tr -d '\n' <"$file" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

artifact_token() {
  t="${ACTIONS_RUNTIME_TOKEN:-${GITHUB_TOKEN:-${GITEA_TOKEN:-}}}"
  if [ -z "$t" ]; then
    echo "missing artifact token (ACTIONS_RUNTIME_TOKEN/GITHUB_TOKEN)" >&2
    exit 1
  fi
  printf '%s' "$t"
}

artifact_base() {
  if [ -n "${ACTIONS_RUNTIME_URL:-}" ]; then
    printf '%s' "${ACTIONS_RUNTIME_URL%/}"
    return
  fi
  if [ -z "${GITHUB_SERVER_URL:-}" ]; then
    echo "missing ACTIONS_RUNTIME_URL or GITHUB_SERVER_URL" >&2
    exit 1
  fi
  printf '%s' "${GITHUB_SERVER_URL%/}/api/actions_pipeline"
}

rewrite_runtime_url() {
  url="$1"
  case "$url" in
    *_apis/*)
      suffix="${url#*_apis/}"
      printf '%s/_apis/%s' "$(artifact_base)" "$suffix"
      ;;
    /*)
      printf '%s%s' "$(artifact_base)" "${url#/api/actions_pipeline}"
      ;;
    *)
      printf '%s' "$url"
      ;;
  esac
}

md5_b64() {
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -md5 -binary "$1" | openssl base64 -A
    return
  fi
  md5sum "$1" | awk '{print $1}' | xxd -r -p | base64 | tr -d '\n'
}

workspace_dir() {
  printf '%s' "${GITHUB_WORKSPACE:-$(pwd)}"
}

list_installed_pkgver() {
  apk list --installed 2>/dev/null | awk '{print $1}' | sort
}

pkgname_of() {
  printf '%s\n' "$1" | sed 's/-r[0-9][0-9]*$//; s/-[^-]*$//'
}

copy_overlay_path() {
  src="$1"
  rel="${src#/}"
  dest="$OVERLAY_DIR/$rel"
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  if [ -L "$src" ]; then
    real="$(readlink -f "$src" || true)"
    if [ -n "$real" ] && [ -e "$real" ] && [ "$real" != "$src" ]; then
      real_rel="${real#/}"
      mkdir -p "$(dirname "$OVERLAY_DIR/$real_rel")"
      cp -a "$real" "$OVERLAY_DIR/$real_rel"
    fi
  fi
}

copy_apk_package() {
  pkg="$1"
  apk info -L "$pkg" 2>/dev/null | while IFS= read -r rel; do
    case "$rel" in
      *contains:*) continue ;;
      "") continue ;;
    esac
    copy_overlay_path "/$rel"
  done
}

write_apk_overlay() {
  before_file="$1"
  if [ ! -f "$before_file" ]; then
    echo "missing installed-package snapshot for overlay" >&2
    exit 1
  fi
  mkdir -p "$OVERLAY_DIR"
  after="$(mktemp)"
  new="$(mktemp)"
  list_installed_pkgver > "$after"
  comm -13 "$before_file" "$after" > "$new"
  if [ ! -s "$new" ]; then
    echo "apk overlay: no new or upgraded packages to snapshot" >&2
    rm -f "$after" "$new"
    exit 1
  fi
  while IFS= read -r pkgver; do
    [ -n "$pkgver" ] || continue
    copy_apk_package "$(pkgname_of "$pkgver")"
  done < "$new"
  rm -f "$after" "$new"
  for req in usr/bin/python3 usr/include/openssl/ssl.h usr/include/postgresql/libpq-fe.h; do
    if [ ! -e "$OVERLAY_DIR/$req" ] && [ ! -L "$OVERLAY_DIR/$req" ]; then
      echo "apk overlay missing $req" >&2
      exit 1
    fi
  done
}

install_tools() {
  mkdir -p "$TOOLS_DIR/bin"
  echo "installing gitleaks ${GITLEAKS_VERSION}"
  curl -sSfL \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C "$TOOLS_DIR/bin" gitleaks
  chmod +x "$TOOLS_DIR/bin/gitleaks"

  echo "installing osv-scanner ${OSV_VERSION}"
  curl -sSfL \
    "https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}/osv-scanner_linux_amd64" \
    -o "$TOOLS_DIR/bin/osv-scanner"
  chmod +x "$TOOLS_DIR/bin/osv-scanner"

  echo "installing semgrep"
  python3 -m venv --copies "$TOOLS_DIR/venv"
  "$TOOLS_DIR/venv/bin/pip" install --upgrade pip
  "$TOOLS_DIR/venv/bin/pip" install semgrep
  ln -sf "$TOOLS_DIR/venv/bin/semgrep" "$TOOLS_DIR/bin/semgrep"
}

cmd_overlay() {
  echo "installing OS packages and snapshotting apk overlay"
  if ! command -v apk >/dev/null 2>&1; then
    echo "apk not available; cannot install Alpine packages" >&2
    exit 1
  fi
  before="$(mktemp)"
  list_installed_pkgver > "$before"
  # apk-tools 3: apk add --no-cache drops the index, so apk fetch is a
  # no-op (exit 0, empty dir). Snapshot files from packages that add
  # actually installed.
  # shellcheck disable=SC2086
  apk add --no-cache $APK_PACKAGES
  write_apk_overlay "$before"
  rm -f "$before"
}

cmd_install() {
  echo "installing OS packages and quality-gate tools"
  cmd_overlay
  install_tools
}

cmd_pack() {
  ws="$(workspace_dir)"
  if [ ! -d "$TOOLS_DIR/bin" ]; then
    echo "tools bin missing; install tools before packing" >&2
    exit 1
  fi
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  mkdir -p "$stage/workspace" "$stage/tools" "$stage/overlay"
  tar -C "$ws" -cf - . | tar -C "$stage/workspace" -xf -
  tar -C "$TOOLS_DIR" -cf - . | tar -C "$stage/tools" -xf -
  if [ -d "$OVERLAY_DIR" ]; then
    tar -C "$OVERLAY_DIR" -cf - . | tar -C "$stage/overlay" -xf -
  fi
  mkdir -p "$(dirname "$TAR_PATH")"
  tar -C "$stage" -czf "$TAR_PATH" workspace tools overlay
  trap - EXIT
  rm -rf "$stage"
  echo "packed $TAR_PATH"
}

apply_system_restore() {
  if [ "$TOOLS_DIR" != "/opt/ci-tools" ]; then
    return
  fi
  if [ -d "$OVERLAY_DIR" ]; then
    tar -C "$OVERLAY_DIR" -cf - . | tar -C / -xf -
  fi
  mkdir -p /usr/local/bin
  if [ -d "$TOOLS_DIR/bin" ]; then
    for f in "$TOOLS_DIR/bin"/*; do
      [ -e "$f" ] || continue
      ln -sf "$f" "/usr/local/bin/$(basename "$f")"
    done
  fi
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$TOOLS_DIR/bin" >> "$GITHUB_PATH"
    if [ -d "$TOOLS_DIR/venv/bin" ]; then
      echo "$TOOLS_DIR/venv/bin" >> "$GITHUB_PATH"
    fi
  fi
}

cmd_unpack() {
  ws="$(workspace_dir)"
  if [ ! -f "$TAR_PATH" ]; then
    echo "missing tarball $TAR_PATH" >&2
    exit 1
  fi
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  tar -C "$stage" -xzf "$TAR_PATH"
  mkdir -p "$ws" "$TOOLS_DIR" "$OVERLAY_DIR"
  tar -C "$stage/workspace" -cf - . | tar -C "$ws" -xf -
  if [ -d "$stage/tools" ]; then
    tar -C "$stage/tools" -cf - . | tar -C "$TOOLS_DIR" -xf -
  fi
  if [ -d "$stage/overlay" ]; then
    tar -C "$stage/overlay" -cf - . | tar -C "$OVERLAY_DIR" -xf -
  fi
  trap - EXIT
  rm -rf "$stage"
  apply_system_restore
  echo "restored workspace=$ws tools=$TOOLS_DIR"
}

cmd_upload() {
  if [ ! -f "$TAR_PATH" ]; then
    echo "missing tarball $TAR_PATH" >&2
    exit 1
  fi
  if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "missing GITHUB_RUN_ID" >&2
    exit 1
  fi
  token="$(artifact_token)"
  base="$(artifact_base)"
  create_url="${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview"
  resp="$(mktemp)"
  curl -fsS -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -X POST --data "{\"Type\":\"actions_storage\",\"Name\":\"${ARTIFACT_NAME}\"}" \
    "$create_url" -o "$resp"
  upload_url="$(json_string fileContainerResourceUrl "$resp")"
  rm -f "$resp"
  if [ -z "$upload_url" ]; then
    echo "artifact create did not return fileContainerResourceUrl" >&2
    exit 1
  fi
  upload_url="$(rewrite_runtime_url "$upload_url")"
  size="$(wc -c <"$TAR_PATH" | tr -d ' ')"
  md5="$(md5_b64 "$TAR_PATH")"
  filename="$(basename "$TAR_PATH")"
  put_url="${upload_url}?itemPath=${ARTIFACT_NAME}%2F${filename}"
  curl -fsS -H "Authorization: Bearer ${token}" \
    -H "x-actions-results-md5: ${md5}" \
    -H "x-tfs-filelength: ${size}" \
    -H "content-range: bytes 0-$((size - 1))/${size}" \
    -X PUT --data-binary "@${TAR_PATH}" \
    "$put_url" -o /dev/null
  curl -fsS -H "Authorization: Bearer ${token}" \
    -X PATCH \
    "${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview&artifactName=${ARTIFACT_NAME}" \
    -o /dev/null
  echo "uploaded artifact ${ARTIFACT_NAME}"
}

cmd_download() {
  if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "missing GITHUB_RUN_ID" >&2
    exit 1
  fi
  token="$(artifact_token)"
  base="$(artifact_base)"
  list_url="${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview"
  resp="$(mktemp)"
  curl -fsS -H "Authorization: Bearer ${token}" "$list_url" -o "$resp"
  container_url="$(json_string fileContainerResourceUrl "$resp")"
  rm -f "$resp"
  if [ -z "$container_url" ]; then
    echo "artifact list did not return fileContainerResourceUrl" >&2
    exit 1
  fi
  container_url="$(rewrite_runtime_url "$container_url")"
  files="$(mktemp)"
  curl -fsS -H "Authorization: Bearer ${token}" \
    "${container_url}?itemPath=${ARTIFACT_NAME}" -o "$files"
  content_url="$(json_string contentLocation "$files")"
  item_path="$(json_string path "$files")"
  rm -f "$files"
  if [ -z "$content_url" ]; then
    echo "artifact download_url did not return contentLocation" >&2
    exit 1
  fi
  content_url="$(rewrite_runtime_url "$content_url")"
  mkdir -p "$(dirname "$TAR_PATH")"
  encoded_path="$(printf '%s' "$item_path" | sed 's|/|%2F|g')"
  curl -fsS -H "Authorization: Bearer ${token}" \
    "${content_url}?itemPath=${encoded_path}" -o "$TAR_PATH"
  echo "downloaded $TAR_PATH"
}

cmd_prepare() {
  if [ "${CI_ENV_SKIP_INSTALL:-}" != "1" ]; then
    cmd_install
  fi
  cmd_pack
  cmd_upload
}

cmd_restore() {
  echo "restoring prepared environment"
  cmd_download
  cmd_unpack
  export PATH="${TOOLS_DIR}/bin:${PATH}"
  if [ -d "${TOOLS_DIR}/venv/bin" ]; then
    export PATH="${TOOLS_DIR}/venv/bin:${PATH}"
  fi
}

usage() {
  echo "usage: $0 prepare|restore|install|overlay|pack|unpack|upload|download" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  prepare) cmd_prepare ;;
  restore) cmd_restore ;;
  install) cmd_install ;;
  overlay) cmd_overlay ;;
  pack) cmd_pack ;;
  unpack) cmd_unpack ;;
  upload) cmd_upload ;;
  download) cmd_download ;;
  *) usage ;;
esac
