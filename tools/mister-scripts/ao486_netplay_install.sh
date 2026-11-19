#!/bin/bash
# MiSTer Scripts menu: puts the ao486 netplay menu (SPEC.md 15.5) on every DOS
# hard disk image in games/AO486 at once, the same as A:\INSTALL on each disk:
# C:\NETPLAY, C:\NP.BAT and two lines in C:\AUTOEXEC.BAT (the old one kept as
# C:\AUTOEXEC.NPB). Then a disk with the network card on asks at boot: online
# or single player (single player after 10 s). Disks that have it get the new
# files only. ao486_netplay_uninstall.sh takes it off all of them again.
#
# The kit comes from games/AO486/NETPLAY.IMG. Skipped: Windows 95/98 disks
# (they boot into Windows), images without DOS (no COMMAND.COM), CD images.
# Run it with the ao486 core closed (from the MiSTer menu, as the Scripts menu
# does): a disk the core has mounted must not change under it.
#
# Game shortcuts (MGL files in the menu's _ folders, such as _DOS Games) that
# start the ao486 core with one of these disks are copied to _Netplay/_DOS Games
# with the core changed to _Netplay/ao486_netplay, so the netplay core starts
# them from the main menu's Netplay folder; the originals keep the normal core.
#
#   ao486_netplay_install.sh [--uninstall] [--dry-run] [--menu-root DIR] [games dir ...]
#
# Licence: GNU GPL version 2 or later.
if [ "$(cat /tmp/CORENAME 2>/dev/null)" = "AO486" ]; then
	echo "The ao486 core is running: close it first (MiSTer menu), then run this again."
	exit 1
fi
exec python3 -I - "$@" <<'PY'
import os, re, subprocess, sys, tempfile

args = sys.argv[1:]
menu_root = "/media/fat"
if "--menu-root" in args:
    i = args.index("--menu-root")
    menu_root = args[i + 1]
    del args[i:i + 2]
uninstall = "--uninstall" in args
dry = "--dry-run" in args
dirs = [a for a in args if not a.startswith("--")]
NP_RBF = "_Netplay/ao486_netplay"
NP_MGL = os.path.join(menu_root, "_Netplay", "_DOS Games")

KIT = ["NPMENU.EXE", "NPIPX.COM", "NE2000.COM", "GAMES.INI", "NETBOOT.BAT", "README.TXT"]
HOOK = ["CALL C:\\NETPLAY\\NETBOOT.BAT BOOT", "IF EXIST C:\\NETPLAY\\NPSKIP.FLG GOTO NPEND"]
END = ":NPEND"


def games_dirs():
    out = []
    for root in ["/media/usb%d" % i for i in range(6)] + ["/media/fat"]:
        g = os.path.join(root, "games")
        if not os.path.isdir(g):
            continue
        for n in os.listdir(g):
            if n.upper() == "AO486" and os.path.isdir(os.path.join(g, n)):
                out.append(os.path.join(g, n))
    return out


def find(d, name):
    """the entry of d named name, any case (FAT keeps the case it was given)"""
    try:
        for n in os.listdir(d):
            if n.upper() == name.upper():
                return os.path.join(d, n)
    except OSError:
        pass
    return None


class Mount:
    def __init__(self, img, offset, ro):
        self.dir = tempfile.mkdtemp(prefix="np486.")
        opt = "loop,offset=%d,shortname=mixed%s" % (offset, ",ro" if ro else "")
        r = subprocess.run(["mount", "-t", "vfat", "-o", opt, img, self.dir], capture_output=True, text=True)
        if r.returncode:
            os.rmdir(self.dir)
            raise OSError(r.stderr.strip() or "mount failed")

    def close(self):
        subprocess.run(["sync"])
        r = subprocess.run(["umount", self.dir], capture_output=True, text=True)
        if r.returncode:
            print("   warning: umount: " + r.stderr.strip())
        else:
            os.rmdir(self.dir)


def fat_offset(img):
    """byte offset of the first FAT partition, or None"""
    with open(img, "rb") as f:
        s = f.read(512)
    if len(s) < 512 or s[510:512] != b"\x55\xaa":
        return None
    if s[0x36:0x39] == b"FAT" or s[0x52:0x55] == b"FAT":
        return 0                                    # no partition table
    for i in range(4):
        e = s[446 + 16 * i:462 + 16 * i]
        if e[4] in (0x01, 0x04, 0x06, 0x0B, 0x0C, 0x0E):
            return int.from_bytes(e[8:12], "little") * 512
    return None


def read_lines(path):
    with open(path, "rb") as f:
        data = f.read()
    if b"\x1a" in data:                             # DOS end of file
        data = data[:data.index(b"\x1a")]
    lines = [l[:-1] if l.endswith("\r") else l for l in data.decode("latin-1").split("\n")]
    if lines and lines[-1] == "":
        lines.pop()                                 # the last line's end
    return lines, data


