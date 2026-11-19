#!/usr/bin/env python3
"""T3e-i: ao486_netplay_install.sh / _uninstall.sh on disk images (SPEC.md 15.5).

Runs as root in a privileged container (loop mounts, as on the MiSTer), with
mtools and dosfstools:

    test_ao486_install.py <scripts dir> <NETPLAY.IMG> <dos disk image> <out>

It builds a games/AO486 folder in <out>: NETPLAY.IMG, a copy of the DOS disk
(partitioned, a game start in AUTOEXEC.BAT), a Windows 95 disk, a FAT disk
without DOS, a DOS disk without a partition table and without AUTOEXEC.BAT,
and a CD image. Then:
  1. --dry-run changes nothing
  2. install: the DOS disks get C:\\NETPLAY (the floppy's files), NP.BAT, the
     hook before the game start and :NPEND last, the backup; the others not
  3. install again: AUTOEXEC.BAT the same, "updated"
  4. uninstall: AUTOEXEC.BAT byte for byte the old one (the disk without one
     keeps the minimal one), C:\\NETPLAY, NP.BAT and the backup gone
  5. a line added after the install stays through the uninstall
  6. the script refuses while the ao486 core runs (/tmp/CORENAME)
  7. shortcuts: the menu's MGL files that start the ao486 core with a disk
     that got the menu are copied to _Netplay/_DOS Games with the core
     _Netplay/ao486_netplay; not for the Windows disk, not other cores' MGLs,
     a file of the user's there is left alone, the originals are unchanged;
     the uninstall removes only ours
"""
import os, shutil, subprocess, sys

scripts, floppy, dos_src, out = sys.argv[1:5]
failures = []


def check(cond, what):
    print(("PASS " if cond else "FAIL ") + what, flush=True)
    if not cond:
        failures.append(what)


ENV = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")


def part(img):
    with open(img, "rb") as f:
        s = f.read(512)
    if s[0x36:0x39] == b"FAT" or s[0x52:0x55] == b"FAT":
        return img
    return "%s@@%d" % (img, int.from_bytes(s[454:458], "little") * 512)


def mt(*a, img):
    return subprocess.run([a[0], "-i", part(img)] + list(a[1:]), env=ENV, capture_output=True)


def get(img, path):
    r = mt("mtype", "::" + path, img=img)
    return r.stdout if r.returncode == 0 else None


def put(img, path, data):
    tmp = os.path.join(out, "put.tmp")
    with open(tmp, "wb") as f:
        f.write(data)
    mt("mcopy", "-o", tmp, "::" + path, img=img)


def exists(img, path):
    return mt("mdir", "::" + path, img=img).returncode == 0


def mkfat(img, mb, partitioned):
    with open(img, "wb") as f:
        f.truncate(mb << 20)
    if partitioned:
        subprocess.run(["sfdisk", "-q", img], input="2048,,6\n", text=True, check=True)
        subprocess.run(["mkfs.vfat", "-F", "16", "--offset", "2048", img, str((mb << 10) - 1024)],
                       check=True, capture_output=True)
    else:
        subprocess.run(["mkfs.vfat", "-F", "16", img], check=True, capture_output=True)


def run(*extra):
    r = subprocess.run(["bash", os.path.join(scripts, "ao486_netplay_install.sh")] + list(extra) + ["--menu-root", fat, games],
                       capture_output=True, text=True)
    print(r.stdout + r.stderr, flush=True)
    return r


shutil.rmtree(out, ignore_errors=True)
fat = os.path.join(out, "fat")
games = os.path.join(out, "games", "AO486")
for d in ("_DOS Games", "_Netplay/_DOS Games", "_Console"):
    os.makedirs(os.path.join(fat, d))
open(os.path.join(fat, "_Netplay", "ao486_netplay_20261117.rbf"), "wb").write(b"rbf")
MGL = '<mistergamedescription>\n    <rbf>%s</rbf>\n    <file delay="0" type="s" index="2" path="%s"/>\n    <reset delay="1"/>\n</mistergamedescription>\n'
mgl_doom = MGL % ("_computer/ao486", "media/doom/doom.vhd")
for name, text in (("Doom.mgl", mgl_doom), ("Win.mgl", MGL % ("_computer/ao486", "media/win95/win95.vhd")),
                   ("Mario.mgl", MGL % ("_Console/SNES", "media/doom/doom.vhd"))):
    open(os.path.join(fat, "_DOS Games", name), "w").write(text)
