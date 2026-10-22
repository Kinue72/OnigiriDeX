#!/system/bin/sh
# Runs in KernelSU's domain. Never sources an upstream module script or deletes user config.
DATA=/data/system/onigiri-essential
ROM=/system/etc/onigiri-essential
LEGACY=/data/adb/onigiri/rootmods

log() { /system/bin/log -t onigiri-essential "$*"; }
state() { setprop "sys.onigiri.$1.state" "$2"; }
atomic() { printf '%s\n' "$2" > "$1.new" && chmod 644 "$1.new" && mv -f "$1.new" "$1" && sync; }
value() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

module_conflicts() {
    [ -d "/data/adb/modules_update/$1" ] && return 0
    [ -d "/data/adb/modules/$1" ] || return 1
    # A disabled copy cannot inject at this boot. Keep it and its uninstall-sensitive config.
    [ ! -f "/data/adb/modules/$1/disable" ] || [ -f "/data/adb/modules/$1/remove" ]
}

payload() {
    if [ -f "$DATA/$1/active" ]; then
        HASH=$(cat "$DATA/$1/active")
        [ "${#HASH}" = 64 ] || return 1
        case "$HASH" in *[!a-f0-9]*) return 1;; esac
        [ -d "$DATA/$1/releases/$HASH" ] || return 1
        CURRENT=$DATA/$1/releases/$HASH
        CODE=$(value "$CURRENT/version.properties" code)
        ROM_CODE=$(value "$ROM/$1/version.properties" code)
        case "$CODE:$ROM_CODE" in *[!0-9:]*|:*|*:) return 1;; esac
        if [ "$(value "$CURRENT/version.properties" adapter)" != "$(value "$ROM/$1/version.properties" adapter)" ] ||
                [ "$CODE" -le "$ROM_CODE" ]; then
            printf '%s\n' "$ROM/$1"
        else
            printf '%s\n' "$CURRENT"
        fi
    else
        printf '%s\n' "$ROM/$1"
    fi
}

rollback() {
    DIR=$DATA/$1
    [ -f "$DIR/trial" ] || return 0
    # A trial that has never started (for example while switched off) is not a failed boot.
    [ -f "$DIR/guard" ] || return 0
    # References are replaced atomically. A power cut at any step returns to the old payload.
    if [ -s "$DIR/previous" ]; then
        atomic "$DIR/active" "$(cat "$DIR/previous")" || return 1
    else
        rm -f "$DIR/active" || return 1
    fi
    rm -f "$DIR/pending" "$DIR/trial"
    log "$1 update rolled back after an incomplete start"
}

activate() {
    DIR=$DATA/$1
    [ -f "$DIR/pending" ] || return 0
    if [ ! -f "$DIR/trial" ]; then
        atomic "$DIR/previous" "$(cat "$DIR/active" 2>/dev/null)" &&
            touch "$DIR/trial" && sync || return 1
    fi
    atomic "$DIR/active" "$(cat "$DIR/pending")" && rm -f "$DIR/pending"
}

seed_bool() {
    [ -n "$(getprop "persist.sys.onigiri.$1")" ] || setprop "persist.sys.onigiri.$1" "$2"
    case "$(getprop "persist.sys.onigiri.$1")" in true|1) BOOL=true;; *) BOOL=false;; esac
    case "$1" in brene.*) setprop "sys.onigiri.$1" "$BOOL";; *) setprop "sys.onigiri.$1.enabled" "$BOOL";; esac
}

seed_hma() {
    for HMA_DIR in /data/misc/hide_my_applist_*; do
        [ -d "$HMA_DIR" ] && return 0
    done
    NEW=$(mktemp -d /data/misc/onigiri-hma.XXXXXXXX) || return 1
    if cp "$ROM/hma-oss.json" "$NEW/config.json" && chmod 600 "$NEW/config.json" &&
            chown -R system:system "$NEW" &&
            mv "$NEW" "/data/misc/hide_my_applist_${NEW##*.}"; then
        restorecon -RF "/data/misc/hide_my_applist_${NEW##*.}"
    else
        rm -rf "$NEW"
        return 1
    fi
}