def write_lines(path, lines):
    with open(path, "wb") as f:
        f.write(("".join(l + "\r\n" for l in lines)).encode("latin-1"))


def norm(l):
    return l.strip().upper()


def is_hook(l):
    return norm(l) in HOOK or norm(l) == END


def hook_at(lines):
    """before the first CD or RUNGAME line (how the ready-made disks start their game), else the end"""
    for i, l in enumerate(lines):
        u = norm(l)
        if u.startswith("CD ") or u.startswith("CD\\") or "RUNGAME" in u:
            return i
    return len(lines)


def windows(root):
    """Windows 95/98 boots into Windows: MSDOS.SYS is a text file without BootGUI=0"""
    p = find(root, "MSDOS.SYS")
    if not p or os.path.getsize(p) > 64 * 1024:
        return False
    t = open(p, "rb").read().decode("latin-1").upper().replace(" ", "")
    return "[OPTIONS]" in t and "BOOTGUI=0" not in t


def install(root, kit):
    if dry:
        return "would install"
    nd = find(root, "NETPLAY") or os.path.join(root, "NETPLAY")
    os.makedirs(nd, exist_ok=True)
    for name, data in kit.items():
        with open(find(nd, name) or os.path.join(nd, name), "wb") as f:
            f.write(data)
    with open(find(root, "NP.BAT") or os.path.join(root, "NP.BAT"), "wb") as f:
        f.write(b"@ECHO OFF\r\nCALL C:\\NETPLAY\\NETBOOT.BAT\r\n")
    ap = find(root, "AUTOEXEC.BAT")
    lines = read_lines(ap)[0] if ap else []
    if any("NETPLAY\\NETBOOT" in norm(l) for l in lines):
        return "updated (it had the menu)"
    ap = ap or os.path.join(root, "AUTOEXEC.BAT")
    if lines and not find(root, "AUTOEXEC.NPB"):
        with open(ap, "rb") as a, open(os.path.join(root, "AUTOEXEC.NPB"), "wb") as b:
            b.write(a.read())
    at = hook_at(lines)
    new = lines[:at] + ([] if lines else ["@ECHO OFF"]) + HOOK + lines[at:] + [END]
    write_lines(ap, new)
    return "installed"


def remove(root):
    ap = find(root, "AUTOEXEC.BAT")
    nd = find(root, "NETPLAY")
    lines, data = read_lines(ap) if ap else ([], b"")
    hooks = sum(1 for l in lines if is_hook(l))
    if not hooks and not nd:
        return "nothing to take off"
    if dry:
        return "would uninstall"
    bp = find(root, "AUTOEXEC.NPB")
    if hooks:
        rest = [l for l in lines if not is_hook(l)]
        if bp and read_lines(bp)[0] == rest:
            with open(bp, "rb") as a, open(ap, "wb") as b:   # the old file, byte for byte
                b.write(a.read())
        else:
            write_lines(ap, rest)                          # later changes stay
    for p in (bp, find(root, "NP.BAT")):
        if p:
            os.remove(p)
    if nd:
        for n in os.listdir(nd):
            p = os.path.join(nd, n)
            if os.path.isfile(p):
                os.remove(p)
        try:
            os.rmdir(nd)
        except OSError:
            return "uninstalled (C:\\NETPLAY kept: it has folders of yours)"
    return "uninstalled"


RBF_RE = re.compile(r"<rbf>\s*([^<]*?)\s*</rbf>", re.I)
PATH_RE = re.compile(r'path\s*=\s*"([^"]*)"', re.I)


def ao486_mgls():
    """the menu's MGL files that start the normal ao486 core: (path, text)"""
    out = []
    try:
        tops = sorted(os.listdir(menu_root))
    except OSError:
        return out
    for t in tops:
        top = os.path.join(menu_root, t)
        if not t.startswith("_") or t.lower() == "_netplay" or not os.path.isdir(top):
            continue
        for d, sub, files in os.walk(top):
            if d[len(top):].count(os.sep) >= 3:
                sub[:] = []
            for f in sorted(files):
                if not f.lower().endswith(".mgl"):
                    continue
                p = os.path.join(d, f)
                try:
                    text = open(p, "rb").read().decode("latin-1")
                except OSError:
                    continue
                m = RBF_RE.search(text)
                if m and m.group(1).replace("\\", "/").strip("/").lower() == "_computer/ao486":
                    out.append((p, text))
    return out


def ours(p):
    try:
        m = RBF_RE.search(open(p, "rb").read().decode("latin-1"))
    except OSError:
        return False
    return bool(m) and m.group(1).lower() == NP_RBF.lower()


