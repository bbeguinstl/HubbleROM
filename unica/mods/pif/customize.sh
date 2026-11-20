APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/framework.jar/0001-Introduce-PlayIntegrityHooks.patch"
FRAMEWORK_APK="$APKTOOL_DIR/system/framework/framework.jar"
INSTRUMENTATION_SMALI="$(find "$FRAMEWORK_APK" -type f -path '*/android/app/Instrumentation.smali' -printf '%P\n' -quit)"
if ! grep -q -F 'PlayIntegrityHooks;->setProps(Landroid/content/Context;)V' "$FRAMEWORK_APK/$INSTRUMENTATION_SMALI"; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p1}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p3}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null
fi
unset FRAMEWORK_APK INSTRUMENTATION_SMALI
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0001-Introduce-PlayIntegrityHooks.patch"

if [ ! -f "$APKTOOL_DIR/system/framework/framework.jar/smali_classes7/io/mesalabs/unica/KeyboxImitationHooks.smali" ]; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes7/io/mesalabs/unica/PlayIntegrityHooks.smali" "return" \
        'shouldBlockKeyAttestation()Z' 'true'
fi