prepare() {
    umask 022
    [ ! -L "$DATA" ] || return 1
    mkdir -p "$DATA" || return 1
    chown root:root "$DATA" || return 1
    chmod 755 "$DATA" || return 1
    DEFAULT=true
    # Preserve the old installer's opt-out and the user's existing module choices.
    if [ -d "$LEGACY" ] || [ -n "$(ls -A /data/adb/modules 2>/dev/null)" ]; then DEFAULT=false; fi
    for ID in hma tee brene; do
        [ ! -L "$DATA/$ID" ] || return 1
        mkdir -p "$DATA/$ID/releases" || return 1
        chown root:root "$DATA/$ID" "$DATA/$ID/releases" || return 1
        chmod 755 "$DATA/$ID" "$DATA/$ID/releases" || return 1
        state "$ID" unavailable
        rollback "$ID" || continue
        seed_bool "$ID" "$DEFAULT"
        if [ -f "$DATA/$ID/guard" ]; then
            # An interrupted/failed boot disables the feature until the user retries it.
            setprop "persist.sys.onigiri.$ID" false
            setprop "sys.onigiri.$ID.enabled" false
            rm -f "$DATA/$ID/guard"
            log "$ID disabled after an incomplete start"
            continue
        fi
        activate "$ID" || continue
        [ "$(getprop "sys.onigiri.$ID.enabled")" = true ] || { state "$ID" off; continue; }
        case "$ID" in hma) MOD=hma_oss_zygisk;; tee) MOD=tricky_store;; brene) MOD=brene;; esac
        if [ -e "$DATA/disable" ] || [ "$(getprop persist.sys.safemode)" = 1 ] ||
                [ "$(getprop ro.sys.safemode)" = 1 ] ||
                module_conflicts "$MOD" || { [ "$ID" = tee ] && module_conflicts teesim; }; then
            log "$ID skipped: recovery mode or an existing module"
            continue
        fi
        PAYLOAD=$(payload "$ID") || continue
        setprop "sys.onigiri.$ID.version" "$(value "$PAYLOAD/version.properties" version)"
        case "$ID" in
            hma)
                seed_hma || continue
                touch "$DATA/hma/guard" || continue
                sync
                # Updated managers are installed after PackageManager starts, before loading hooks.
                if [ "$PAYLOAD" = "$ROM/hma" ]; then state hma ready; else state hma loading; fi
                ;;
            tee) state tee ready;;
            brene) state brene ready;;
        esac
    done
    for NAME in rom_paths addon_d; do
        case "$NAME" in rom_paths) KEY=config_hide_custom_rom_paths;; addon_d) KEY=config_hide_addon_d;; esac
        BOOL=true
        if [ -f /data/adb/brene/config.sh ]; then
            OLD=$(value /data/adb/brene/config.sh "$KEY" | tr -d "\"'")
            [ "$OLD" = 1 ] || BOOL=false
        fi
        seed_bool "brene.$NAME" "$BOOL"
    done
    # Versions remain visible while off or blocked by an installed module.
    for ID in hma tee brene; do
        PAYLOAD=$(payload "$ID") || continue
        setprop "sys.onigiri.$ID.version" "$(value "$PAYLOAD/version.properties" version)"
        if [ -f "$DATA/$ID/pending" ]; then
            HASH=$(cat "$DATA/$ID/pending")
            case "$HASH" in ''|*[!a-f0-9]*) continue;; esac
            setprop "sys.onigiri.$ID.pending_version" "$(value "$DATA/$ID/releases/$HASH/version.properties" version)"
        fi
    done
    restorecon -RF "$DATA"
    setprop sys.onigiri.essential.prepared true
}

hide_path() {
    [ -e "$1" ] || [ -L "$1" ] || return 0
    "$SUSFS" add_sus_map "$1" && "$SUSFS" add_sus_path_loop "$1"
}

