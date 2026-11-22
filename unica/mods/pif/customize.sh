PIF_FRAMEWORK_PATCH="$MODPATH/framework.jar/0001-Introduce-PlayIntegrityHooks.patch"
PIF_FRAMEWORK_DIR="$APKTOOL_DIR/system/framework.jar"
DECODE_APK "system" "system/framework/framework.jar"
if ! LC_ALL=C git apply --reverse --check \
        --directory="$PIF_FRAMEWORK_DIR" --unsafe-paths "$PIF_FRAMEWORK_PATCH" \
        > /dev/null 2>&1 && \
        ! LC_ALL=C git apply --check \
            --directory="$PIF_FRAMEWORK_DIR" --unsafe-paths "$PIF_FRAMEWORK_PATCH" \
            > /dev/null 2>&1; then
    LOGW "Skipping Play Integrity hooks because this donor's framework.jar layout is incompatible"
    unset PIF_FRAMEWORK_PATCH PIF_FRAMEWORK_DIR
    return 0
fi
APPLY_PATCH "system" "system/framework/framework.jar" "$PIF_FRAMEWORK_PATCH"
unset PIF_FRAMEWORK_PATCH PIF_FRAMEWORK_DIR

FRAMEWORK_APK="$APKTOOL_DIR/system/framework/framework.jar"
INSTRUMENTATION_SMALI="$(find "$FRAMEWORK_APK" -type f -path '*/android/app/Instrumentation.smali' -printf '%P\n' -quit)"
if [ "$INSTRUMENTATION_SMALI" ] && \
        ! grep -q -F 'PlayIntegrityHooks;->setProps(Landroid/content/Context;)V' "$FRAMEWORK_APK/$INSTRUMENTATION_SMALI"; then
    if ! SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p1}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null; then
        LOGW "Skipping Play Integrity hook in the legacy newApplication overload"
    fi
    if ! SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p3}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null; then
        LOGW "Skipping Play Integrity hook in the class-loader newApplication overload"
    fi
elif [ ! "$INSTRUMENTATION_SMALI" ]; then
    LOGW "Instrumentation.smali is absent; skipping Play Integrity application hooks"
fi
unset FRAMEWORK_APK INSTRUMENTATION_SMALI
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0001-Introduce-PlayIntegrityHooks.patch" true

if [ ! -f "$APKTOOL_DIR/system/framework/framework.jar/smali_classes7/io/mesalabs/unica/KeyboxImitationHooks.smali" ]; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes7/io/mesalabs/unica/PlayIntegrityHooks.smali" "return" \
        'shouldBlockKeyAttestation()Z' 'true'
fi
