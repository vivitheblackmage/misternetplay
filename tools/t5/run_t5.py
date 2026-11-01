#!/usr/bin/env python3
"""T5 on a MiSTer without a person playing (SPEC.md T5).

Runs on the MiSTer (Python 3.9 there). For each game: record with a virtual
gamepad pressing random buttons, then replay every recording and read the
result from /media/fat/netplay/netplay.log. Writes a report to
/media/fat/_netplaytest/result.txt.

The virtual gamepad copies the INNEX NES Controller (1292:4643), so MiSTer
uses its existing button map. It must be the first pad used after boot to be
player 1: start this right after a reboot and do not touch the real pads.
That map has no OSD button, so random presses cannot open the OSD menu.

  python3 run_t5.py [seconds_per_game]     (default 630 s, > 36000 frames)

netplay.ini is backed up and put back at the end.
"""
import os, random, struct, sys, time

FAT = "/media/fat"
TEST = FAT + "/_netplaytest"
NES = "/media/usb0/games/NES"
GAMES = [  # label, mapper family, ROM
    ("NROM", "Super Mario Bros.", NES + "/S ROMS/Super Mario Bros. (World).nes"),
    ("MMC1", "Zelda", NES + "/L ROMS/Legend of Zelda, The (USA).nes"),
    ("MMC3", "SMB3", NES + "/S ROMS/Super Mario Bros. 3 (USA).nes"),
    ("MMC5", "Castlevania III", NES + "/C ROMS/Castlevania III - Dracula's Curse (USA).nes"),
]
PILOT_S = 25
LOAD_S = 12          # core load + MGL file delay + session start
FRAMES_NEEDED = 36000

out = open(TEST + "/result.txt", "w")


def say(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    out.write(line + "\n")
    out.flush()


from vpad import Pad


# ---------------------------------------------------------------- MiSTer
def load(rom):
    """Load NES_netplay with this ROM through an MGL file; rom=None loads the menu."""
    if rom is None:
        cmd = "load_core " + FAT + "/menu.rbf\n"
    else:
        mgl = TEST + "/" + os.path.basename(rom)[:-4] + ".mgl"
        with open(mgl, "w") as f:
            f.write('<mistergamedescription>\n <rbf>_Console/NES_netplay</rbf>\n'
                    ' <file delay="2" type="f" index="0" path="%s"/>\n</mistergamedescription>\n' % rom)
        cmd = "load_core " + mgl + "\n"
    with open("/dev/MiSTer_cmd", "w") as f:
        f.write(cmd)


def npr(rom):
    return FAT + "/netplay/" + os.path.basename(rom)[:-4] + ".npr"


def npr_info(path):
    """(frames, crcs, pad changes) or None"""
    try:
        d = open(path, "rb").read()
    except OSError:
        return None
    if d[:4] != b"NPR2":
        return None
    n = struct.unpack_from("<I", d, 21)[0]
    joy = d[25:25 + n]
    m = struct.unpack_from("<I", d, 25 + n)[0]
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


def mapper(rom):
    h = open(rom, "rb").read(16)
    return (h[6] >> 4) | (h[7] & 0xF0)


# ---------------------------------------------------------------- run
def record(pad, rom, seconds, seed):
    pos = log_size()
    load(rom)
    time.sleep(LOAD_S)
    pad.play(seconds, random.Random(seed))
    return log_since(pos)


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 630
    ini = open(FAT + "/netplay.ini").read()
    open(TEST + "/netplay.ini.bak", "w").write(ini)
    say("T5 start, %d s per game" % seconds)
    for label, name, rom in GAMES:
        if not os.path.exists(rom):
            say("MISSING %s" % rom); return 1
        say("%s: %s, mapper %d" % (label, name, mapper(rom)))

    pad = Pad()
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
        say("T5 " + ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    finally:
        pad.close()
        open(FAT + "/netplay.ini", "w").write(ini)
        say("netplay.ini restored")


if __name__ == "__main__":
    sys.exit(main())