brene() {
    [ "$(getprop sys.onigiri.brene.state)" = ready ] || return 0
    state brene unavailable
    PAYLOAD=$(payload brene) || return 1
    SUSFS=$PAYLOAD/susfs
    "$SUSFS" show version > /dev/null || return 1
    touch "$DATA/brene/guard" || return 1
    sync
    if [ "$(getprop sys.onigiri.brene.addon_d)" = true ]; then hide_path /system/addon.d || return 1; fi
    if [ "$(getprop sys.onigiri.brene.rom_paths)" = true ]; then
        # One scan per filesystem, with the upstream list as data, not executable shell.
        set --
        while IFS= read -r NAME; do
            case "$NAME" in ''|*[!a-z]*) return 1;; esac
            [ "$#" -eq 0 ] || set -- "$@" -o
            set -- "$@" -iname "*$NAME*"
        done < "$PAYLOAD/rom-names"
        [ "$#" -gt 0 ] || return 1
        find /system /system_ext /vendor /product \( "$@" \) > "$DATA/brene/paths" || return 1
        find /data -maxdepth 1 \( "$@" \) >> "$DATA/brene/paths" || return 1
        while IFS= read -r TARGET; do hide_path "$TARGET" || return 1; done < "$DATA/brene/paths"
    fi
    state brene active
}

tee() {
    [ "$(getprop sys.onigiri.tee.state)" = ready ] || return 0
    state tee unavailable
    PAYLOAD=$(payload tee) || return 1
    mkdir -p /data/adb/tricky_store || return 1
    for NAME in keybox.xml target.txt; do
        if [ ! -e "/data/adb/tricky_store/$NAME" ]; then
            (umask 077; cp "$PAYLOAD/$NAME" "/data/adb/tricky_store/$NAME.new") &&
                mv "/data/adb/tricky_store/$NAME.new" "/data/adb/tricky_store/$NAME" || return 1
        fi
    done
    touch "$DATA/tee/guard" || return 1
    sync
    cd "$PAYLOAD" || return 1
    # v3.2 resolves inject and its library relative to cwd. No live toggle unloads keystore hooks.
    for ATTEMPT in 1 2 3; do
        SINCE=$(date '+%m-%d %H:%M:%S.000')
        /system/bin/app_process -Djava.class.path="$PAYLOAD/classes.dex" "$PAYLOAD" \
            --nice-name=TEESimulator org.matrix.TEESimulator.App &
        PID=$!
        trap 'state tee unavailable; kill "$PID" 2>/dev/null; exit' TERM INT
        COUNT=0
        while kill -0 "$PID" 2>/dev/null; do
            if logcat -b all -d -T "$SINCE" --pid="$PID" -s TEESimulator:I 2>/dev/null |
                    grep -qF 'Interceptors initialized successfully.'; then
                state tee active
                break
            fi
            COUNT=$((COUNT + 1))
            [ "$COUNT" -lt 60 ] || break
            sleep 1
        done
        if [ "$(getprop sys.onigiri.tee.state)" = active ]; then
            wait "$PID"
        else
            kill "$PID" 2>/dev/null
            wait "$PID" 2>/dev/null
        fi
        state tee unavailable
        sleep 2
    done
}

boot_complete() {
    if [ "$(getprop sys.onigiri.hma.state)" = loading ] && [ -f "$DATA/hma/active" ]; then
        PAYLOAD=$(payload hma) || return 1
        # PackageManager enforces the original manager signing identity.
        if pm install -r "$PAYLOAD/manager.apk" 2>&1 | grep -q '^Success'; then
            state hma ready
        else
            state hma unavailable
        fi
    fi
    # Require 60 consecutive active seconds after boot before accepting a trial update.
    for ID in hma tee brene; do
        (
            STABLE=0
            SECONDS_WAITED=0
            while [ "$SECONDS_WAITED" -lt 180 ]; do
                if [ "$(getprop "sys.onigiri.$ID.state")" = active ]; then STABLE=$((STABLE + 1)); else STABLE=0; fi
                if [ "$STABLE" -ge 60 ]; then
                    rm -f "$DATA/$ID/guard" "$DATA/$ID/trial"
                    break
                fi
                [ "$(getprop "sys.onigiri.$ID.enabled")" = true ] || break
                sleep 1
                SECONDS_WAITED=$((SECONDS_WAITED + 1))
            done
        ) &
    done
    wait
}

case "$1" in
    prepare) prepare;;
    brene) brene;;
    tee) tee;;
    boot-complete) boot_complete;;
    update)
        case "$2" in hma|tee|brene) ;; *) exit 2;; esac
        setprop "sys.onigiri.$2.update" checking || exit 1
        exec /system/bin/app_process -Djava.class.path=/system/framework/onigiri-essential.jar \
            /system/bin moe.foss.onigiri.EssentialUpdate "$2"
        ;;
    *) exit 2;;
esac
