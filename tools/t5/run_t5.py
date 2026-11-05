#!/usr/bin/env python3
"""T5 on a MiSTer without a person playing (SPEC.md T5, and T5s for SNES).

Runs on the MiSTer (Python 3.9 there). For each game: record with a virtual
gamepad pressing random buttons, then replay every recording and read the
result from /media/fat/netplay/netplay.log. Writes a report to
/media/fat/_netplaytest/result-<system>.txt.

The virtual gamepad copies a pad whose map is already on the MiSTer (see
vpad.py), so no mapping is needed. It must be the first pad used after boot to
be player 1: start this right after a reboot and do not touch the real pads.
The maps have no OSD button, so random presses cannot open the OSD menu.

  python3 run_t5.py [nes|snes] [seconds_per_game] [LABEL...]
      (default nes, 630 s, > 36000 frames; LABELs pick games, e.g. DSP-1)

netplay.ini is backed up and put back at the end.
"""
import os, random, signal, struct, sys, time

FAT = "/media/fat"
TEST = FAT + "/_netplaytest"
NES = "/media/usb0/games/NES"
SNES = "/media/usb0/games/SNES/_USA"
SYSTEMS = {
    # core, MGL file index, games: label (mapper or chip), name, ROM
    "nes": ("NES_netplay", 0, [
        ("NROM", "Super Mario Bros.", NES + "/S ROMS/Super Mario Bros. (World).nes"),
        ("MMC1", "Zelda", NES + "/L ROMS/Legend of Zelda, The (USA).nes"),
        ("MMC3", "SMB3", NES + "/S ROMS/Super Mario Bros. 3 (USA).nes"),
        ("MMC5", "Castlevania III", NES + "/C ROMS/Castlevania III - Dracula's Curse (USA).nes"),
    ]),
    "snes": ("SNES_netplay", 1, [
        ("LoROM", "Super Mario World", SNES + "/S/Super Mario World (U) [!].smc"),
        ("HiROM", "Donkey Kong Country", SNES + "/D/Donkey Kong Country (U) (V1.0) [!].smc"),
        ("SA-1", "Kirby Super Star", SNES + "/K/Kirby Super Star (U) [!].smc"),
        ("GSU2", "Yoshi's Island", SNES + "/S/Super Mario World 2 - Yoshi's Island (U) (M3) (V1.0) [!].smc"),
        # Pilotwings, not Super Mario Kart: SMK's menu ends up in 2P with Start/A,
        # and a recording has no player 2 to pick a kart
        ("DSP-1", "Pilotwings", SNES + "/P/Pilotwings (U) [!].smc"),
    ]),
}
args = sys.argv[1:]
SYSTEM = args.pop(0) if args and args[0] in SYSTEMS else "nes"
CORE, INDEX, GAMES = SYSTEMS[SYSTEM]
SECONDS = int(args.pop(0)) if args and args[0].isdigit() else 630
if args:
    GAMES = [g for g in GAMES if g[0] in args]
PILOT_S = 25
INTRO_S = 30         # Start and A only, so the menus stay on 1 Player (vpad.py)
LOAD_S = 12          # core load + MGL file delay + session start
FRAMES_NEEDED = 36000

os.makedirs(TEST, exist_ok=True)
out = open(TEST + "/result-%s.txt" % SYSTEM, "w")


