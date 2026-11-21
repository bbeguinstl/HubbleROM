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
    local source_cpio="$TMP_DIR/ramdisk-source.cpio"
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
            RAMDISK_FS_CONFIG="$TMP_DIR/ramdisk-fs-config"
            : > "$RAMDISK_NODES_FILE" || return 1
            : > "$RAMDISK_FS_CONFIG" || return 1
            if [[ "$format" == "gz" ]]; then
                gzip -dc "$archive" > "$source_cpio" || return 1
            else
                lz4 -d "$archive" -c > "$source_cpio" || return 1
            fi
            python3 - "$destination" "$source_cpio" "$errors" \
                "$RAMDISK_NODES_FILE" "$RAMDISK_FS_CONFIG" <<'PY'
import re
import stat
import sys
from pathlib import Path

root, source_cpio, errors_file, nodes_file, config_file = map(Path, sys.argv[1:])
expected = {"dev/null", "dev/console", "dev/urandom", "dev/kmsg"}
missing = set()
for line in errors_file.read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(
        r"cpio: (?:\./)?(dev/(?:null|console|urandom|kmsg)): Cannot mknod: Operation not permitted",
        line,
    )
    if not match:
        raise SystemExit(f"Unexpected cpio extraction error: {line}")
    missing.add(match.group(1))
if not missing:
    raise SystemExit("cpio failed without identifying an expected device node")

archive = source_cpio.read_bytes()
offset = 0
nodes = {}
while offset + 110 <= len(archive):
    header = archive[offset : offset + 110]
    if header[:6] not in (b"070701", b"070702"):
        raise SystemExit(f"Invalid newc CPIO header at offset {offset}")
    fields = [int(header[i : i + 8], 16) for i in range(6, 110, 8)]
    mode, uid, gid, size, rdevmajor, rdevminor, namesize = (
        fields[1], fields[2], fields[3], fields[6], fields[9], fields[10], fields[11]
    )
    offset += 110
    name = archive[offset : offset + namesize - 1].decode("utf-8", "strict")
    offset = (offset + namesize + 3) & ~3
    if name == "TRAILER!!!":
        break
    while name.startswith("./"):
        name = name[2:]
    if name in expected:
        if size != 0 or not (stat.S_ISCHR(mode) or stat.S_ISBLK(mode)):
            raise SystemExit(f"Expected a device node in source CPIO: {name}")
        nodes[name] = (
            stat.S_IMODE(mode),
            uid,
            gid,
            "c" if stat.S_ISCHR(mode) else "b",
            rdevmajor,
            rdevminor,
        )
    offset = (offset + size + 3) & ~3

entries = {}
dev_dir = root / "dev"
if not dev_dir.is_dir():
    raise SystemExit("Source ramdisk device nodes have no dev/ parent directory")
dev_metadata = dev_dir.lstat()
if not stat.S_ISDIR(dev_metadata.st_mode):
    raise SystemExit("Source ramdisk dev/ parent is not a directory")
node_lines = [
    f"dir dev {stat.S_IMODE(dev_metadata.st_mode):04o} "
    f"{dev_metadata.st_uid} {dev_metadata.st_gid}"
]
for name in sorted(missing):
    if name not in nodes:
        raise SystemExit(f"Could not find original device-node metadata: {name}")
    mode, uid, gid, kind, major, minor = nodes[name]
    node_lines.append(
        f"nod {name} {mode:04o} {uid} {gid} {kind} {major} {minor}"
    )
    entries[name] = (uid, gid, mode)

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
nodes_file.write_text("\n".join(node_lines) + "\n", encoding="utf-8")
config_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
            [[ -s "$RAMDISK_NODES_FILE" && -s "$RAMDISK_FS_CONFIG" ]] || return 1
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