def shortcuts(with_menu):
    """copy the ao486 shortcuts of disks with the menu to _Netplay/_DOS Games"""
    nd = os.path.join(menu_root, "_Netplay")
    have = [f for f in (os.listdir(nd) if os.path.isdir(nd) else [])
            if f.lower().endswith(".rbf") and (f.lower() == "ao486_netplay.rbf" or f.lower().startswith("ao486_netplay_"))]
    if not have:
        print("Shortcuts: no ao486_netplay core in _Netplay, so none were made.")
        return
    n = 0
    for p, text in ao486_mgls():
        disks = [x.replace("\\", "/").lower() for x in PATH_RE.findall(text)]
        if not any(x in with_menu for x in disks):
            continue
        dst = os.path.join(NP_MGL, os.path.basename(p))
        if os.path.exists(dst) and not ours(dst):
            continue                                # a file of the user's: left alone
        n += 1
        if dry:
            continue
        os.makedirs(NP_MGL, exist_ok=True)
        with open(dst, "wb") as f:
            f.write(RBF_RE.sub("<rbf>%s</rbf>" % NP_RBF, text, count=1).encode("latin-1"))
    print("Shortcuts: %d %s Netplay -> DOS Games (they start ao486_netplay)." %
          (n, "would go in" if dry else "in"))


def remove_shortcuts():
    if not os.path.isdir(NP_MGL):
        return
    n = 0
    for f in os.listdir(NP_MGL):
        p = os.path.join(NP_MGL, f)
        if f.lower().endswith(".mgl") and ours(p):
            n += 1
            if not dry:
                os.remove(p)
    if not dry:
        try:
            os.rmdir(NP_MGL)
        except OSError:
            pass
    print("Shortcuts: %d %s Netplay -> DOS Games." % (n, "would go from" if dry else "removed from"))


def load_kit(gdirs):
    for g in gdirs:
        img = find(g, "NETPLAY.IMG")
        if not img:
            continue
        m = Mount(img, 0, True)
        try:
            kit = {}
            for n in KIT:
                p = find(m.dir, n)
                if not p:
                    raise OSError("%s has no %s" % (img, n))
                kit[n] = open(p, "rb").read()
            return kit, img
        finally:
            m.close()
    return None, None


def main():
    if os.geteuid() != 0:
        print("Run it as root (the Scripts menu does).")
        return 1
    gdirs = dirs or games_dirs()
    if not gdirs:
        print("No games/AO486 folder found.")
        return 1
    kit = None
    if not uninstall:
        kit, src = load_kit(gdirs)
        if not kit:
            print("No NETPLAY.IMG in " + ", ".join(gdirs) + ": copy it to games/AO486 first.")
            return 1
        print("Kit from " + src)
    print(("Taking the netplay menu off" if uninstall else "Putting the netplay menu on") +
          " the DOS disks in " + ", ".join(gdirs) + (" (dry run: nothing changes)" if dry else ""))
    n = 0
    with_menu = set()
    for g in gdirs:
        for d, sub, files in os.walk(g):
            sub.sort()
            for f in sorted(files):
                if not f.lower().endswith(".vhd"):
                    continue
                img = os.path.join(d, f)
                name = os.path.relpath(img, g)
                try:
                    off = fat_offset(img)
                    if off is None:
                        print(" - %s: skipped (no FAT partition)" % name)
                        continue
                    m = Mount(img, off, dry)
                except OSError as e:
                    print(" - %s: skipped (%s)" % (name, e))
                    continue
                try:
                    if not find(m.dir, "COMMAND.COM"):
                        what = "skipped (no DOS on it)"
                    elif windows(m.dir) and not uninstall:
                        what = "skipped (Windows 95/98)"
                    else:
                        what = remove(m.dir) if uninstall else install(m.dir, kit)
                        n += what.startswith(("installed", "updated", "uninstalled", "would"))
                        if what.startswith(("installed", "updated", "would install")):
                            with_menu.add(name.replace(os.sep, "/").lower())
                except OSError as e:
                    what = "FAILED: %s" % e
                finally:
                    m.close()
                print(" - %s: %s" % (name, what))
    if uninstall:
        remove_shortcuts()
    else:
        shortcuts(with_menu)
    if dry:
        print("Dry run: %d disk%s would change." % (n, "" if n == 1 else "s"))
        return 0
    print("Done: %d disk%s %s." % (n, "" if n == 1 else "s", "without the menu now" if uninstall else "with the menu"))
    if not uninstall and n:
        print("Boot one with the network card on (ao486 OSD, Hardware: Netplay Host or Join)")
        print("and press 1 at the question for the network game menu.")
    return 0


sys.exit(main())
PY
