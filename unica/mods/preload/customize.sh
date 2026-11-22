# KernelSU Next
# Install the official KernelSU-Next manager release that matches the
# KernelSU-Next revision pinned in this target's kernel tree, e.g.
# v3.4.0-legacy-12-g8869bd76 -> release v3.4.0. The kernels are built with the
# default (official) manager signature, so the release APK is recognised. The
# download is checked against the sha256 digest GitHub publishes for it.
# https://github.com/tiann/KernelSU/issues/886
APK_PATH="system/preload/KernelSU-Next/com.rifsxd.ksunext-mesa==/base.apk"
KERNELSU_DIR="$OUT_DIR/kernel_tmp-$TARGET_PLATFORM/KernelSU-Next"

if [ -d "$KERNELSU_DIR" ]; then
    KERNELSU_TAG="$(git -C "$KERNELSU_DIR" describe --tags --abbrev=0 2> /dev/null)"
    # Release tags are vX.Y.Z; the legacy kernel branch tags vX.Y.Z-legacy.
    KERNELSU_RELEASE="$(grep -oE "^v[0-9]+\.[0-9]+\.[0-9]+" <<< "$KERNELSU_TAG")"
    if [ ! "$KERNELSU_RELEASE" ]; then
        ABORT "Cannot derive a KernelSU-Next release from the kernel tag \"$KERNELSU_TAG\""
    fi

    KERNELSU_API_ARGS=(
        -fsSL
        --retry 3
        --retry-all-errors
        -H "Accept: application/vnd.github+json"
    )
    if [ "${GH_TOKEN:-}" ]; then
        KERNELSU_API_ARGS+=(-H "Authorization: Bearer $GH_TOKEN")
    fi
    KERNELSU_RELEASE_DATA="$(curl "${KERNELSU_API_ARGS[@]}" \
        "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/tags/$KERNELSU_RELEASE")" || \
        ABORT "Failed to query the KernelSU-Next $KERNELSU_RELEASE release from GitHub"
    KERNELSU_ASSET="$(python3 -I -c '
import json, re, sys
for a in json.load(sys.stdin).get("assets", []):
    if re.fullmatch(r"KernelSU_Next_v[0-9.]+_[0-9]+-release\.apk", a["name"]):
        print(a["browser_download_url"], (a.get("digest") or "").removeprefix("sha256:"))
        break
' <<< "$KERNELSU_RELEASE_DATA")"
    KERNELSU_URL="$(cut -d " " -f 1 <<< "$KERNELSU_ASSET")"
    KERNELSU_SHA256="$(cut -d " " -f 2 -s <<< "$KERNELSU_ASSET")"
    if [ ! "$KERNELSU_URL" ] || [ ! "$KERNELSU_SHA256" ]; then
        ABORT "No KernelSU-Next $KERNELSU_RELEASE release APK with a digest was found"
    fi

    LOG "- Downloading KernelSU-Next $KERNELSU_RELEASE manager (kernel: $KERNELSU_TAG)"
    DOWNLOAD_FILE "$KERNELSU_URL" "$WORK_DIR/system/$APK_PATH" || \
        ABORT "Failed to download $KERNELSU_URL"
    if [ "$(sha256sum "$WORK_DIR/system/$APK_PATH" | cut -d " " -f 1)" != "$KERNELSU_SHA256" ]; then
        rm -f "$WORK_DIR/system/$APK_PATH"
        ABORT "KernelSU-Next manager download does not match its published sha256"
    fi
else
    LOG "- No KernelSU-Next kernel tree for $TARGET_PLATFORM; skipping the manager app"
    rm -rf "$WORK_DIR/system/system/preload/KernelSU-Next"
fi
unset KERNELSU_DIR KERNELSU_TAG KERNELSU_RELEASE KERNELSU_ASSET KERNELSU_URL \
    KERNELSU_SHA256 KERNELSU_RELEASE_DATA KERNELSU_API_ARGS
mkdir -p "$WORK_DIR/system/system/preload"

while IFS= read -r i; do
    i="${i//$WORK_DIR\/system\//}"

    if [ -d "$WORK_DIR/system/$i" ]; then
        SET_METADATA "system" "$i" 0 0 755 "u:object_r:system_file:s0"
    else
        SET_METADATA "system" "$i" 0 0 644 "u:object_r:system_file:s0"
    fi

    if [[ "$i" == *".apk" ]] && \
            ! grep -q "$i" "$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"; then
        LOG "- Adding \"$i\" to /system/system/etc/vpl_apks_count_list.txt"
        EVAL "echo \"$i\" >> \"$WORK_DIR/system/system/etc/vpl_apks_count_list.txt\""
    fi
done <<< "$(find "$WORK_DIR/system/system/preload")"

# Samsung Internet Browser
# https://play.google.com/store/apps/details?id=com.sec.android.app.sbrowser
SBROWSER_APK="$WORK_DIR/system/system/preload/SBrowser/SBrowser.apk"
SBROWSER_TMP="$SBROWSER_APK.download"
SBROWSER_URL="$(GET_GALAXY_STORE_DOWNLOAD_URL "com.sec.android.app.sbrowser")" || SBROWSER_URL=""
if [ "$SBROWSER_URL" ]; then
    LOG "- Downloading Samsung Internet app"
    if DOWNLOAD_FILE "$SBROWSER_URL" "$SBROWSER_TMP"; then
        mv -f "$SBROWSER_TMP" "$SBROWSER_APK"
    else
        rm -f "$SBROWSER_TMP"
        if [ -f "$SBROWSER_APK" ]; then
            LOGW "Galaxy Store download failed; keeping Samsung Internet from the source firmware"
        else
            LOGW "Galaxy Store download failed; skipping Samsung Internet preload"
        fi
    fi
elif [ -f "$SBROWSER_APK" ]; then
    LOGW "Galaxy Store download is unavailable; keeping Samsung Internet from the source firmware"
else
    LOGW "Galaxy Store download is unavailable; skipping Samsung Internet preload"
fi
unset SBROWSER_APK SBROWSER_TMP SBROWSER_URL

while IFS= read -r i; do
    i="${i//$WORK_DIR\/system\//}"

    if [ -d "$WORK_DIR/system/$i" ]; then
        SET_METADATA "system" "$i" 0 0 755 "u:object_r:system_file:s0"
    else
        SET_METADATA "system" "$i" 0 0 644 "u:object_r:system_file:s0"
    fi

    if [[ "$i" == *".apk" ]] && \
            ! grep -q "$i" "$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"; then
        LOG "- Adding \"$i\" to /system/system/etc/vpl_apks_count_list.txt"
        EVAL "echo \"$i\" >> \"$WORK_DIR/system/system/etc/vpl_apks_count_list.txt\""
    fi
done <<< "$(find "$WORK_DIR/system/system/preload")"