mine = os.path.join(fat, "_Netplay", "_DOS Games", "Mine.mgl")
open(mine, "w").write(MGL % ("_computer/ao486", "media/plain/plain.vhd"))
media = os.path.join(games, "media")
for d in ("doom", "win95", "nodos", "plain", "cd"):
    os.makedirs(os.path.join(media, d))
shutil.copyfile(floppy, os.path.join(games, "NETPLAY.IMG"))
doom = os.path.join(media, "doom", "doom.vhd")
shutil.copyfile(dos_src, doom)
win = os.path.join(media, "win95", "win95.vhd")
mkfat(win, 32, True)
put(win, "/COMMAND.COM", b"x")
put(win, "/MSDOS.SYS", b"[Paths]\r\nWinDir=C:\\WINDOWS\r\n[Options]\r\nBootMulti=1\r\n")
put(win, "/AUTOEXEC.BAT", b"@ECHO OFF\r\nCD GAME\r\n")
nodos = os.path.join(media, "nodos", "linux.vhd")
mkfat(nodos, 32, True)
put(nodos, "/SYSLINUX.CFG", b"DEFAULT linux\n")
plain = os.path.join(media, "plain", "plain.vhd")
mkfat(plain, 16, False)
put(plain, "/COMMAND.COM", b"x")
with open(os.path.join(media, "cd", "game.iso"), "wb") as f:
    f.write(b"\0" * 4096)

doom_before = get(doom, "/AUTOEXEC.BAT")
win_before = get(win, "/AUTOEXEC.BAT")
check(doom_before is not None, "setup: the DOS disk has AUTOEXEC.BAT")
imgs = {p: open(p, "rb").read() for p in (doom, win, nodos, plain)}

# 1. dry run
r = run("--dry-run")
check(r.returncode == 0 and "doom/doom.vhd: would install" in r.stdout and "Dry run: 2 disks would change." in r.stdout,
      "dry run: says what it would do")
check(all(open(p, "rb").read() == d for p, d in imgs.items()), "dry run: no image changed")

# 2. install
r = run()
check(r.returncode == 0, "install: exit code 0")
check("doom/doom.vhd: installed" in r.stdout and "plain/plain.vhd: installed" in r.stdout, "install: both DOS disks")
check("win95/win95.vhd: skipped (Windows 95/98)" in r.stdout, "install: Windows 95 skipped")
check("nodos/linux.vhd: skipped (no DOS on it)" in r.stdout, "install: no DOS skipped")
check("game.iso" not in r.stdout, "install: CD images not touched")
check("Done: 2 disks with the menu." in r.stdout, "install: the count")
a = get(doom, "/AUTOEXEC.BAT")
lines = [l.strip().upper() for l in a.decode("latin-1").splitlines()]
hook = next((i for i, l in enumerate(lines) if l == "CALL C:\\NETPLAY\\NETBOOT.BAT BOOT"), -1)
game = next((i for i, l in enumerate(lines) if l.startswith("CD ") or "RUNGAME" in l), -1)
check(hook >= 0 and lines[hook + 1] == "IF EXIST C:\\NETPLAY\\NPSKIP.FLG GOTO NPEND", "install: the two hook lines")
check(game < 0 or hook < game, "install: the hook before the game start")
check(lines[-1] == ":NPEND", "install: :NPEND last")
check(b"\r\n" in a and a.count(b"\n") == a.count(b"\r\n"), "install: DOS line ends")
check(get(doom, "/AUTOEXEC.NPB") == doom_before, "install: the backup is the old AUTOEXEC.BAT")
names = mt("mdir", "-b", "::/NETPLAY", img=doom).stdout.decode().upper()
check(all(n in names for n in ("NPMENU.EXE", "NPIPX.COM", "NE2000.COM", "GAMES.INI", "NETBOOT.BAT", "README.TXT")),
      "install: C:\\NETPLAY has the kit")
fl = subprocess.run(["mtype", "-i", os.path.join(games, "NETPLAY.IMG"), "::/NPMENU.EXE"], env=ENV, capture_output=True).stdout
check(get(doom, "/NETPLAY/NPMENU.EXE") == fl, "install: NPMENU.EXE is the floppy's")
check(get(doom, "/NP.BAT") == b"@ECHO OFF\r\nCALL C:\\NETPLAY\\NETBOOT.BAT\r\n", "install: NP.BAT")
check(get(plain, "/AUTOEXEC.BAT") == b"@ECHO OFF\r\nCALL C:\\NETPLAY\\NETBOOT.BAT BOOT\r\n"
      b"IF EXIST C:\\NETPLAY\\NPSKIP.FLG GOTO NPEND\r\n:NPEND\r\n", "install: a disk without AUTOEXEC.BAT gets one")
