if grep -q '^CONFIG_SECURITY_PROCA=y$' "$OUT_DIR/target/b5q/kernel/gki.config"; then
    ABORT "The Onigiri kernel must disable PROCA at build time."
fi
