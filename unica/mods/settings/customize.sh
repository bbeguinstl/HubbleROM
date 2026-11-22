# Show battery regulatory info in Settings
# Requires SEM_BATTERY_PROPERTY_IC_AUTHENTICATION_RESULT support
DECODE_APK "system" "system/framework/framework.jar"
FRAMEWORK_APK="$APKTOOL_DIR/system/framework/framework.jar"
FRAMEWORK_DEX_VERSION="$(unzip -p "$WORK_DIR/system/system/framework/framework.jar" classes.dex | dd bs=1 skip=4 count=3 2> /dev/null)"
FRAMEWORK_DEX_METHOD_IDS="$(unzip -p "$WORK_DIR/system/system/framework/framework.jar" classes.dex | dd bs=1 skip=88 count=4 2> /dev/null | od -An -tu4 --endian=little | tr -d ' ')"
INSTRUMENTATION_SMALI="$(find "$FRAMEWORK_APK" -type f -path '*/android/app/Instrumentation.smali' -printf '%P\n' -quit)"
if [ "$FRAMEWORK_DEX_VERSION" = "041" ] && \
        [ "$FRAMEWORK_DEX_METHOD_IDS" -ge "65536" ] && \
        [[ "$INSTRUMENTATION_SMALI" == smali/* ]]; then
    mkdir -p "$FRAMEWORK_APK/smali_classes8/android/app"
    mv "$FRAMEWORK_APK/$INSTRUMENTATION_SMALI" \
        "$FRAMEWORK_APK/smali_classes8/android/app/Instrumentation.smali"
    INSTRUMENTATION_SMALI="smali_classes8/android/app/Instrumentation.smali"
    LOG "- Moved Instrumentation into a separate DEX to keep the beta framework under its method-reference limit"
fi
for CLASS_PATH in \
        'android/security/KeyStore2.smali' \
        'android/system/keystore2/IKeystoreSecurityLevel$Stub$Proxy.smali' \
        'android/system/keystore2/IKeystoreService$Stub$Proxy.smali' \
        'android/security/keystore2/AndroidKeyStoreSpi.smali'; do
    CLASS_SOURCE="$FRAMEWORK_APK/smali_classes4/$CLASS_PATH"
    if [ -f "$CLASS_SOURCE" ]; then
        mkdir -p "$FRAMEWORK_APK/smali_classes8/$(dirname "$CLASS_PATH")"
        mv "$CLASS_SOURCE" "$FRAMEWORK_APK/smali_classes8/$CLASS_PATH"
        LOG "- Moved patched $(basename "$CLASS_PATH") into the DEX overflow area"
    fi
done

if [ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS")" ]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS" --delete
fi
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"

if ! grep -q -F 'SamsungPropsHooks;->init(Landroid/content/Context;)V' "$FRAMEWORK_APK/$INSTRUMENTATION_SMALI"; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
        'invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
        '    invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p1}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
        > /dev/null
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
        'invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
        '    invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p3}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
        > /dev/null
fi

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"
SECSETTINGS_APK="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"

# Disable stock OTA references, unless the ROM ships an updater: ChoiDujour,
# or FotaAgent patched by unica/mods/fotaagent into the ROM update downloader.
if [ ! -f "$WORK_DIR/system/system/priv-app/ChoiDujour/ChoiDujour.apk" ] && \
        [ ! -f "$WORK_DIR/system/system/priv-app/FotaAgent/FotaAgent.apk" ]; then
    SOFTWARE_UPDATE_UTILS="$(find "$SECSETTINGS_APK" \
        -type f -path '*/com/samsung/android/settings/softwareupdate/SoftwareUpdateUtils.smali' -printf '%P\n' -quit)"
    [ "$SOFTWARE_UPDATE_UTILS" ] || ABORT "SoftwareUpdateUtils.smali not found"
    if grep -q -F '.method public static isOTAUpgradeAllowed(Landroid/content/Context;)Z' \
            "$SECSETTINGS_APK/$SOFTWARE_UPDATE_UTILS"; then
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$SOFTWARE_UPDATE_UTILS" "return" \
            'isOTAUpgradeAllowed(Landroid/content/Context;)Z' \
            'false'
    else
        SOFTWARE_UPDATE_CONTROLLER="$(find "$SECSETTINGS_APK" \
            -type f -path '*/com/samsung/android/settings/homepage/TopLevelSoftwareUpdatePreferenceController.smali' \
            -printf '%P\n' -quit)"
        [ "$SOFTWARE_UPDATE_CONTROLLER" ] || \
            ABORT "TopLevelSoftwareUpdatePreferenceController.smali not found"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$SOFTWARE_UPDATE_CONTROLLER" "return" \
            'getAvailabilityStatus()I' \
            '3'
    fi
    unset SOFTWARE_UPDATE_UTILS
fi

# Always show One UI minor version
ONEUI_VERSION_CONTROLLER="$(find "$SECSETTINGS_APK" -type f \
    -path '*/com/samsung/android/settings/deviceinfo/softwareinfo/OneUIVersionPreferenceController.smali' \
    -printf '%P\n' -quit)"
[ "$ONEUI_VERSION_CONTROLLER" ] || ABORT "OneUIVersionPreferenceController.smali not found"
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "$ONEUI_VERSION_CONTROLLER" "replace" \
    'isDeviceWithMicroVersion()Z' \
    'move-result p0' \
    'const/4 p0, 0x1'

# Show the target model number from the bootloader-provided model property.
MODEL_NAME_PROVIDER="$(find "$SECSETTINGS_APK" -type f \
    -path '*/com/samsung/android/settings/deviceinfo/aboutphone/ModelNameProvider.smali' \
    -printf '%P\n' -quit)"
if [ "$MODEL_NAME_PROVIDER" ]; then
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODEL_NAME_PROVIDER" "replace" \
        'getModelName()Ljava/lang/String;' \
        'ro.product.model' \
        'ro.boot.em.model'
elif [ "$TARGET_ASSERT_MODEL" ]; then
    # Android 17 beta Settings removed ModelNameProvider. Use the target model
    # directly so About device does not keep the donor S26+ model number.
    TARGET_MODEL_NAME="${TARGET_ASSERT_MODEL%%:*}"
    LOGW "ModelNameProvider.smali is absent; setting ro.product.model to $TARGET_MODEL_NAME"
    SET_PROP "system" "ro.product.model" "$TARGET_MODEL_NAME"
else
    LOGW "ModelNameProvider.smali is absent; keeping the current ro.product.model"
fi

LOG_STEP_IN "- Adding Hubble Settings"

# Dynamically patch SecSettings
# - Add missing/non-xml files in place
# - Patch existing files
#   - Use the first line of the file to tell sed how to apply the rest of the content
#   - Exception made for files under *res/values* where the "resources" tag gets nuked
while IFS= read -r f; do
    f="${f//$MODPATH\/SecSettings.apk\//}"

    # Full XML overlays (for example unica_ui_settings.xml) may already exist
    # in an incremental work-dir.  They are documents, not sed instructions;
    # copy them again instead of attempting to execute their XML declaration.
    # res/values XML remains additive and is handled by the branch below.
    if [ ! -f "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f" ] || \
            [[ "$f" != *".xml" ]] || \
            { [[ "$f" != *"res/values"* ]] && head -n 1 "$MODPATH/SecSettings.apk/$f" | grep -q '^<?xml '; }; then
        LOG "- Adding \"$f\" to /system/system/priv-app/SecSettings.apk"
        EVAL "mkdir -p \"$(dirname "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f")\""
        EVAL "cp -a \"$MODPATH/SecSettings.apk/${f//\$/\\$}\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/${f//\$/\\$}\""
    else
        LOG "- Patching \"$f\" in /system/system/priv-app/SecSettings.apk"
        if [[ "$f" == *"res/values"* ]]; then
            PATCH_INST="/<\/resources>/i"
            CONTENT="$(sed -e "/?xml/d" -e "/resources>/d" "$MODPATH/SecSettings.apk/$f")"
            # Module customization may run again when reusing a work directory.
            # Keep values resources additive without appending entries that are
            # already present in the decoded APK.
            CONTENT="$(awk -v target="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f" '
                BEGIN {
                    while ((getline line < target) > 0) {
                        if (match(line, /name="[^"]+"/)) {
                            name = substr(line, RSTART + 6, RLENGTH - 7)
                            seen[name] = 1
                        }
                    }
                    close(target)
                }
                {
                    if (match($0, /name="[^"]+"/)) {
                        name = substr($0, RSTART + 6, RLENGTH - 7)
                        if (seen[name]) next
                        seen[name] = 1
                    }
                    print
                }
            ' <<< "$CONTENT")"
        else
            PATCH_INST="$(head -n 1 "$MODPATH/SecSettings.apk/$f")"
            CONTENT="$(tail -n +2 "$MODPATH/SecSettings.apk/$f")"
        fi
        CONTENT="$(sed -e "s/\"/\\\\\"/g" -e "s/\\$/\\\\$/g" -e "s/ /\\\ /g" -e "s/\\\\n/\\\\\\\\\n/g" <<< "$CONTENT")"
        CONTENT="$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' <<< "$CONTENT")"
        EVAL "sed -i \"$PATCH_INST $CONTENT\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f\""
    fi
done < <(find "$MODPATH/SecSettings.apk" -type f)

# Add the HubbleROM banner above the About device details.
ABOUT_DEVICE_XML="$SECSETTINGS_APK/res/xml/sec_my_device_info.xml"
if ! grep -q 'key="hubble_about_banner"' "$ABOUT_DEVICE_XML"; then
    sed -i '/<com.samsung.android.settings.widget.SecInsetCategoryPreference/i\    <com.android.settingslib.widget.LayoutPreference android:key="hubble_about_banner" android:layout="@layout/hubble_about_banner_layout" android:selectable="false" android:order="-10" />' \
        "$ABOUT_DEVICE_XML"
fi
if ! grep -q 'key="hubble_rom_version"' "$ABOUT_DEVICE_XML"; then
    sed -i '/<com.samsung.android.settings.widget.SecInsetCategoryPreference/a\    <Preference android:key="hubble_rom_version" android:title="@string/unica_rom_version_title" android:summary="@string/summary_placeholder" android:order="25" settings:controller="io.mesalabs.unica.settings.ROMVersionPreferenceController" />' \
        "$ABOUT_DEVICE_XML"
fi
unset ABOUT_DEVICE_XML

# Add Hubble Settings SearchIndexableData registrations
SEARCH_INDEXABLE_RESOURCES="$(find "$SECSETTINGS_APK" -type f \
    -path '*/com/android/settingslib/search/SearchIndexableResourcesMobile.smali' -printf '%P\n' -quit)"
SEARCH_FEATURE_PROVIDER="$(find "$SECSETTINGS_APK" -type f \
    -path '*/com/android/settings/search/SearchFeatureProviderImpl$$ExternalSyntheticLambda0.smali' \
    -printf '%P\n' -quit)"
[ "$SEARCH_INDEXABLE_RESOURCES" ] || ABORT "SearchIndexableResourcesMobile.smali not found"
[ "$SEARCH_FEATURE_PROVIDER" ] || ABORT "SearchFeatureProviderImpl lambda not found"
LOG "- Patching \"$SEARCH_INDEXABLE_RESOURCES\" in /system/system/priv-app/SecSettings.apk"
if grep -q -F '.class public final Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        "$SECSETTINGS_APK/$SEARCH_INDEXABLE_RESOURCES"; then
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$SEARCH_INDEXABLE_RESOURCES" "replaceall" \
        '.class public final Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        '.class public Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        > /dev/null
else
    LOG "- SearchIndexableResourcesMobile is already public; skipping"
fi
LOG "- Patching \"$SEARCH_FEATURE_PROVIDER\" in /system/system/priv-app/SecSettings.apk"
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "$SEARCH_FEATURE_PROVIDER" "replace" \
    'invoke()Ljava/lang/Object;' \
    'return-object p0' \
    '    invoke-static {p0}, Lio/mesalabs/unica/search/UnicaSearchIndexableResources;->addIndexes(Lcom/android/settingslib/search/SearchIndexableResourcesBase;)V\n\n    return-object p0' \
    > /dev/null

DECODE_APK "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
TOP_LEVEL_KEYS_COLLECTOR="$(find "$APKTOOL_DIR/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    -type f -path '*/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali' \
    -printf '%P\n' -quit)"
