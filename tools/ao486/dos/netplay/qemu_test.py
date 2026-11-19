#!/usr/bin/env python3
"""T3e-m: the ao486 netplay menu in QEMU (SPEC.md 15.5).

Runs inside the np-qemu Docker image (qemu-system-i386 with ne2k_isa):

    docker run --rm -v <dir>:/t np-qemu python3 /t/qemu_test.py /t/dos.img /t/NETPLAY.IMG /t/out

<dos.img>: a bootable DOS hard disk (raw; a fixed VHD works) whose
AUTOEXEC.BAT starts a game the way the ready-made ao486 disks do (CD <dir>,
RUNGAME.BAT). It is not changed: the test works on copies in <out>.

What it checks, with the screen read from VGA text memory:
  1. install: A:\\INSTALL hooks AUTOEXEC.BAT before the game start, backs it up
  2. card off: the boot goes on to the disk's own game as before, no question
  3. card on, no key: the boot asks online or single player and after 10 s
     goes on as single player (no drivers, no menu)
  4. card on (IRQ 10, to see the IRQ found), 1 = online: drivers loaded once
     (NE2000.COM, NPIPX), the menu comes up and lists a fake Heretic; F10
     leaves at the DOS prompt and NP brings the menu back without loading the
     drivers again
  5. two PCs on one wire: each sees the other in the room (NPIPX broadcasts);
     A starts Heretic (deathmatch), B follows with J and gets the same command
     line
  6. A:\\UNINSTALL: AUTOEXEC.BAT is byte for byte the old one, C:\\NETPLAY,
     C:\\NP.BAT and the backup are gone; with a line added after the install,
     only the netplay lines go and the added line stays
"""
import os, shutil, socket, subprocess, sys, time

QEMU = "qemu-system-i386"
disk_src, floppy, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
failures = []


def check(cond, what):
    print(("PASS " if cond else "FAIL ") + what, flush=True)
    if not cond:
        failures.append(what)


# ---------------------------------------------------------------- the disk

def part_offset(img):
    with open(img, "rb") as f:
        mbr = f.read(512)
    return int.from_bytes(mbr[446 + 8:446 + 12], "little") * 512


def mtools(*args, img):
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    return subprocess.run(list(args[:1]) + ["-i", f"{img}@@{part_offset(img)}"] + list(args[1:]),
                          env=env, capture_output=True, text=True)


def read_file(img, path):
    return mtools("mtype", "::" + path, img=img).stdout


# a COM program that writes its command line to C:\ARGS.TXT: the fake game
# (waits 5 s first, so the other menu sees the start before this one is back)
FAKE = bytes.fromhex(
    "b400cd1a89d383c35ab400cd1a39da72f8"
    "b43c31c9ba3101cd2193b4408a0e800030edba8100cd21b43ecd21b8004ccd21") + b"C:\\ARGS.TXT\0"


def add_fake_games(img):
    """Heretic, with a fake IPXSETUP that records its command line"""
    tmp = os.path.join(out, "fake")
    os.makedirs(tmp, exist_ok=True)
    files = [("HERETIC.WAD", b"IWAD"), ("IPXSETUP.EXE", FAKE), ("HERETIC.EXE", FAKE)]
    for name, data in files:
        with open(os.path.join(tmp, name), "wb") as f:
            f.write(data)
    mtools("mmd", "::/HERETIC", img=img)
    for name, _ in files:
        mtools("mcopy", "-o", os.path.join(tmp, name), "::/HERETIC/" + name, img=img)


# ------------------------------------------------------------------ the VM

KEYS = {" ": "spc", "\n": "ret", "\\": "backslash", ":": "shift-semicolon", ".": "dot",
        "-": "minus", "_": "shift-minus", "/": "slash", "=": "equal", "&": "shift-7", ">": "shift-dot"}


