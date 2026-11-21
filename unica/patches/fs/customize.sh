# [
PARTITIONS_LIST="system vendor product system_ext odm vendor_dlkm odm_dlkm system_dlkm"

# The target firmware's vendor fstab is the canonical source for the logical
# partition entries.  The copy inside boot.img is only a ramdisk copy of this
# file and must be validated after repacking; otherwise a stale stock boot
# image can silently retain ext4 while the generated images are EROFS.
CANONICAL_FSTAB=""

GET_CANONICAL_FSTAB()
{
    local candidate

    for candidate in "$WORK_DIR/vendor/etc/fstab.exynos9611" \
        "$WORK_DIR/vendor/etc/fstab."*; do
        if [ -f "$candidate" ]; then
            CANONICAL_FSTAB="$candidate"
            return 0
        fi
    done

    ABORT "No target vendor fstab was found under ${WORK_DIR//$SRC_DIR\//}/vendor/etc"
    return 1
}

VALIDATE_FSTAB_TYPE()
{
    local root="$1"
    local file line partition fs_type

    while IFS= read -r file; do
        while IFS=$'\t ' read -r partition _ fs_type _; do
            [ -n "$partition" ] || continue
            case "$partition" in
                system|vendor|product|system_ext|odm|vendor_dlkm|odm_dlkm|system_dlkm)
                    [ "$fs_type" = "$TARGET_OS_FILE_SYSTEM_TYPE" ] || {
                        ABORT "fstab $(sed -e "s|$WORK_DIR||g" -e "s|$TMP_DIR/out/ramdisk_extracted|$BOOT_FILE|g" <<< "$file") keeps $partition as $fs_type (expected $TARGET_OS_FILE_SYSTEM_TYPE)"
                        return 1
                    }
                    ;;
            esac
        done < <(sed -E 's/[[:space:]]+#.*$//' "$file")
    done < <(find "$root" -type f -name 'fstab.*' | LC_ALL=C sort)
}

PATCH_FSTAB()
{
    local f

    while IFS= read -r f; do
        if [[ "$f" == *"emmc" ]] || [[ "$f" == *"ramplus" ]]; then
            continue
        fi
        if sed -E -i \
            -e "/^[^[:space:]]+[[:space:]]+\/(${PARTITIONS_LIST// /|})[[:space:]]+/ s/^([^[:space:]]+[[:space:]]+[^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+/\1\t$TARGET_OS_FILE_SYSTEM_TYPE\t/" \
            -e "/^[^[:space:]]+[[:space:]]+\/(${PARTITIONS_LIST// /|})[[:space:]]+/ s/^([^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+/\1\tro\t/" \
            "$f"; then
            LOG "- Patching $(sed -e "s|$WORK_DIR||g" -e "s|$TMP_DIR/out/ramdisk_extracted|$BOOT_FILE|g" <<< "$f")"
        fi
        EVAL "uniq \"$f\" \"$TMP_DIR/tmp\" && mv -f \"$TMP_DIR/tmp\" \"$f\""
    done < <(find "$1" -type f -name "fstab.*")
}

EXTRACT_RAMDISK_CPIO()
{
    local archive="$1"
    local format="$2"
    local destination="$3"
    local errors="$TMP_DIR/cpio-extract.errors"
    local node_path
    local config_path
    local had_errexit=0
    local -a pipe_status=()

    RAMDISK_NODES_FILE=""
    RAMDISK_FS_CONFIG=""
    [[ "$-" == *e* ]] && had_errexit=1
    : > "$errors" || return 1
    set +e
    if [[ "$format" == "gz" ]]; then
        gzip -dc "$archive" | cpio --quiet -i -D "$destination" 2> "$errors"
    elif [[ "$format" == "lz4" ]]; then
        lz4 -d "$archive" -c | cpio --quiet -i -D "$destination" 2> "$errors"
    else
        [[ "$had_errexit" == 1 ]] && set -e
        return 1
    fi
    pipe_status=( "${PIPESTATUS[@]}" )
    [[ "$had_errexit" == 1 ]] && set -e

    if [[ "${pipe_status[0]:-1}" != 0 ]]; then
        cat "$errors" >&2
        return 1
    fi
    if [[ "${pipe_status[1]:-1}" != 0 ]]; then
        if [[ -s "$errors" ]] && ! grep -vE \
            '^cpio: (\./)?dev/(null|console|urandom|kmsg): Cannot mknod: Operation not permitted$' \
            "$errors"; then
            RAMDISK_NODES_FILE="$TMP_DIR/ramdisk-nodes"
            : > "$RAMDISK_NODES_FILE" || return 1
            while IFS= read -r node_path; do
                case "${node_path#./}" in
                    dev/null)
                        printf 'nod dev/null 0666 0 0 c 1 3\n' >> "$RAMDISK_NODES_FILE"
                        ;;
                    dev/console)
                        printf 'nod dev/console 0600 0 0 c 5 1\n' >> "$RAMDISK_NODES_FILE"
                        ;;
                    dev/urandom)
                        printf 'nod dev/urandom 0666 0 0 c 1 9\n' >> "$RAMDISK_NODES_FILE"
                        ;;
                    dev/kmsg)
                        printf 'nod dev/kmsg 0600 0 0 c 1 11\n' >> "$RAMDISK_NODES_FILE"
                        ;;
                esac
            done < <(sed -nE \
                's/^cpio: (\.\/)?(dev\/(null|console|urandom|kmsg)): Cannot mknod: Operation not permitted$/\2/p' \
                "$errors")
            [[ -s "$RAMDISK_NODES_FILE" ]] || {
                cat "$errors" >&2
                return 1
            }
            RAMDISK_FS_CONFIG="$TMP_DIR/ramdisk-fs-config"
            python3 - "$destination" "$RAMDISK_NODES_FILE" "$RAMDISK_FS_CONFIG" <<'PY'
