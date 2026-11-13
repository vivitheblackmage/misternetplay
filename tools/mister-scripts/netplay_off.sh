#!/bin/bash
# MiSTer Scripts menu: switch back to your normal Main_MiSTer binary and reboot.
cd /media/fat || exit 1
# a netplay binary has netplay.ini in it; the normal MiSTer binary does not
if ! grep -q -F netplay.ini MiSTer; then
	echo "Netplay binary is not active, nothing to do."
	exit 0
fi
[ -f MiSTer_offline ] || { echo "No /media/fat/MiSTer_offline to go back to."; exit 1; }
if grep -q -F netplay.ini MiSTer_offline; then
	echo "MiSTer_offline is a netplay binary too (an older netplay_on saved it)."
	echo "Run update_all or downloader to get the normal MiSTer binary back."
	exit 1
fi
cp MiSTer_offline MiSTer.new && chmod +x MiSTer.new && mv MiSTer.new MiSTer || exit 1
echo "Netplay OFF. Rebooting..."
sync; sleep 2; reboot