class Vm:
    def __init__(self, name, disk, floppy=None, nic=None, mac="52:54:00:12:34:56"):
        self.name = name
        self.sock = os.path.join(out, name + ".mon")
        if os.path.exists(self.sock):
            os.remove(self.sock)
        cmd = [QEMU, "-m", "16", "-display", "none", "-vga", "std", "-cpu", "486",
               "-drive", f"file={disk},format=raw,if=ide,index=0",
               "-boot", "c", "-monitor", f"unix:{self.sock},server,nowait"]
        if floppy:
            cmd += ["-drive", f"file={floppy},format=raw,if=floppy,index=0,readonly=on"]
        if nic:
            irq, netdev = nic
            cmd += ["-netdev", netdev + ",id=n0", "-device", f"ne2k_isa,iobase=0x300,irq={irq},netdev=n0,mac={mac}"]
        self.p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=open(os.path.join(out, name + ".err"), "w"))
        for _ in range(100):
            if os.path.exists(self.sock):
                break
            time.sleep(0.1)
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(self.sock)
        self._read()

    def _read(self):
        buf = b""
        while not buf.endswith(b"\r\n(qemu) ") and not buf == b"(qemu) " and not buf.endswith(b"information\r\n(qemu) "):
            got = self.s.recv(65536)
            if not got:                         # QEMU has quit
                break
            buf += got
        return buf.decode("latin-1")

    def cmd(self, c):
        self.s.setblocking(False)              # drop what an earlier command left
        try:
            while self.s.recv(65536):
                pass
        except BlockingIOError:
            pass
        self.s.setblocking(True)
        self.s.sendall((c + "\n").encode())
        return self._read()

    def key(self, k):
        self.cmd("sendkey " + k)
        time.sleep(0.12)

    def type(self, text):
        for ch in text:
            if ch in KEYS:
                k = KEYS[ch]
            elif ch.isupper():
                k = "shift-" + ch.lower()
            else:
                k = ch
            self.key(k)

    def screen(self):
        raw = self.cmd("xp /2000hx 0xb8000")
        cells = []
        for line in raw.splitlines():
            if ":" not in line or not line.strip().startswith("00000000000b8"):
                continue
            for w in line.split(":", 1)[1].split():
                cells.append(int(w, 16) & 0xFF)
        rows = []
        for r in range(25):
            rows.append("".join(chr(c) if 32 <= c < 127 else " " for c in cells[r * 80:(r + 1) * 80]))
        return rows

    def wait_for(self, text, timeout=60):
        end = time.time() + timeout
        while time.time() < end:
            scr = self.screen()
            if any(text in r for r in scr):
                return True
            time.sleep(0.5)
        self.dump()
        return False

    def dump(self):
        print(f"--- {self.name} screen", flush=True)
        for r in self.screen():
            print("| " + r.rstrip(), flush=True)

    def quit(self):
        try:
            self.cmd("quit")
        except OSError:
            pass
        self.p.wait(timeout=10)


# ------------------------------------------------------------------ tests

base = os.path.join(out, "base.img")
shutil.copyfile(disk_src, base)
add_fake_games(base)
autoexec_before = read_file(base, "/AUTOEXEC.BAT")

# 1. install from the floppy: leave the disk's own game menu first
vm = Vm("install", base, floppy=floppy)
time.sleep(8)
vm.key("ctrl-c"); time.sleep(1); vm.type("y\n"); time.sleep(1)
vm.type("a:\\install\n")
check(vm.wait_for("Netplay installed", 30), "install: A:\\INSTALL reports success")
vm.quit()
autoexec = read_file(base, "/AUTOEXEC.BAT")
backup = read_file(base, "/AUTOEXEC.NPB")
lines = [l.strip().upper() for l in autoexec.splitlines()]
check(backup == autoexec_before, "install: AUTOEXEC.NPB is the old AUTOEXEC.BAT")
hook = next((i for i, l in enumerate(lines) if "NETPLAY\\NETBOOT.BAT BOOT" in l), -1)
game = next((i for i, l in enumerate(lines) if l.startswith("CD ") or "RUNGAME" in l), -1)
check(hook >= 0 and (game < 0 or hook < game), "install: the hook comes before the disk's game start")
check(lines and lines[-1] == ":NPEND", "install: :NPEND at the end")
check("NPMENU.EXE" in mtools("mdir", "-b", "::/NETPLAY", img=base).stdout.upper(), "install: C:\\NETPLAY filled")