[ "$TOP_LEVEL_KEYS_COLLECTOR" ] || ABORT "TopLevelKeysCollector.smali not found"
LOG "- Patching \"$TOP_LEVEL_KEYS_COLLECTOR\" in /system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
TOP_LEVEL_KEYS_FILE="$APKTOOL_DIR/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk/$TOP_LEVEL_KEYS_COLLECTOR"
if ! grep -q -F '"top_level_unica"' "$TOP_LEVEL_KEYS_FILE"; then
    TOP_LEVEL_KEYS_LOCALS="$(awk '
        /^\.method .*<init>\(Landroid\/content\/Context;\)V$/ { inside=1; next }
        inside && /^    \.locals [0-9]+$/ { print $2; exit }
    ' "$TOP_LEVEL_KEYS_FILE")"
    TOP_LEVEL_KEYS_ARRAY="$(awk '
        /^\.method .*<init>\(Landroid\/content\/Context;\)V$/ { inside=1; next }
        inside && /filled-new-array\/range \{v1 \.\. v[0-9]+\}, \[Ljava\/lang\/String;/ {
            print
            exit
        }
        inside && /^\.end method$/ { exit }
    ' "$TOP_LEVEL_KEYS_FILE")"
    if [[ ! "$TOP_LEVEL_KEYS_LOCALS" =~ ^[0-9]+$ ]] || \
            [[ ! "$TOP_LEVEL_KEYS_ARRAY" =~ v1[[:space:]]+\.\.[[:space:]]+v([0-9]+) ]]; then
        ABORT "Unable to resolve TopLevelKeysCollector registers"
    fi
    TOP_LEVEL_KEYS_LAST_REGISTER="${BASH_REMATCH[1]}"
    TOP_LEVEL_KEYS_NEW_REGISTER=$((TOP_LEVEL_KEYS_LAST_REGISTER + 1))
    TOP_LEVEL_KEYS_NEW_LOCALS=$((TOP_LEVEL_KEYS_LOCALS + 1))
    SMALI_PATCH "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
        "$TOP_LEVEL_KEYS_COLLECTOR" "replace" \
        '<init>(Landroid/content/Context;)V' \
        ".locals $TOP_LEVEL_KEYS_LOCALS" \
        ".locals $TOP_LEVEL_KEYS_NEW_LOCALS" \
        > /dev/null
    SMALI_PATCH "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
        "$TOP_LEVEL_KEYS_COLLECTOR" "replace" \
        '<init>(Landroid/content/Context;)V' \
        "$TOP_LEVEL_KEYS_ARRAY" \
        "    const-string v$TOP_LEVEL_KEYS_NEW_REGISTER, \"top_level_unica\"\n\n    filled-new-array/range {v1 .. v$TOP_LEVEL_KEYS_NEW_REGISTER}, [Ljava/lang/String;" \
        > /dev/null
fi

# Show Vulkan renderer toggle if required
if [[ "$(GET_PROP "ro.hwui.use_vulkan")" != "true" ]]; then
    SET_PROP "system" "persist.sys.unica.vulkan" "false"
fi

unset PATCH_INST CONTENT SECSETTINGS_APK SOFTWARE_UPDATE_UTILS SOFTWARE_UPDATE_CONTROLLER
unset ONEUI_VERSION_CONTROLLER MODEL_NAME_PROVIDER TARGET_MODEL_NAME SEARCH_INDEXABLE_RESOURCES SEARCH_FEATURE_PROVIDER
unset TOP_LEVEL_KEYS_COLLECTOR
unset TOP_LEVEL_KEYS_FILE TOP_LEVEL_KEYS_LOCALS TOP_LEVEL_KEYS_ARRAY
unset TOP_LEVEL_KEYS_LAST_REGISTER TOP_LEVEL_KEYS_NEW_REGISTER TOP_LEVEL_KEYS_NEW_LOCALS

LOG_STEP_OUT
