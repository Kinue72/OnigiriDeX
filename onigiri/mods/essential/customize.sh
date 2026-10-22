python3 "$SRC_DIR/scripts/build_essential.py" "$SRC_DIR" "$WORK_DIR" "$TOOLS_DIR/bin/r8.jar" || return 1

# Both ROM payloads and root-owned update payloads use this type. No app can replace code
# consumed by system_server, and keystore only gets read/execute access to the native library.
cat >> "$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil" <<'CIL'
(type onigiri_essential_file)
(typeattributeset file_type (onigiri_essential_file))
(typeattributeset data_file_type (onigiri_essential_file))
(typeattributeset core_data_file_type (onigiri_essential_file))
(allow system_server onigiri_essential_file (dir (getattr open read search)))
(allow system_server onigiri_essential_file (file (getattr open read map execute)))
(allow keystore onigiri_essential_file (dir (getattr open read search)))
(allow keystore onigiri_essential_file (file (getattr open read map execute)))
(allow keystore system_data_file (dir (search)))
(allow crash_dump keystore (process (ptrace)))
CIL
cat >> "$WORK_DIR/system/system/etc/selinux/plat_file_contexts" <<'CONTEXTS'
/data/system/onigiri-essential(/.*)? u:object_r:onigiri_essential_file:s0
CONTEXTS