import os
import stat
import sys
from pathlib import Path

root, nodes_file, output = map(Path, sys.argv[1:])
entries = {}
for line in nodes_file.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if len(fields) != 8 or fields[0] != "nod":
        raise SystemExit(f"Invalid mkbootfs node entry: {line}")
    _, path, mode, uid, gid, *_ = fields
    entries[path] = (int(uid), int(gid), int(mode, 8))

for path in root.rglob("*"):
    name = path.relative_to(root).as_posix()
    if any(char.isspace() for char in name):
        raise SystemExit(f"Whitespace in ramdisk path cannot be represented: {name!r}")
    metadata = path.lstat()
    entries[name] = (
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IMODE(metadata.st_mode),
    )

lines = [
    f"{name} {uid} {gid} {mode:04o}"
    for name, (uid, gid, mode) in sorted(entries.items())
]
lines.append(" 0 0 0755")
output.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
            [[ -s "$RAMDISK_FS_CONFIG" ]] || return 1
            LOGW "Preserving ramdisk device nodes through mkbootfs"
        else
            cat "$errors" >&2
            return 1
        fi
    fi
    return 0
}
# ]

BOOT_FILE="boot.img"
if [ -f "$WORK_DIR/kernel/vendor_boot.img" ]; then
    BOOT_FILE="vendor_boot.img"
fi

GET_CANONICAL_FSTAB || return 1
if [ ! -f "$WORK_DIR/kernel/$BOOT_FILE" ]; then
    ABORT "File not found: ${WORK_DIR//$SRC_DIR\//}/kernel/$BOOT_FILE"
fi

LOG "- Extracting $BOOT_FILE"

if [ -d "$TMP_DIR" ]; then
    EVAL "rm -rf \"$TMP_DIR\""
fi
EVAL "mkdir -p \"$TMP_DIR\""
EVAL "cp -a \"$WORK_DIR/kernel/$BOOT_FILE\" \"$TMP_DIR/$BOOT_FILE\""

MKBOOTIMG_ARGS="$(unpack_bootimg --boot_img "$TMP_DIR/$BOOT_FILE" --out "$TMP_DIR/out" --format mkbootimg 2>&1)"