# 2. card off: boot goes on to the disk's game as before
off = os.path.join(out, "off.img")
shutil.copyfile(base, off)
vm = Vm("off", off)
check(vm.wait_for("no network card", 40), "card off: NETBOOT says so")
time.sleep(4)
scr = "\n".join(vm.screen())
check("MiSTer ao486 netplay" not in scr and "How do you want to play" not in scr, "card off: no question, no menu, the boot goes on")
vm.quit()

# 3. card on, no key: single player after 10 s
single = os.path.join(out, "single.img")
shutil.copyfile(base, single)
vm = Vm("single", single, nic=("10", "user"))
check(vm.wait_for("How do you want to play", 60), "boot: the question comes up with the card on")
t0 = time.time()
check(any("Single player starts in" in r for r in vm.screen()), "boot: the countdown shows")
check(vm.wait_for("single player (no network drivers loaded)", 20), "boot: single player without a key")
waited = time.time() - t0
check(8 <= waited <= 13, f"boot: single player after about 10 s ({waited:.1f} s)")
time.sleep(4)
scr = "\n".join(vm.screen())
check("MiSTer ao486 netplay" not in scr, "boot: single player goes on booting, no menu")
vm.quit()

# 4. card on, IRQ 10, online
one = os.path.join(out, "one.img")
shutil.copyfile(base, one)
vm = Vm("one", one, nic=("10", "user"))
check(vm.wait_for("How do you want to play", 60), "online: the question")
vm.key("1")
check(vm.wait_for("MiSTer ao486 netplay", 60), "card on: the menu comes up")
scr = "\n".join(vm.screen())
check("Network card ready" in scr and "IRQ 10" in scr, "card on: drivers loaded, IRQ 10 found")
check("Heretic " in scr and "C:\\HERETIC" in scr, "card on: Heretic found in C:\\HERETIC")
check("Warcraft II" in scr or "Strife" in scr, "card on: games not on the disk are listed too")
vm.key("f10")
time.sleep(2)
vm.type("np\n")
check(vm.wait_for("MiSTer ao486 netplay", 30), "NP again: the menu comes back")
check(any("IRQ 10" in r for r in vm.screen()), "NP again: still IRQ 10")
vm.key("f10")
vm.quit()
load = read_file(one, "/NETPLAY/NPLOAD.BAT").upper()
check("NE2000" not in load and "NPIPX" not in load, "NP again: the drivers were found loaded, not loaded twice")
check(read_file(one, "/NETPLAY/NPIRQ.TXT").strip() == "10", "card on: NPIRQ.TXT says 10")

# 5. two PCs on one wire (QEMU socket network)
a_img, b_img = os.path.join(out, "a.img"), os.path.join(out, "b.img")
shutil.copyfile(base, a_img)
shutil.copyfile(base, b_img)
a = Vm("a", a_img, nic=("11", "socket,listen=127.0.0.1:12345"), mac="52:54:00:00:00:0a")
time.sleep(1)
b = Vm("b", b_img, nic=("11", "socket,connect=127.0.0.1:12345"), mac="52:54:00:00:00:0b")
check(a.wait_for("How do you want to play", 60) and b.wait_for("How do you want to play", 60), "two: both ask")
a.key("down"); a.key("ret"); b.key("o")   # Up/Down + Enter on one, the letter on the other
check(a.wait_for("MiSTer ao486 netplay", 60) and b.wait_for("MiSTer ao486 netplay", 60), "two: both menus up")
time.sleep(4)
sa, sb = "\n".join(a.screen()), "\n".join(b.screen())
check("PLAYER-000B" in sa and "PLAYER-000A" in sb, "two: each sees the other in the room")
# A: move to Heretic, Enter, Mode -> Deathmatch, Enter
row = next(i for i, r in enumerate(a.screen()[4:18]) if "C:\\HERETIC" in r)
for _ in range(row):
    a.key("down")
