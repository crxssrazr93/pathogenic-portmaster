#!/usr/bin/env python3
"""Virtual Xbox-style gamepad over uinput, driven by a simple script of steps.

Usage: vpad.py "wait 8; press A; wait 2; hold right 1.5; press START; shot name"
Steps: wait <s> | press <BTN> | tap <stick-dir|dpad-dir> | hold <BTN|left|right|up|down> <s> | shot <name>
       on <BTN|stick-dir|dpad-dir> | off <same>   (held input across other steps)
       stick-dir: left right up down (analog stick); dpad-dir: dleft dright dup ddown
       rec <name> | stoprec   (screen recording via $REC_CMD)
'shot' runs $SHOT_CMD with {name} substituted, so screenshots line up with input.
"""
import os, subprocess, sys, time
from evdev import UInput, ecodes as e, AbsInfo

BTN = {'A': e.BTN_SOUTH, 'B': e.BTN_EAST, 'X': e.BTN_WEST, 'Y': e.BTN_NORTH,
       'LB': e.BTN_TL, 'RB': e.BTN_TR, 'SELECT': e.BTN_SELECT, 'START': e.BTN_START}
AXIS = {'left': (e.ABS_X, -32767), 'right': (e.ABS_X, 32767),
        'up': (e.ABS_Y, -32767), 'down': (e.ABS_Y, 32767)}
HAT = {'dleft': (e.ABS_HAT0X, -1), 'dright': (e.ABS_HAT0X, 1),
       'dup': (e.ABS_HAT0Y, -1), 'ddown': (e.ABS_HAT0Y, 1)}
caps = {
    e.EV_KEY: list(BTN.values()) + [e.BTN_MODE, e.BTN_THUMBL, e.BTN_THUMBR],
    e.EV_ABS: [(a, AbsInfo(0, -32768, 32767, 16, 128, 0)) for a in (e.ABS_X, e.ABS_Y, e.ABS_RX, e.ABS_RY)]
              + [(a, AbsInfo(0, -1, 1, 0, 0, 0)) for a in (e.ABS_HAT0X, e.ABS_HAT0Y)],
}
pad = UInput(caps, name='Microsoft X-Box 360 pad', vendor=0x045e, product=0x028e, version=0x110)
time.sleep(1.0)

def run(script):
    for step in filter(None, (s.strip() for s in script.split(';'))):
        cmd, *args = step.split()
        if cmd == 'wait':
            time.sleep(float(args[0]))
        elif cmd == 'press':
            pad.write(e.EV_KEY, BTN[args[0]], 1); pad.syn(); time.sleep(0.12)
            pad.write(e.EV_KEY, BTN[args[0]], 0); pad.syn(); time.sleep(0.25)
        elif cmd == 'tap':
            # short d-pad or stick flick: tap <dleft|dright|dup|ddown|left|right|up|down>
            code, val = (HAT | AXIS)[args[0]]
            pad.write(e.EV_ABS, code, val); pad.syn(); time.sleep(0.12)
            pad.write(e.EV_ABS, code, 0); pad.syn(); time.sleep(0.25)
        elif cmd == 'hold':
            if args[0] in HAT:
                code, val = HAT[args[0]]
                pad.write(e.EV_ABS, code, val); pad.syn(); time.sleep(float(args[1]))
                pad.write(e.EV_ABS, code, 0); pad.syn()
            elif args[0] in AXIS:
                code, val = AXIS[args[0]]
                pad.write(e.EV_ABS, code, val); pad.syn(); time.sleep(float(args[1]))
                pad.write(e.EV_ABS, code, 0); pad.syn()
            else:
                pad.write(e.EV_KEY, BTN[args[0]], 1); pad.syn(); time.sleep(float(args[1]))
                pad.write(e.EV_KEY, BTN[args[0]], 0); pad.syn()
        elif cmd in ('on', 'off'):
            name, down = args[0], cmd == 'on'
            if name in AXIS:
                code, val = AXIS[name]
                pad.write(e.EV_ABS, code, val if down else 0)
            elif name in HAT:
                code, val = HAT[name]
                pad.write(e.EV_ABS, code, val if down else 0)
            else:
                pad.write(e.EV_KEY, BTN[name], 1 if down else 0)
            pad.syn()
        elif cmd == 'rec':
            # start a background screen recording of $REC_DISPLAY to <name>.mp4
            global rec
            rec = subprocess.Popen(os.environ['REC_CMD'].format(name=args[0]), shell=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif cmd == 'stoprec':
            rec.communicate(b'q', timeout=10)
        elif cmd == 'shot':
            subprocess.run(os.environ['SHOT_CMD'].format(name=args[0]), shell=True)
        print('done:', step, flush=True)

if __name__ == '__main__':
    run(sys.argv[1])
    pad.close()