while IFS= read -r f; do
    LOG "- Extracting $BOOT_FILE/$(basename "$f")"

    RAMDISK_FORMAT=""
    if [[ "$(READ_BYTES_AT "$f" "0" "2")" == "8b1f" ]]; then
        RAMDISK_FORMAT="gz"
    fi
    if [[ "$(READ_BYTES_AT "$f" "0" "4")" == "184c2102" ]]; then
        RAMDISK_FORMAT="lz4"
    fi
    if [ ! "$RAMDISK_FORMAT" ]; then
        ABORT "Ramdisk format not valid\n\n$(LC_ALL=C file -b "$f")"
    fi

    EVAL "mkdir -p \"$TMP_DIR/out/ramdisk_extracted\""
    EXTRACT_RAMDISK_CPIO "$f" "$RAMDISK_FORMAT" \
        "$TMP_DIR/out/ramdisk_extracted" || return 1

    PATCH_FSTAB "$TMP_DIR/out/ramdisk_extracted"

    LOG "- Repacking $BOOT_FILE/$(basename "$f")"

    if [[ "$RAMDISK_FORMAT" == "gz" ]]; then
        if [[ -n "$RAMDISK_NODES_FILE" ]]; then
            EVAL "mkbootfs -f \"$RAMDISK_FS_CONFIG\" -n \"$RAMDISK_NODES_FILE\" \"$TMP_DIR/out/ramdisk_extracted\" | gzip > \"$f\""
        else
            EVAL "mkbootfs \"$TMP_DIR/out/ramdisk_extracted\" | gzip > \"$f\""
        fi
    elif [[ "$RAMDISK_FORMAT" == "lz4" ]]; then
        if [[ -n "$RAMDISK_NODES_FILE" ]]; then
            EVAL "mkbootfs -f \"$RAMDISK_FS_CONFIG\" -n \"$RAMDISK_NODES_FILE\" \"$TMP_DIR/out/ramdisk_extracted\" | lz4 -l -12 --favor-decSpeed > \"$f\""
        else
            EVAL "mkbootfs \"$TMP_DIR/out/ramdisk_extracted\" | lz4 -l -12 --favor-decSpeed > \"$f\""
        fi
    fi

    EVAL "rm -rf \"$TMP_DIR/out/ramdisk_extracted\""
done < <(find "$TMP_DIR/out" -type f -name "*ramdisk*" | LC_ALL=C sort)

PATCH_FSTAB "$WORK_DIR/vendor/etc"

# Confirm both the patched vendor copy and the ramdisk copy agree before the
# image is rebuilt.  This prevents packaging a logical EROFS image with the
# original ext4 fstab from the target firmware.
VALIDATE_FSTAB_TYPE "$WORK_DIR/vendor/etc" || return 1

LOG "- Repacking $BOOT_FILE"

if [[ "$BOOT_FILE" == "vendor_boot.img" ]]; then
    EVAL "mkbootimg $MKBOOTIMG_ARGS --vendor_boot \"$WORK_DIR/kernel/vendor_boot.img\""
else
    EVAL "mkbootimg $MKBOOTIMG_ARGS -o \"$TMP_DIR/new-boot.img\""
    echo -n "SEANDROIDENFORCE" >> "$TMP_DIR/new-boot.img"
    EVAL "mv -f \"$TMP_DIR/new-boot.img\" \"$WORK_DIR/kernel/boot.img\""
fi

# Re-open the generated boot image and validate the copy that Android's
# first-stage init actually consumes.  A later kernel/packaging step must not
# be allowed to replace it with the untouched target boot image.
VERIFY_DIR="$TMP_DIR/verify"
EVAL "mkdir -p \"$VERIFY_DIR\""
EVAL "unpack_bootimg --boot_img \"$WORK_DIR/kernel/$BOOT_FILE\" --out \"$VERIFY_DIR\" >/dev/null"
VERIFY_RAMDISK="$VERIFY_DIR/ramdisk"
VERIFY_FORMAT=""
if [[ "$(READ_BYTES_AT "$VERIFY_RAMDISK" "0" "2")" == "8b1f" ]]; then
    VERIFY_FORMAT="gz"
elif [[ "$(READ_BYTES_AT "$VERIFY_RAMDISK" "0" "4")" == "184c2102" ]]; then
    VERIFY_FORMAT="lz4"
fi
[ -n "$VERIFY_FORMAT" ] || ABORT "Repacked $BOOT_FILE has an unsupported ramdisk format"
EVAL "mkdir -p \"$VERIFY_DIR/ramdisk_extracted\""
EXTRACT_RAMDISK_CPIO "$VERIFY_RAMDISK" "$VERIFY_FORMAT" \
    "$VERIFY_DIR/ramdisk_extracted" || return 1
VALIDATE_FSTAB_TYPE "$VERIFY_DIR/ramdisk_extracted" || return 1
LOG "- Verified $BOOT_FILE fstab uses $TARGET_OS_FILE_SYSTEM_TYPE for all logical partitions"

EVAL "rm -rf \"$TMP_DIR\""

unset PARTITIONS_LIST CANONICAL_FSTAB BOOT_FILE MKBOOTIMG_ARGS RAMDISK_FILE RAMDISK_FORMAT RAMDISK_NODES_FILE RAMDISK_FS_CONFIG VERIFY_DIR VERIFY_RAMDISK VERIFY_FORMAT
unset -f PATCH_FSTAB
unset -f GET_CANONICAL_FSTAB VALIDATE_FSTAB_TYPE
unset -f EXTRACT_RAMDISK_CPIO