a.key("ret"); time.sleep(1)
check(a.wait_for("Start Heretic", 10), "two: A's setup screen")
a.key("down"); a.key("right"); time.sleep(0.5)
check(any("-nodes 2 -deathmatch -skill 3" in r for r in a.screen()), "two: A's command line")
a.key("ret")
check(b.wait_for("Press J to join", 20), "two: B is invited")
b.key("j")
check(b.wait_for("Same settings as the other player", 10), "two: B's follow screen")
b.key("ret")
time.sleep(1)
check(a.wait_for("MiSTer ao486 netplay", 30) and b.wait_for("MiSTer ao486 netplay", 30), "two: both back in the menu after the game")
a.key("f10"); b.key("f10"); time.sleep(1)
a.quit(); b.quit()
args_a, args_b = read_file(a_img, "/ARGS.TXT").strip(), read_file(b_img, "/ARGS.TXT").strip()
print(f"A ran IPXSETUP {args_a!r}, B ran IPXSETUP {args_b!r}", flush=True)
check(args_a == "-nodes 2 -deathmatch -skill 3", "two: A's game got its command line")
check(args_a == args_b, "two: B's game got the same")

# 6. uninstall from the floppy (card off: the boot goes to the game, leave it)
def uninstall(name, img):
    vm = Vm(name, img, floppy=floppy)
    vm.wait_for("no network card", 40)
    time.sleep(6)
    vm.key("ctrl-c"); time.sleep(1); vm.type("y\n"); time.sleep(1)
    vm.type("a:\\uninstall\n")       # 9 letters: DOS cuts it to UNINSTAL
    ok = vm.wait_for("Netplay removed", 30)
    vm.quit()
    return ok


def gone(img, path):
    return mtools("mdir", "::" + path, img=img).returncode != 0


un = os.path.join(out, "un.img")
shutil.copyfile(base, un)
check(uninstall("un", un), "uninstall: A:\\UNINSTALL reports success")
check(read_file(un, "/AUTOEXEC.BAT") == autoexec_before, "uninstall: AUTOEXEC.BAT is the old one again")
check(gone(un, "/NETPLAY") and gone(un, "/NP.BAT") and gone(un, "/AUTOEXEC.NPB"), "uninstall: C:\\NETPLAY, NP.BAT, AUTOEXEC.NPB gone")

un2 = os.path.join(out, "un2.img")
shutil.copyfile(base, un2)
edited = read_file(un2, "/AUTOEXEC.BAT").replace("\r\n", "\n").rstrip("\n").split("\n")
edited.insert(1, "REM ADDED AFTER THE INSTALL")
tmpf = os.path.join(out, "autoexec.edit")
with open(tmpf, "wb") as f:
    f.write(("\r\n".join(edited) + "\r\n").encode("latin-1"))
mtools("mcopy", "-o", tmpf, "::/AUTOEXEC.BAT", img=un2)
check(uninstall("un2", un2), "uninstall, edited: reports success")
after = [l.strip().upper() for l in read_file(un2, "/AUTOEXEC.BAT").splitlines()]
before = [l.strip().upper() for l in autoexec_before.splitlines()]
check("REM ADDED AFTER THE INSTALL" in after, "uninstall, edited: the added line stays")
check([l for l in after if l != "REM ADDED AFTER THE INSTALL"] == before, "uninstall, edited: only the netplay lines went")
check(gone(un2, "/NETPLAY"), "uninstall, edited: C:\\NETPLAY gone")

print(("ALL PASS" if not failures else f"{len(failures)} FAILED"), flush=True)
sys.exit(1 if failures else 0)