def say(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    out.write(line + "\n")
    out.flush()


from vpad import Pad


# ---------------------------------------------------------------- MiSTer
def load(rom):
    """Load the netplay core with this ROM through an MGL file; rom=None loads the menu."""
    if rom is None:
        cmd = "load_core " + FAT + "/menu.rbf\n"
    else:
        mgl = TEST + "/" + os.path.splitext(os.path.basename(rom))[0] + ".mgl"
        with open(mgl, "w") as f:
            f.write('<mistergamedescription>\n <rbf>_Console/%s</rbf>\n'
                    ' <file delay="2" type="f" index="%d" path="%s"/>\n</mistergamedescription>\n'
                    % (CORE, INDEX, rom))
        cmd = "load_core " + mgl + "\n"
    with open("/dev/MiSTer_cmd", "w") as f:
        f.write(cmd)


def npr(rom):
    return FAT + "/netplay/" + os.path.splitext(os.path.basename(rom))[0] + ".npr"


def npr_info(path):
    """(frames, crcs, pad changes) or None"""
    try:
        d = open(path, "rb").read()
    except OSError:
        return None
    if d[:4] == b"NPR2":       # md5[16], u8 delay, u32 frames, u8 joy[frames], u32 crcs
        n = struct.unpack_from("<I", d, 21)[0]
        joy = d[25:25 + n]
        m = struct.unpack_from("<I", d, 25 + n)[0]
    elif d[:4] == b"NPR3":     # md5[16], u8 delay, u8 system, u32 frames, u16 joy[frames], u32 crcs
        n = struct.unpack_from("<I", d, 22)[0]
        joy = struct.unpack_from("<%dH" % n, d, 26)
        m = struct.unpack_from("<I", d, 26 + 2 * n)[0]
    else:
        return None
    changes = sum(1 for i in range(1, n) if joy[i] != joy[i - 1])
    return n, m, changes


LOG = FAT + "/netplay/netplay.log"


def log_size():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


def log_since(pos):
    try:
        with open(LOG) as f:
            f.seek(pos)
            return f.read()
    except OSError:
        return ""


def set_ini(mode):
    lines = open(FAT + "/netplay.ini").read().splitlines(True)
    with open(FAT + "/netplay.ini", "w") as f:
        for l in lines:
            if l.startswith("mode="): l = "mode=%-17s; host | join | record | replay | off\n" % mode
            elif l.startswith("file="): l = "file=               ; record/replay: empty = one file per game\n"
            f.write(l)


def describe(rom):
    """NES: the iNES mapper. SNES: map mode and chip byte from the internal header."""
    d = open(rom, "rb").read(0x410000)
    if SYSTEM == "nes":
        return "mapper %d" % ((d[6] >> 4) | (d[7] & 0xF0))
    off = 512 if len(d) % 1024 == 512 else 0
    for base in (0x7FC0, 0xFFC0, 0x40FFC0):
        h = d[off + base:off + base + 32]
        if len(h) == 32 and (h[0x15] & 0x0F) in (0, 1, 2, 3, 5, 0xA) and all(32 <= c < 127 for c in h[:21]):
            return "%s, map %02x, chip %02x" % (h[:21].decode().strip(), h[0x15], h[0x16])
    return "no header found"


# ---------------------------------------------------------------- run
def record(pad, rom, seconds, seed):
    pos = log_size()
    load(rom)
    time.sleep(LOAD_S)
    pad.play(seconds, random.Random(seed), INTRO_S)
    return log_since(pos)


def main():
    # kill (SIGTERM) also runs the finally below: netplay.ini is put back
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(1))
    seconds = SECONDS
    if not GAMES:
        say("no game matches " + " ".join(args)); return 1
    ini = open(FAT + "/netplay.ini").read()
    open(TEST + "/netplay.ini.bak", "w").write(ini)
    say("T5 %s start, %d s per game" % (SYSTEM.upper(), seconds))
    if not os.path.exists(FAT + "/_Console/" + CORE + ".rbf"):
        say("MISSING " + FAT + "/_Console/" + CORE + ".rbf"); return 1
    for label, name, rom in GAMES:
        if not os.path.exists(rom):
            say("MISSING %s" % rom); return 1
        say("%s: %s, %s" % (label, name, describe(rom)))

    pad = Pad(SYSTEM)
    try:
        set_ini("record")
        time.sleep(1)

        # Pilot: is the virtual pad player 1?
        rom = GAMES[0][2]
        say("pilot: %d s of %s" % (PILOT_S, GAMES[0][1]))
        log = record(pad, rom, PILOT_S, 1)
        load(None); time.sleep(8)
        info = npr_info(npr(rom))
        say("pilot log: " + " | ".join(log.split("\n")[-6:]).strip())
        if not info or info[2] == 0:
            say("ABORT: pilot recording %s has no pad changes - the virtual pad is not player 1" % (info,))
            return 1
        say("pilot OK: %d frames, %d pad changes" % (info[0], info[2]))

        for i, (label, name, rom) in enumerate(GAMES):
            say("record %s (%s)" % (label, name))
            log = record(pad, rom, seconds, 100 + i)
            for l in log.splitlines():
                say("  log: " + l)
        load(None); time.sleep(8)     # leaving the core saves the last one

        rec = {}
        for label, name, rom in GAMES:
            rec[label] = npr_info(npr(rom))
            say("recorded %s: %s (frames, crcs, pad changes)" % (label, rec[label]))

        set_ini("replay")
        time.sleep(1)
        results = {}
        for label, name, rom in GAMES:
            say("replay %s (%s)" % (label, name))
            pos = log_size()
            load(rom)
            end = time.time() + seconds + 120
            verdict = "TIMEOUT"
            while time.time() < end:
                time.sleep(5)
                text = log_since(pos)
                if "replay OK" in text:
                    verdict = [l for l in text.splitlines() if "replay OK" in l][-1]; break
                if "DESYNC" in text:
                    verdict = [l for l in text.splitlines() if "DESYNC" in l][-1]; break
            results[label] = verdict
            for l in log_since(pos).splitlines():
                say("  log: " + l)
        load(None); time.sleep(8)

        say("=== RESULT ===")
        ok = True
        for label, name, rom in GAMES:
            r = rec[label]
            long_enough = bool(r) and r[0] >= FRAMES_NEEDED
            passed = "replay OK" in results[label] and long_enough
            ok &= passed
            say("%s %-5s %-16s frames=%s pad=%s  %s" % ("PASS" if passed else "FAIL", label, name,
                r[0] if r else "-", r[2] if r else "-", results[label]))
        say("T5 %s " % SYSTEM.upper() + ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    finally:
        pad.close()
        open(FAT + "/netplay.ini", "w").write(ini)
        say("netplay.ini restored")


if __name__ == "__main__":
    sys.exit(main())
