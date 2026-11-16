# One at a time: every deletion rewrites the same fs_config and file_context files, so parallel
# ones lose each other's edits and leave entries behind for files that are gone.

# Dexpreopt
for PARTITION in product system system_ext; do
    while IFS= read -r FILE; do
        DELETE_FROM_WORK_DIR "$PARTITION" "${FILE#"$WORK_DIR/$PARTITION/"}"
    done < <(find "$WORK_DIR/$PARTITION" -type d -name "oat" -prune | sort)
done
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.bprof"
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.prof"
DELETE_FROM_WORK_DIR "system" "system/framework/arm"
DELETE_FROM_WORK_DIR "system" "system/framework/arm64"
while IFS= read -r FILE; do
    DELETE_FROM_WORK_DIR "system" "${FILE#"$WORK_DIR/system/"}"
done < <(find "$WORK_DIR/system/system/framework" -type f -name "*.vdex" | sort)

# Debloat list
source "$SRC_DIR/onigiri/debloat.sh"

for PARTITION in odm product system system_ext vendor; do
    LIST="${PARTITION^^}_DEBLOAT"
    while IFS= read -r FILE; do
        [ -z "$FILE" ] || DELETE_FROM_WORK_DIR "$PARTITION" "$FILE"
    done < <(sort <<< "${!LIST}")
done
