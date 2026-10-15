#!/usr/bin/env bash


source "$SRC_DIR/scripts/utils/log_utils.sh"

PRINT_MODULE_INFO()
{
    local MODPATH="$1"
    local MODNAME
    local MODAUTH
    local MODDESC

    if [ ! -d "$MODPATH" ]; then
        LOGE "Folder not found: $MODPATH"
        exit 1
    fi

    if [ -d "$MODPATH/$TARGET_SINGLE_SYSTEM_IMAGE" ]; then
        MODPATH="$MODPATH/$TARGET_SINGLE_SYSTEM_IMAGE"
    fi

    if [ ! -f "$MODPATH/module.prop" ]; then
        LOGE "File not found: $MODPATH/module.prop"
        exit 1
    elif [ -f "$MODPATH/disable" ]; then
        return 0
    else
        MODNAME="$(grep "^name" "$MODPATH/module.prop" | sed "s/name=//")"
        MODAUTH="$(grep "^author" "$MODPATH/module.prop" | sed "s/author=//")"
        MODDESC="$(grep "^description" "$MODPATH/module.prop" | sed "s/description=//")"
    fi

    LOG "-- Module $MODULES_COUNT:"
    LOG "Name: $MODNAME"
    LOG "Author(s): $MODAUTH"
    LOG "Description: $MODDESC"
}

if [ "$#" -gt 0 ]; then
    echo "Usage: print_modules_info" >&2
    echo "This script does not accept any arguments." >&2
    exit 1
fi

MODULES_COUNT=0

while read -r i; do
    ((MODULES_COUNT+=1))
    PRINT_MODULE_INFO "$i"
done <<< "$(find "$SRC_DIR/onigiri/patches" -mindepth 1 -maxdepth 1 -type d)"

while read -r i; do
    ((MODULES_COUNT+=1))
    PRINT_MODULE_INFO "$i"
done <<< "$(find "$SRC_DIR/onigiri/mods" -mindepth 1 -maxdepth 1 -type d)"

while read -r i; do
    ((MODULES_COUNT+=1))
    PRINT_MODULE_INFO "$i"
done <<< "$(find "$SRC_DIR/target/$TARGET_CODENAME/patches" -mindepth 1 -maxdepth 1 -type d)"

exit 0