check(not exists(plain, "/AUTOEXEC.NPB"), "install: no backup where there was nothing")
check(get(win, "/AUTOEXEC.BAT") == win_before and not exists(win, "/NETPLAY"), "install: Windows 95 disk unchanged")
check(not exists(nodos, "/NETPLAY"), "install: the disk without DOS unchanged")
off = int(part(doom).split("@@")[1]) if "@@" in part(doom) else 0
fs = os.path.join(out, "fs.img")
with open(doom, "rb") as f:
    f.seek(off)
    data = f.read()
with open(fs, "wb") as f:
    f.write(data)
r2 = subprocess.run(["fsck.vfat", "-n", fs], capture_output=True, text=True)
check(r2.returncode == 0, "install: the file system is clean (fsck.vfat -n)")
os.remove(fs)
installed = open(doom, "rb").read()

# 7. shortcuts
npm = os.path.join(fat, "_Netplay", "_DOS Games")
check("Shortcuts: 1 in Netplay -> DOS Games" in r.stdout, "shortcuts: the count")
d = open(os.path.join(npm, "Doom.mgl")).read() if os.path.exists(os.path.join(npm, "Doom.mgl")) else ""
check(d == mgl_doom.replace("_computer/ao486", "_Netplay/ao486_netplay"), "shortcuts: Doom's copy starts _Netplay/ao486_netplay, the rest the same")
check(not os.path.exists(os.path.join(npm, "Win.mgl")) and not os.path.exists(os.path.join(npm, "Mario.mgl")),
      "shortcuts: none for the Windows disk or another core")
check(open(mine).read() == MGL % ("_computer/ao486", "media/plain/plain.vhd"), "shortcuts: the user's own file left alone")
check(open(os.path.join(fat, "_DOS Games", "Doom.mgl")).read() == mgl_doom, "shortcuts: the original unchanged")

# 3. again
r = run()
check("doom/doom.vhd: updated (it had the menu)" in r.stdout, "again: updated")
check(get(doom, "/AUTOEXEC.BAT") == a, "again: AUTOEXEC.BAT the same")
shutil.copyfile(doom, os.path.join(out, "installed.vhd"))   # for the boot test in QEMU

# 4. uninstall
r = subprocess.run(["bash", os.path.join(scripts, "ao486_netplay_uninstall.sh"), "--menu-root", fat, games], capture_output=True, text=True)
print(r.stdout + r.stderr, flush=True)
check(not os.path.exists(os.path.join(npm, "Doom.mgl")) and os.path.exists(mine), "uninstall: our shortcut gone, the user's kept")
check(r.returncode == 0 and "doom/doom.vhd: uninstalled" in r.stdout, "uninstall: done")
check("win95/win95.vhd: nothing to take off" in r.stdout, "uninstall: Windows 95 had nothing")
check(get(doom, "/AUTOEXEC.BAT") == doom_before, "uninstall: AUTOEXEC.BAT byte for byte the old one")
check(not exists(doom, "/NETPLAY") and not exists(doom, "/NP.BAT") and not exists(doom, "/AUTOEXEC.NPB"),
      "uninstall: C:\\NETPLAY, NP.BAT, the backup gone")
check(not exists(plain, "/NETPLAY"), "uninstall: the disk without a backup too")

# 5. a line added after the install stays
with open(doom, "wb") as f:
    f.write(installed)
put(doom, "/AUTOEXEC.BAT", a.replace(b"\r\n", b"\r\nREM ADDED LATER\r\n", 1))
subprocess.run(["bash", os.path.join(scripts, "ao486_netplay_uninstall.sh"), "--menu-root", fat, games], capture_output=True)
after = get(doom, "/AUTOEXEC.BAT").decode("latin-1").splitlines()
check("REM ADDED LATER" in after, "edited: the added line stays")
check([l for l in after if l != "REM ADDED LATER"] == doom_before.decode("latin-1").splitlines(),
      "edited: only the netplay lines went")

# 6. not while ao486 runs
with open("/tmp/CORENAME", "w") as f:
    f.write("AO486")
r = run()
check(r.returncode == 1 and "core is running" in r.stdout, "core running: refused")
os.remove("/tmp/CORENAME")

print("ALL PASS" if not failures else "%d FAILED" % len(failures), flush=True)
sys.exit(1 if failures else 0)
