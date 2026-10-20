#!/system/bin/sh
# A full CSC flash leaves "--data_resizing" in /cache/recovery/command. Stock recovery can't mount
# the encrypted /data to resize it, so it only deletes the metadata encryption key, and Android then
# stops at "Can't load Android system" (fs_mgr_mount_all:M02R). Stock avoids this with a fresh
# userdata.img in its AP; Onigiri's AP has none, so an AP-only flash keeps data. Do the factory
# reset the CSC flash is meant to be instead.
COMMAND=/cache/recovery/command

mount -t ext4 -o nosuid,nodev /dev/block/bootdevice/by-name/cache /cache || exit 0
grep -qx -- --data_resizing "$COMMAND" && echo --wipe_data > "$COMMAND"
umount /cache
