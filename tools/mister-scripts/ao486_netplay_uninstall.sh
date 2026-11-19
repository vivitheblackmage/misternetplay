#!/bin/bash
# MiSTer Scripts menu: takes the ao486 netplay menu off every DOS hard disk
# image in games/AO486 (the lines in AUTOEXEC.BAT, C:\NETPLAY, C:\NP.BAT and
# the backup), the same as A:\UNINSTALL on each. Later changes to AUTOEXEC.BAT
# stay. ao486_netplay_install.sh does the work.
exec bash "$(dirname "$0")/ao486_netplay_install.sh" --uninstall "$@"
