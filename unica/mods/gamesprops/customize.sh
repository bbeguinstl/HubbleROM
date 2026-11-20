FRAMEWORK_APK="$APKTOOL_DIR/system/framework/framework.jar"
INSTRUMENTATION_SMALI="$(find "$FRAMEWORK_APK" -type f -path '*/android/app/Instrumentation.smali' -printf '%P\n' -quit)"
if ! grep -q -F 'GamesPropsUtils;->setProps(Landroid/content/Context;)V' "$FRAMEWORK_APK/$INSTRUMENTATION_SMALI"; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p1}, Lio/mesalabs/unica/GamesPropsUtils;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "$INSTRUMENTATION_SMALI" "replace" \
        'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
        'return-object p0' \
        '    invoke-static {p3}, Lio/mesalabs/unica/GamesPropsUtils;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
        > /dev/null
fi
unset FRAMEWORK_APK INSTRUMENTATION_SMALI
