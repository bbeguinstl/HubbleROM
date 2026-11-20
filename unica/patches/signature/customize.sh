CERT_PREFIX="aosp"
$ROM_IS_OFFICIAL && CERT_PREFIX="unica"

if [ ! -f "$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem" ]; then
    ABORT "File not found: security/${CERT_PREFIX}_platform.x509.pem"
fi

DECODE_APK "system" "system/framework/services.jar"
INSTALL_PACKAGE_HELPER="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/InstallPackageHelper.smali"
if grep -Fq '.field public final mCustomPlatformSignatures:[Landroid/content/pm/Signature;' \
        "$INSTALL_PACKAGE_HELPER"; then
    LOG "- Custom platform signature support is already installed"
else
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/services.jar/0001-Allow-custom-platform-signature.patch"
fi

CERT_SIGNATURE="$(sed "/CERTIFICATE/d" "$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem" | tr -d "\n" | base64 -d | xxd -p -c 0)"
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/pm/InstallPackageHelper.smali" "replace" \
    '<init>(Lcom/android/server/pm/PackageManagerService;Lcom/android/server/pm/AppDataHelper;Lcom/android/server/pm/RemovePackageHelper;Lcom/android/server/pm/DeletePackageHelper;Lcom/android/server/pm/BroadcastHelper;)V' \
    'CONFIG_CUSTOM_PLATFORM_SIGNATURE' \
    "$CERT_SIGNATURE" \
    > /dev/null

unset CERT_PREFIX CERT_SIGNATURE INSTALL_PACKAGE_HELPER
