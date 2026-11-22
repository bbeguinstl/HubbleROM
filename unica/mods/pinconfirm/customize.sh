# The PIN auto-confirm change touches two framework methods and two Settings
# methods. Samsung has changed these internals between One UI releases, so only
# apply the feature when all four patch sites still match. A partial patch can
# expose a Settings toggle that the framework no longer supports.
PINCONFIRM_SERVICES="system/framework/services.jar"
PINCONFIRM_SETTINGS="system/priv-app/SecSettings/SecSettings.apk"

if ! DECODE_APK "system" "$PINCONFIRM_SERVICES" || \
        ! DECODE_APK "system" "$PINCONFIRM_SETTINGS"; then
    LOGW "Skipping 4-digit PIN auto-confirm: required framework or Settings APK is unavailable"
    return 0
fi

PINCONFIRM_SERVICES_ROOT="$APKTOOL_DIR/system/framework/services.jar"
PINCONFIRM_SETTINGS_ROOT="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
PINCONFIRM_SERVICE_SMALI="$(find "$PINCONFIRM_SERVICES_ROOT" -type f \
    -path '*/com/android/server/locksettings/SyntheticPasswordManager.smali' \
    -print -quit)"
PINCONFIRM_SETTINGS_SMALI="$(find "$PINCONFIRM_SETTINGS_ROOT" -type f \
    -path '*/com/android/settings/password/ChooseLockPassword$ChooseLockPasswordFragment.smali' \
    -print -quit)"

# Return success if a method contains either the original instruction or its
# replacement. The latter makes reruns against a decoded cache idempotent.
PINCONFIRM_HAS_PATCH_SITE()
{
    local FILE="$1"
    local METHOD="$2"
    local ORIGINAL="$3"
    local REPLACEMENT="$4"

    [ -f "$FILE" ] || return 1
    awk -v FN="$METHOD" -v ORIGINAL="$ORIGINAL" -v REPLACEMENT="$REPLACEMENT" '
        /^\.method/ && index($0, FN) { inside = 1 }
        inside {
            line = $0
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == ORIGINAL || line == REPLACEMENT) found = 1
        }
        inside && /^\.end method/ { inside = 0 }
        END { exit !found }
    ' "$FILE"
}

PINCONFIRM_COMPATIBLE=true
if [ ! "$PINCONFIRM_SERVICE_SMALI" ] || [ ! "$PINCONFIRM_SETTINGS_SMALI" ] || \
        ! PINCONFIRM_HAS_PATCH_SITE "$PINCONFIRM_SERVICE_SMALI" \
            'refreshPinLengthOnDisk(Landroid/app/admin/PasswordMetrics;JI)Z' \
            'const/4 p1, 0x6' 'const/4 p1, 0x4' || \
        ! PINCONFIRM_HAS_PATCH_SITE "$PINCONFIRM_SERVICE_SMALI" \
            'createLskfBasedProtector(Landroid/service/gatekeeper/IGateKeeperService;Lcom/android/internal/widget/LockscreenCredential;JLcom/android/internal/widget/LockscreenCredential;Lcom/android/server/locksettings/SyntheticPassword;I)Lcom/android/server/locksettings/SyntheticPasswordManager$CreatedLskfBasedProtectorIds;' \
            'const/4 v12, 0x6' 'const/4 v12, 0x4' || \
        ! PINCONFIRM_HAS_PATCH_SITE "$PINCONFIRM_SETTINGS_SMALI" \
            'handleNext$2()V' 'const/4 v2, 0x6' 'const/4 v2, 0x4' || \
        ! PINCONFIRM_HAS_PATCH_SITE "$PINCONFIRM_SETTINGS_SMALI" \
            'setAutoPinConfirmOption(IZ)V' 'const/4 p2, 0x6' 'const/4 p2, 0x4'; then
    PINCONFIRM_COMPATIBLE=false
fi

if ! $PINCONFIRM_COMPATIBLE; then
    LOGW "Skipping 4-digit PIN auto-confirm: One UI donor changed one or more expected patch sites"
else
    PINCONFIRM_SERVICE_SMALI="${PINCONFIRM_SERVICE_SMALI#"$PINCONFIRM_SERVICES_ROOT"/}"
    PINCONFIRM_SETTINGS_SMALI="${PINCONFIRM_SETTINGS_SMALI#"$PINCONFIRM_SETTINGS_ROOT"/}"

    SMALI_PATCH "system" "$PINCONFIRM_SERVICES" \
        "$PINCONFIRM_SERVICE_SMALI" "replace" \
        'refreshPinLengthOnDisk(Landroid/app/admin/PasswordMetrics;JI)Z' \
        'const/4 p1, 0x6' 'const/4 p1, 0x4'

    # shellcheck disable=SC2016
    SMALI_PATCH "system" "$PINCONFIRM_SERVICES" \
        "$PINCONFIRM_SERVICE_SMALI" "replace" \
        'createLskfBasedProtector(Landroid/service/gatekeeper/IGateKeeperService;Lcom/android/internal/widget/LockscreenCredential;JLcom/android/internal/widget/LockscreenCredential;Lcom/android/server/locksettings/SyntheticPassword;I)Lcom/android/server/locksettings/SyntheticPasswordManager$CreatedLskfBasedProtectorIds;' \
        'const/4 v12, 0x6' 'const/4 v12, 0x4'

    SMALI_PATCH "system" "$PINCONFIRM_SETTINGS" \
        "$PINCONFIRM_SETTINGS_SMALI" "replace" \
        'handleNext$2()V' \
        'const/4 v2, 0x6' 'const/4 v2, 0x4'
    SMALI_PATCH "system" "$PINCONFIRM_SETTINGS" \
        "$PINCONFIRM_SETTINGS_SMALI" "replace" \
        'setAutoPinConfirmOption(IZ)V' \
        'const/4 p2, 0x6' 'const/4 p2, 0x4'
fi

unset -f PINCONFIRM_HAS_PATCH_SITE
unset PINCONFIRM_SERVICES PINCONFIRM_SETTINGS PINCONFIRM_SERVICES_ROOT \
    PINCONFIRM_SETTINGS_ROOT PINCONFIRM_SERVICE_SMALI \
    PINCONFIRM_SETTINGS_SMALI PINCONFIRM_COMPATIBLE
