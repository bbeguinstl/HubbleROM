SET_PROP_IF_DIFF "vendor" "ro.oem_unlock_supported" "0"

# Better device/model detection in CoreRune
CORE_RUNE_SMALI="smali_classes6/com/samsung/android/rune/CoreRune.smali"
if [ ! -f "$APKTOOL_DIR/system/framework/framework.jar/$CORE_RUNE_SMALI" ]; then
    CORE_RUNE_MATCHES="$(find "$APKTOOL_DIR/system/framework/framework.jar" -path \
        '*/com/samsung/android/rune/CoreRune.smali' -type f | sort)"
    if [ "$(printf '%s\n' "$CORE_RUNE_MATCHES" | sed '/^$/d' | wc -l)" -ne 1 ]; then
        ABORT "Unable to uniquely locate CoreRune in framework.jar"
    fi
    CORE_RUNE_SMALI="${CORE_RUNE_MATCHES#"$APKTOOL_DIR/system/framework/framework.jar/"}"
fi
SMALI_PATCH "system" "system/framework/framework.jar" \
    "$CORE_RUNE_SMALI" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'
SMALI_PATCH "system" "system/framework/framework.jar" \
    "$CORE_RUNE_SMALI" "replace" \
    '<clinit>()V' \
    'ro.product.device' \
    'ro.product.vendor.device'

# Disable RescueParty when the AOSP implementation is present. Android 17's
# Samsung framework no longer ships this class or its isDisabled() entrypoint.
if [ -f "$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/RescueParty.smali" ]; then
    # shellcheck disable=SC2016
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/RescueParty.smali" "return" \
        '-$$Nest$smisDisabled()Z' \
        'true'
else
    LOG "- AOSP RescueParty implementation is absent; skipping legacy disable patch"
fi

# Better model detection in FreecessController
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali/com/android/server/am/FreecessController.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'

# The Android 17 services.jar removed the old ActivityManagerService lambda
# that displayed the build-fingerprint mismatch warning. Preserve the legacy
# patch for older sources, but skip it when that implementation is absent.
if ! rg -l -F 'Build fingerprint is not consistent, warning user' \
        "$APKTOOL_DIR/system/framework/services.jar"/smali* >/dev/null 2>&1; then
    LOG "- Android 17 services.jar has no legacy vendor-mismatch warning"
fi

unset CORE_RUNE_SMALI CORE_RUNE_MATCHES
