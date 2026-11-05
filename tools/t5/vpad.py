#!/usr/bin/env python3
"""Virtual pad on a MiSTer (uinput). It copies a pad whose button map is
already on the MiSTer, so no mapping is needed, and that map has no OSD button:

  nes   INNEX NES Controller (1292:4643): A B Select Start
  snes  a pad with the ID 2810:0009, default map input_2810_0009_v3.map:
        A B X Y L R Select Start (the SNES core has no map of its own for it)

  python3 vpad.py [--snes] BUTTONS... [hold_s]   e.g.  vpad.py start   vpad.py --snes x 1.5

Buttons: a b x y l r select start up down left right (several = pressed together).
Used by run_t5.py. The first pad used after boot becomes player 1.
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
# name, vid, pid, buttons in the order A B Select Start X Y L R (as in the maps)
PROFILES = {
    "nes": (b"INNEX NES Controller USB", 0x1292, 0x4643, [0x130, 0x131, 0x132, 0x133]),
    "snes": (b"USB Gamepad", 0x2810, 0x0009, [0x130, 0x131, 0x13a, 0x13b, 0x133, 0x134, 0x136, 0x137]),
}


class Pad:
    def __init__(self, system="nes"):
        name, vid, pid, self.buttons = PROFILES[system]
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_ABS)
        for b in self.buttons:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, b)
        for a in (0, 1):
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, a)
        absmax = [0] * 64; absmin = [0] * 64
        absmax[0] = absmax[1] = 1; absmin[0] = absmin[1] = -1
        dev = struct.pack("80sHHHHI", name, 3, vid, pid, 0x110, 0)
        dev += struct.pack("64i", *absmax) + struct.pack("64i", *absmin) + bytes(4 * 64 * 2)
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        self.state = None

    def ev(self, t, c, v):
        os.write(self.fd, struct.pack("@llHHi", 0, 0, t, c, v))

    def set(self, x, y, keys):
        for i, b in enumerate(self.buttons):
            self.ev(EV_KEY, b, 1 if keys >> i & 1 else 0)
        self.ev(EV_ABS, 0, x)
        self.ev(EV_ABS, 1, y)
        self.ev(EV_SYN, 0, 0)

    def play(self, seconds, rng, intro=0):
        """Random buttons for seconds. The first intro seconds press only Start
        and A, never a direction: menus take their default, which is 1 Player
        (a recording has no player 2, a 2-player mode would wait for them)."""
        end = time.time() + seconds
        intro_end = time.time() + intro
        while time.time() < min(intro_end, end):
            for keys in (8, 1):
                self.set(0, 0, keys); time.sleep(0.15)
                self.set(0, 0, 0); time.sleep(0.6)
        while time.time() < end:
            x = rng.choice((-1, 0, 1, 1))          # a bit more right: games move on
            y = rng.choice((-1, 0, 0, 1))
            keys = (rng.random() < 0.5) | (rng.random() < 0.5) << 1
            if rng.random() < 0.02: keys |= 4      # Select
            if rng.random() < 0.01: keys |= 8      # Start (pause, menus)
            if len(self.buttons) > 4:              # SNES: X Y often, L R now and then
                keys |= (rng.random() < 0.4) << 4 | (rng.random() < 0.4) << 5
                keys |= (rng.random() < 0.15) << 6 | (rng.random() < 0.15) << 7
            self.set(x, y, keys)
            time.sleep(rng.uniform(0.05, 0.4))
        self.set(0, 0, 0)

    def close(self):
        self.set(0, 0, 0)
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)



NAMES = {"a": 1, "b": 2, "select": 4, "start": 8, "x": 16, "y": 32, "l": 64, "r": 128}

if __name__ == "__main__":
    args = sys.argv[1:]
    system = "snes" if "--snes" in args else "nes"
    args = [a for a in args if a != "--snes"]
    hold = float(args.pop()) if args and args[-1].replace(".", "").isdigit() else 0.2
    keys = sum(NAMES.get(a, 0) for a in args)
    x = -1 if "left" in args else 1 if "right" in args else 0
    y = -1 if "up" in args else 1 if "down" in args else 0
    pad = Pad(system)
    time.sleep(1.0)          # let MiSTer open the device
    pad.set(x, y, keys)
    time.sleep(hold)
    pad.close()
