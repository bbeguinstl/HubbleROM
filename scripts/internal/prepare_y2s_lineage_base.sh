#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare the official LineageOS 24 y2s device base used by HubbleROM.
set -euo pipefail

[[ "${TARGET_CODENAME:-}" == "y2s" ]] || exit 0
source "$SRC_DIR/scripts/utils/log_utils.sh"

OTA_NAME="lineage-24.0-20261114-nightly-y2s-signed.zip"
OTA_URL="https://mirrorbits.lineageos.org/full/y2s/20261114/$OTA_NAME"
OTA_SHA256="9537ed3267c53d2709f90dfbaa8b68b65ea3bf446d4546bb989bd7be42a621f8"
BOOT_SHA256="89f2278c081c97e1b8a5184f6db09081b55945089ecf5cb9f0a52666d6e52b13"
DTBO_SHA256="4e647f2dc7282b271bbaedee9774ab2a72463e70d5678dbf38bba5471d27fb8f"
BASE_DIR="$OUT_DIR/lineage_y2s_24"
SCRIPT_SHA256="$(sha256sum "$0" | cut -d ' ' -f 1)"

if [[ -s "$BASE_DIR/boot.img" && -s "$BASE_DIR/dtbo.img" && \
        -d "$BASE_DIR/vendor" && -s "$BASE_DIR/config/vendor_fs_config" && \
        -s "$BASE_DIR/config/vendor_file_contexts" && \
        -f "$BASE_DIR/source.sha256" ]] && \
        [[ "$(cat "$BASE_DIR/source.sha256")" == "$OTA_SHA256 $SCRIPT_SHA256" ]]; then
    LOG "- Reusing prepared LineageOS 24 y2s device base"
    exit 0
fi

for TOOL in curl unzip brotli sha256sum; do
    command -v "$TOOL" >/dev/null 2>&1 || {
        LOGE "Missing required tool: $TOOL"
        exit 1
    }
done
for TOOL in "$TOOLS_DIR/bin/extract.erofs" "$SRC_DIR/scripts/internal/sdat2img.py"; do
    [[ -x "$TOOL" || -f "$TOOL" ]] || {
        LOGE "Missing required tool: ${TOOL//$SRC_DIR\//}"
        exit 1
    }
done

TMP_DIR="$(mktemp -d "$OUT_DIR/lineage-y2s.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
OTA_PATH="${LINEAGE_Y2S_OTA_PATH:-$TMP_DIR/$OTA_NAME}"

if [[ ! -f "$OTA_PATH" ]]; then
    LOG "- Downloading official LineageOS 24 y2s base"
    curl -fL --retry 3 --retry-delay 2 "$OTA_URL" -o "$OTA_PATH"
fi

ACTUAL_OTA_SHA256="$(sha256sum "$OTA_PATH" | cut -d ' ' -f 1)"
[[ "$ACTUAL_OTA_SHA256" == "$OTA_SHA256" ]] || {
    LOGE "LineageOS OTA checksum mismatch: $ACTUAL_OTA_SHA256"
    exit 1
}
unzip -tq "$OTA_PATH" || {
    LOGE "LineageOS OTA archive is corrupt"
    exit 1
}

LOG "- Extracting LineageOS vendor image"
unzip -p "$OTA_PATH" vendor.transfer.list > "$TMP_DIR/vendor.transfer.list"
unzip -p "$OTA_PATH" vendor.new.dat.br | brotli -d -c | \
    python3 "$SRC_DIR/scripts/internal/sdat2img.py" \
        "$TMP_DIR/vendor.transfer.list" - "$TMP_DIR/vendor.img"
mkdir -p "$TMP_DIR/extracted"
"$TOOLS_DIR/bin/extract.erofs" -i "$TMP_DIR/vendor.img" -x -s \
    -T6 -o "$TMP_DIR/extracted" || {
        LOGE "Could not extract the LineageOS vendor image"
        exit 1
    }
[[ -d "$TMP_DIR/extracted/vendor" && \
        -s "$TMP_DIR/extracted/config/vendor_fs_config" && \
        -s "$TMP_DIR/extracted/config/vendor_file_contexts" ]] || {
    LOGE "LineageOS vendor metadata is incomplete"
    exit 1
}

# extract.erofs labels the image root as both "/" and "vendor/". HubbleROM's
# image builder expects the canonical Samsung form: "vendor" in fs_config
# and "/vendor" in file_contexts.
python3 - "$TMP_DIR/extracted/config/vendor_fs_config" \
    "$TMP_DIR/extracted/config/vendor_file_contexts" <<'PY'
from pathlib import Path
import sys

fs_config, file_contexts = map(Path, sys.argv[1:])
normalized = []
seen = set()
for line in fs_config.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if not fields:
        continue
    if fields[0] in {"/", "vendor/"}:
        fields[0] = "vendor"
    elif fields[0].startswith("/vendor/"):
        fields[0] = fields[0][1:]
    line = " ".join(fields)
    if line not in seen:
        normalized.append(line)
        seen.add(line)
fs_config.write_text("\n".join(normalized) + "\n", encoding="utf-8")

normalized = []
seen = set()
for line in file_contexts.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if not fields:
        continue
    if fields[0] in {"/", "/vendor/"}:
        fields[0] = "/vendor"
    line = " ".join(fields)
    if line not in seen:
        normalized.append(line)
        seen.add(line)
file_contexts.write_text("\n".join(normalized) + "\n", encoding="utf-8")
PY

mkdir -p "$BASE_DIR/config"
rm -f "$BASE_DIR/source.sha256"
rm -rf "$BASE_DIR/vendor"
cp -a "$TMP_DIR/extracted/vendor" "$BASE_DIR/vendor"
cp -a "$TMP_DIR/extracted/config/vendor_fs_config" \
    "$BASE_DIR/config/vendor_fs_config"
cp -a "$TMP_DIR/extracted/config/vendor_file_contexts" \
    "$BASE_DIR/config/vendor_file_contexts"
cp -a "$TMP_DIR/extracted/config/vendor_fs_options" \
    "$BASE_DIR/config/vendor_fs_options"
unzip -p "$OTA_PATH" boot.img > "$BASE_DIR/boot.img"
unzip -p "$OTA_PATH" dtbo.img > "$BASE_DIR/dtbo.img"

[[ "$(sha256sum "$BASE_DIR/boot.img" | cut -d ' ' -f 1)" == "$BOOT_SHA256" ]] || {
    LOGE "LineageOS boot image checksum mismatch"
    exit 1
}
[[ "$(sha256sum "$BASE_DIR/dtbo.img" | cut -d ' ' -f 1)" == "$DTBO_SHA256" ]] || {
    LOGE "LineageOS DTBO checksum mismatch"
    exit 1
}
grep -q '^ro.product.vendor.device=y2s$' "$BASE_DIR/vendor/build.prop" || {
    LOGE "LineageOS vendor image is not for y2s"
    exit 1
}
grep -q '^ro.vendor.build.version.sdk=37$' "$BASE_DIR/vendor/build.prop" || {
    LOGE "LineageOS vendor image is not Android 17 / SDK 37"
    exit 1
}
printf '%s %s\n' "$OTA_SHA256" "$SCRIPT_SHA256" > "$BASE_DIR/source.sha256"
printf '%s\n' "$OTA_NAME" > "$BASE_DIR/source.txt"
LOG "- Prepared LineageOS 24 y2s kernel, DTBO and vendor"
