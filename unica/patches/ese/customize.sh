# SEC_PRODUCT_FEATURE_SECURITY_CONFIG_ESE_CHIP_VENDOR
# SEC_PRODUCT_FEATURE_SECURITY_CONFIG_ESE_COS_NAME
if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" == "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" ]] && \
    [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" == "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    return 0
fi

# [
LOG_MISSING_PATCHES()
{
    local MESSAGE="Missing SPF patches for condition ($1: [${!1}], $2: [${!2}])"

    if $DEBUG; then
        LOGW "$MESSAGE"
    else
        ABORT "${MESSAGE}. Aborting"
    fi
}

REPLACEALL_SMALI_IF_NEEDED()
{
    local PARTITION="$1"
    local APK="$2"
    local SMALI="$3"
    local FROM="$4"
    local TO="$5"
    local SMALI_FILE="$APKTOOL_DIR/$PARTITION/${APK//system/}/$SMALI"

    DECODE_APK "$PARTITION" "$APK"
    if grep -Fq -- "$FROM" "$SMALI_FILE"; then
        SMALI_PATCH "$PARTITION" "$APK" "$SMALI" "replaceall" "$FROM" "$TO"
    elif [ -n "$TO" ] && grep -Fq -- "$TO" "$SMALI_FILE"; then
        LOG "- $SMALI already uses the target value; skipping"
    elif [ -z "$TO" ]; then
        LOG "- $SMALI no longer contains the source value; skipping"
    else
        ABORT "Unable to find either source or target value in $SMALI"
    fi
}
# ]

if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" == "NXP" ]] && [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" == "JCOP6.2U" ]] && \
        [[ "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" == "none" ]] && [[ "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" == "none" ]]; then
    APPLY_PATCH "system" "system/app/SecureElement/SecureElement.apk" \
        "$MODPATH/ese/SecureElement.apk/0001-Disable-eSE-support.patch"
    DELETE_FROM_WORK_DIR "system" "system/bin/sem_daemon"
    DELETE_FROM_WORK_DIR "system" "system/etc/init/sem.rc" 2>&1 | sed "/File not found/d"
    DELETE_FROM_WORK_DIR "system" "system/etc/init/sem_early.rc" 2>&1 | sed "/File not found/d"
    DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.ese.xml"
    DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.sem.factoryapp.xml"
    APPLY_PATCH "system" "system/framework/framework.jar" "$MODPATH/ese/framework.jar/0001-Disable-SemService.patch"
    EVAL "cp -a \"$MODPATH/framework.jar/SemService.smali\" \"$APKTOOL_DIR/system/framework/framework.jar/smali_classes6/com/android/server/SemService.smali\""
    APPLY_PATCH "system" "system/framework/services.jar" "$MODPATH/ese/services.jar/0001-Disable-SemService.patch"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib/libsec_semRil.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib/libtlc_blockchain_keystore.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib/libtlc_payment_spay.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib64/libsec_semRil.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib64/libtlc_blockchain_keystore.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "a73xqxx" || echo "a54xnsxx")" \
        "system" "system/lib64/libtlc_payment_spay.so" 0 0 644 "u:object_r:system_lib_file:s0"
    DELETE_FROM_WORK_DIR "system" "system/priv-app/SEMFactoryApp"
    DELETE_FROM_WORK_DIR "system" "system/priv-app/SamsungSeAgent"
