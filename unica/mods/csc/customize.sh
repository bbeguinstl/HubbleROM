# Enable Power off lock feature
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/globalactions/util/SystemPropertiesWrapper.smali" "return" \
    'isBrazilianCountryISO()Z' 'true'
DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk"
SYSTEMUI_DEVICE_CONTROLLER="$(find "$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk" \
    -path '*/com/android/systemui/bixby2/controller/DeviceController.smali' -printf '%P\n' -quit)"
if [[ -n "$SYSTEMUI_DEVICE_CONTROLLER" ]]; then
    SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
        "$SYSTEMUI_DEVICE_CONTROLLER" "return" \
        'isSupportPowerOffLock()Z' 'true'
else
    LOG "- SystemUI has no Bixby DeviceController; skipping Power off lock hook"
fi

# The SystemUI dex containing QpRune changes between One UI releases. Apply
# the Smart View patch against its discovered dex path instead of assuming
# smali_classes4, and skip it when this donor's implementation has changed.
SMART_VIEW_PATCH="$SRC_DIR/unica/mods/csc/patches/0002-Enable-Smart-View-tile-visibility-settings.patch"
SYSTEMUI_QP_RUNE="$(find "$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk" \
    -path '*/com/android/systemui/QpRune.smali' -printf '%P\n' -quit)"
if [[ -n "$SYSTEMUI_QP_RUNE" ]]; then
    SMART_VIEW_PATCH_TMP="$(mktemp)"
    sed "s|smali_classes4/com/android/systemui/QpRune.smali|$SYSTEMUI_QP_RUNE|g" \
        "$SMART_VIEW_PATCH" > "$SMART_VIEW_PATCH_TMP"
    APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
        "$SMART_VIEW_PATCH_TMP" true
    rm -f -- "$SMART_VIEW_PATCH_TMP"
else
    LOG "- SystemUI has no QpRune class; skipping Smart View tile hook"
fi

# Hide Remote management tile in Settings app
DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"
REMOTE_SUPPORT_CONTROLLER="$(find "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk" \
    -path '*/com/samsung/android/settings/homepage/TopLevelRemoteSupportPreferenceController.smali' -printf '%P\n' -quit)"
if [[ -n "$REMOTE_SUPPORT_CONTROLLER" ]]; then
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$REMOTE_SUPPORT_CONTROLLER" "return" \
        'getAvailabilityStatus()I' '3'
else
    LOG "- Remote management controller is absent; its Settings tile is already hidden"
fi
    
unset SYSTEMUI_DEVICE_CONTROLLER SYSTEMUI_QP_RUNE SMART_VIEW_PATCH SMART_VIEW_PATCH_TMP \
    REMOTE_SUPPORT_CONTROLLER