elif [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" != "none" ]] && [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "none" ]]; then
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
        SMALI_PATCH "system" "system/app/SecureElement/SecureElement.apk" \
            "smali/com/android/se/internal/UtilExtension.smali" "replace" \
            "<clinit>()V" \
            "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" \
            "${TARGET_SECURITY_CONFIG_ESE_COS_NAME//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
        SMALI_PATCH "system" "system/app/SecureElement/SecureElement.apk" \
            "smali/com/android/se/internal/UtilExtension.smali" "replace" \
            "supportEse(Landroid/content/Context;)Z" \
            "eSE_COS: $SOURCE_SECURITY_CONFIG_ESE_COS_NAME" \
            "eSE_COS: ${TARGET_SECURITY_CONFIG_ESE_COS_NAME//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" != "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" ]]; then
        SMALI_PATCH "system" "system/app/SecureElement/SecureElement.apk" \
            "smali/com/android/se/internal/UtilExtension.smali" "replace" \
            "supportEse(Landroid/content/Context;)Z" \
            "eSE_Vendor: $SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" \
            "eSE_Vendor: ${TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
        SMALI_PATCH "system" "system/app/SecureElement/SecureElement.apk" \
            "smali/com/android/se/internal/UtilExtension.smali" "replace" \
            "supportEseHal()Z" \
            ", eSE_COS: $SOURCE_SECURITY_CONFIG_ESE_COS_NAME" \
            ", eSE_COS: ${TARGET_SECURITY_CONFIG_ESE_COS_NAME//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" != "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" ]]; then
        REPLACEALL_SMALI_IF_NEEDED "system" "system/framework/framework.jar" \
            "smali_classes6/com/android/server/SemService.smali" \
            "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" \
            "${TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
        REPLACEALL_SMALI_IF_NEEDED "system" "system/framework/framework.jar" \
            "smali_classes6/com/android/server/SemService.smali" \
            "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" \
            "${TARGET_SECURITY_CONFIG_ESE_COS_NAME//none/}"
    fi
    SEM_SERVICE_MANAGER_SMALI="smali_classes6/com/samsung/android/service/SemService/SemServiceManager.smali"
    if [ ! -f "$APKTOOL_DIR/system/framework/framework.jar/$SEM_SERVICE_MANAGER_SMALI" ]; then
        SEM_SERVICE_MANAGER_MATCHES="$(find "$APKTOOL_DIR/system/framework/framework.jar" -path \
            '*/com/samsung/android/service/SemService/SemServiceManager.smali' -type f | sort)"
        if [ "$(printf '%s\n' "$SEM_SERVICE_MANAGER_MATCHES" | sed '/^$/d' | wc -l)" -ne 1 ]; then
            ABORT "Unable to uniquely locate SemServiceManager in framework.jar"
        fi
        SEM_SERVICE_MANAGER_SMALI="${SEM_SERVICE_MANAGER_MATCHES#"$APKTOOL_DIR/system/framework/framework.jar/"}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" != "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" ]]; then
        REPLACEALL_SMALI_IF_NEEDED "system" "system/framework/framework.jar" \
            "$SEM_SERVICE_MANAGER_SMALI" \
            "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" \
            "${TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" != "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" ]]; then
        REPLACEALL_SMALI_IF_NEEDED "system" "system/framework/framework.jar" \
            "$SEM_SERVICE_MANAGER_SMALI" \
            "$SOURCE_SECURITY_CONFIG_ESE_COS_NAME" \
            "${TARGET_SECURITY_CONFIG_ESE_COS_NAME//none/}"
    fi
    if [[ "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" != "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" ]]; then
        CREDENTIAL_MANAGER_SERVICE_SMALI="smali_classes2/com/samsung/ucm/ucmservice/CredentialManagerService.smali"
        if [ ! -f "$APKTOOL_DIR/system/framework/services.jar/$CREDENTIAL_MANAGER_SERVICE_SMALI" ]; then
            CREDENTIAL_MANAGER_SERVICE_MATCHES="$(find "$APKTOOL_DIR/system/framework/services.jar" -path \
                '*/com/samsung/ucm/ucmservice/CredentialManagerService.smali' -type f | sort)"
            if [ "$(printf '%s\n' "$CREDENTIAL_MANAGER_SERVICE_MATCHES" | sed '/^$/d' | wc -l)" -ne 1 ]; then
                ABORT "Unable to uniquely locate Samsung CredentialManagerService in services.jar"
            fi
            CREDENTIAL_MANAGER_SERVICE_SMALI="${CREDENTIAL_MANAGER_SERVICE_MATCHES#"$APKTOOL_DIR/system/framework/services.jar/"}"
        fi
        REPLACEALL_SMALI_IF_NEEDED "system" "system/framework/services.jar" \
            "$CREDENTIAL_MANAGER_SERVICE_SMALI" \
            "$SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" \
            "${TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR//none/}"
    fi
else
    LOG_MISSING_PATCHES "SOURCE_SECURITY_CONFIG_ESE_CHIP_VENDOR" "TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" || true
    LOG_MISSING_PATCHES "SOURCE_SECURITY_CONFIG_ESE_COS_NAME" "TARGET_SECURITY_CONFIG_ESE_COS_NAME"
fi

unset -f LOG_MISSING_PATCHES
unset -f REPLACEALL_SMALI_IF_NEEDED
unset SEM_SERVICE_MANAGER_SMALI SEM_SERVICE_MANAGER_MATCHES \
    CREDENTIAL_MANAGER_SERVICE_SMALI CREDENTIAL_MANAGER_SERVICE_MATCHES
