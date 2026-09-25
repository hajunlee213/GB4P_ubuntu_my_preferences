#!/usr/bin/env python3
"""
Touchpad Edge Motion Daemon for Linux (Wayland/X11)
Enables continuous cursor movement when dragging at the touchpad edges.
Supports both physical click-drag and tap-and-drag (double-tap hold).
"""

import sys
import os
import glob
import time
import math
import fcntl
import struct
import select
import threading
import argparse

# Linux Input Event Constants
EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03

SYN_REPORT = 0x00
REL_X = 0x00
REL_Y = 0x01

BTN_LEFT = 0x110
BTN_RIGHT = 0x111
BTN_MIDDLE = 0x112
BTN_TOUCH = 0x14A
BTN_TOOL_FINGER = 0x145
BTN_TOOL_DOUBLETAP = 0x148
BTN_TOOL_TRIPLETAP = 0x14D

ABS_X = 0x00
ABS_Y = 0x01
ABS_MT_SLOT = 0x2F
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36
ABS_MT_TOOL_TYPE = 0x37
ABS_MT_TRACKING_ID = 0x39

MT_TOOL_FINGER = 0
MT_TOOL_PALM = 2

# uinput ioctl constants
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_DEV_SETUP = 0x405c5503
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

# 64-bit input_event format: timeval(qq), type(H), code(H), value(i)
EVENT_FORMAT = "qqHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)


def find_touchpad_and_mouse_devices():
    """Find the event paths of touchpad and mouse buttons."""
    touchpad_dev = None
    button_devs = []

    try:
        with open("/proc/bus/input/devices", "r") as f:
            content = f.read()
    except Exception as e:
        print(f"[Error] Failed to read /proc/bus/input/devices: {e}")
        return None, []

    sections = content.strip().split("\n\n")
    for sec in sections:
        lines = sec.splitlines()
        name = ""
        handlers = ""
        for line in lines:
            if line.startswith("N: Name="):
                name = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("H: Handlers="):
                handlers = line.split("=", 1)[1].strip()

        if "touchpad" in name.lower():
            for h in handlers.split():
                if h.startswith("event"):
                    touchpad_dev = f"/dev/input/{h}"
                    print(f"[Info] Found Touchpad device: '{name}' at {touchpad_dev}")

        if any(keyword in name.lower() for keyword in ["touchpad", "mouse"]):
            for h in handlers.split():
                if h.startswith("event"):
                    dev_path = f"/dev/input/{h}"
                    if dev_path not in button_devs:
                        button_devs.append(dev_path)

    return touchpad_dev, button_devs


def get_abs_range(fd, axis):
    """Query min, max of an absolute axis via ioctl EVIOCGABS."""
    cmd = 0x80184540 + axis
    buf = bytearray(24)
    try:
        fcntl.ioctl(fd, cmd, buf)
        val, min_v, max_v, fuzz, flat, res = struct.unpack("6i", buf)
        return min_v, max_v
    except Exception:
        return 0, 0


class UInputPointer:
    """Virtual mouse pointer using Linux /dev/uinput with mouse handler capabilities."""

    def __init__(self, name="Touchpad Edge Motion Virtual Pointer"):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_RIGHT)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_MIDDLE)

        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_X)
        fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_Y)

        dev_name = name.encode("utf-8")[:79].ljust(80, b"\0")
        setup = struct.pack("HHHH80sI", 0x03, 0x1234, 0x5678, 1, dev_name, 0)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, setup)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)

    def move(self, dx, dy):
        """Emit relative mouse movement."""
        idx = int(dx)
        idy = int(dy)
        if idx == 0 and idy == 0:
            return

        events = []
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1_000_000)

        if idx != 0:
            events.append(struct.pack(EVENT_FORMAT, sec, usec, EV_REL, REL_X, idx))
        if idy != 0:
            events.append(struct.pack(EVENT_FORMAT, sec, usec, EV_REL, REL_Y, idy))

        events.append(struct.pack(EVENT_FORMAT, sec, usec, EV_SYN, SYN_REPORT, 0))
        os.write(self.fd, b"".join(events))

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
            os.close(self.fd)
        except Exception:
            pass


class EdgeMotionDaemon:
    def __init__(self, touchpad_path, button_paths, margin=0.04, speed=2.5,
                 hz=60, require_click=True, debug=False):
        self.touchpad_path = touchpad_path
        self.button_paths = button_paths
        self.margin = margin
        self.speed = speed
        self.hz = hz
        self.interval = 1.0 / hz
        self.require_click = require_click
        self.debug = debug

        # Open unique device paths to avoid reading duplicate events
        unique_paths = set([touchpad_path] + button_paths)
        self.fds = {}
        self.tp_fd = None
        
        for p in unique_paths:
            try:
                fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
                self.fds[fd] = p
                if p == touchpad_path:
                    self.tp_fd = fd
                
                label = "Touchpad + Clicks" if p == touchpad_path else "Clicks"
                print(f"[Info] Monitoring {label} on: {p}")
            except Exception as e:
                print(f"[Warn] Could not open device {p}: {e}")
                
        if self.tp_fd is None:
            raise RuntimeError("Could not open the primary touchpad device.")

        # Get Touchpad Axis boundaries
        self.x_min, self.x_max = get_abs_range(self.tp_fd, ABS_X)
        self.y_min, self.y_max = get_abs_range(self.tp_fd, ABS_Y)
        if self.x_max == 0:
            self.x_min, self.x_max = get_abs_range(self.tp_fd, ABS_MT_POSITION_X)
            self.y_min, self.y_max = get_abs_range(self.tp_fd, ABS_MT_POSITION_Y)

        self.width = self.x_max - self.x_min
        self.height = self.y_max - self.y_min

        self.left_thresh = self.x_min + self.width * self.margin
        self.right_thresh = self.x_max - self.width * self.margin
        self.top_thresh = self.y_min + self.height * self.margin
        self.bottom_thresh = self.y_max - self.height * self.margin

        target_px_sec = self.speed * self.hz
        print(f"[Info] Axis X: {self.x_min} ~ {self.x_max} (Edge Margin: <= {self.left_thresh:.0f} or >= {self.right_thresh:.0f})")
        print(f"[Info] Axis Y: {self.y_min} ~ {self.y_max} (Edge Margin: <= {self.top_thresh:.0f} or >= {self.bottom_thresh:.0f})")
        print(f"[Info] Smooth Motion: {target_px_sec:.0f} px/sec ({self.speed:.2f} px/frame @ {self.hz}Hz)")

        self.uinput = UInputPointer()

        # State tracking
        self.is_clicked = False
        self.is_touching = False
        self.is_palm = False

        self.cur_x = (self.x_min + self.x_max) / 2
        self.cur_y = (self.y_min + self.y_max) / 2
        self.finger_dx = 0.0
        self.finger_dy = 0.0

        # Sub-pixel accumulator for smooth 60fps interpolation
        self.accum_x = 0.0
        self.accum_y = 0.0

        # Tap-and-drag tracking state
        self.touch_active = False
        self.touch_down_time = 0.0
        self.has_initial_pos = False
        self.touch_start_x = 0.0
        self.touch_start_y = 0.0
        self.touch_max_move = 0.0

        self.last_valid_tap_time = 0.0
        self.last_valid_tap_x = 0.0
        self.last_valid_tap_y = 0.0

        self.is_tap_dragging = False

        # Debug log throttling
        self.last_debug_log_time = 0.0

        self.running = False
        self.motion_thread = None
        self.motion_wakeup = threading.Event()

    def is_in_edge_margin(self, x, y):
        """Check if coordinates fall inside the edge margin."""
        return (x <= self.left_thresh or x >= self.right_thresh or
                y <= self.top_thresh or y >= self.bottom_thresh)

    def is_drag_active(self):
        """Check if drag condition is met (physical click OR tap-drag)."""
        if not self.is_touching or self.is_palm:
            return False
        if not self.require_click:
            return True
        return self.is_clicked or self.is_tap_dragging

    def calculate_velocity(self):
        """Calculate constant (vx, vy) if in edge margin and not moving inward."""
        if not self.is_drag_active():
            return 0.0, 0.0

        vx = 0.0
        vy = 0.0

        # Horizontal edge: constant speed
        if self.cur_x <= self.left_thresh:
            if self.finger_dx <= 5:  # not moving back inward
                vx = -self.speed
        elif self.cur_x >= self.right_thresh:
            if self.finger_dx >= -5:  # not moving back inward
                vx = self.speed

        # Vertical edge: constant speed
        if self.cur_y <= self.top_thresh:
            if self.finger_dy <= 5:  # not moving back inward
                vy = -self.speed
        elif self.cur_y >= self.bottom_thresh:
            if self.finger_dy >= -5:  # not moving back inward
                vy = self.speed

        return vx, vy

    def _motion_loop(self):
        """Periodic loop that injects buttery-smooth 60fps relative motion."""
        next_wakeup = time.time() + self.interval
        while self.running:
            vx, vy = self.calculate_velocity()
            now = time.time()
            if vx != 0.0 or vy != 0.0:
                self.accum_x += vx
                self.accum_y += vy

                step_x = int(self.accum_x)
                step_y = int(self.accum_y)

                if step_x != 0 or step_y != 0:
                    self.accum_x -= step_x
                    self.accum_y -= step_y
                    self.uinput.move(step_x, step_y)

                    if self.debug and (now - self.last_debug_log_time >= 0.3):
                        self.last_debug_log_time = now
                        print(f"[Edge Motion ACTIVE] step=({step_x}, {step_y}) (pos: x={self.cur_x:.0f}, y={self.cur_y:.0f})")

                now_time = time.time()
                sleep_time = next_wakeup - now_time
                if sleep_time > 0:
                    time.sleep(sleep_time)
                else:
                    # Prevent rapid-fire catchup after suspend/lag
                    next_wakeup = now_time
                next_wakeup += self.interval

            else:
                self.accum_x = 0.0
                self.accum_y = 0.0
                # Idle state: wait for a wakeup event instead of 60Hz polling
                self.motion_wakeup.wait(timeout=1.0)
                self.motion_wakeup.clear()
                next_wakeup = time.time() + self.interval

    def _handle_touch_down(self, now):
        """Handle finger landing on touchpad."""
        self.touch_active = True
        self.is_touching = True
        self.is_palm = False
        self.touch_down_time = now
        self.has_initial_pos = False
        self.touch_max_move = 0.0

    def _handle_touch_up(self, now):
        """Handle finger lifting from touchpad."""
        if not self.touch_active:
            return

        self.touch_active = False
        duration = now - self.touch_down_time

        # Check if this release was a valid 1st TAP:
        is_tap = (
            0.03 <= duration <= 0.28 and
            self.touch_max_move < 180 and
            not self.is_in_edge_margin(self.touch_start_x, self.touch_start_y)
        )

        if is_tap:
            self.last_valid_tap_time = now
            self.last_valid_tap_x = self.cur_x
            self.last_valid_tap_y = self.cur_y
            if self.debug:
                print(f"[Tap 1 REGISTERED] dur={duration*1000:.0f}ms, move={self.touch_max_move:.0f}")
        else:
            if duration > 0.28 or self.touch_max_move >= 180:
                self.last_valid_tap_time = 0.0
            if self.debug and duration < 0.5:
                print(f"[Touch Lifted] dur={duration*1000:.0f}ms, move={self.touch_max_move:.0f} (Normal Move)")

        self.is_touching = False
        self.is_tap_dragging = False
        self.accum_x = 0.0
        self.accum_y = 0.0
        self.finger_dx = 0.0
        self.finger_dy = 0.0

    def _update_finger_pos(self, new_x, new_y, now):
        """Update finger position and track tap-and-drag trigger."""
        if not self.has_initial_pos:
            self.touch_start_x = new_x
            self.touch_start_y = new_y
            self.has_initial_pos = True
            self.cur_x = new_x
            self.cur_y = new_y

            gap = now - self.last_valid_tap_time
            dist = math.hypot(new_x - self.last_valid_tap_x, new_y - self.last_valid_tap_y)
            started_in_edge = self.is_in_edge_margin(new_x, new_y)

            if not started_in_edge and (gap < 0.40) and (dist < 300):
                self.is_tap_dragging = True
                self.last_valid_tap_time = 0.0
                if self.debug:
                    print(f"===> [DRAG ACTIVATED] Tap-and-drag started! (gap={gap*1000:.0f}ms, dist={dist:.0f}) <===")
            return

        move = math.hypot(new_x - self.touch_start_x, new_y - self.touch_start_y)
        if move > self.touch_max_move:
            self.touch_max_move = move

        self.finger_dx = new_x - self.cur_x
        self.finger_dy = new_y - self.cur_y
        self.cur_x = new_x
        self.cur_y = new_y

    def run(self):
        self.running = True
        self.motion_thread = threading.Thread(target=self._motion_loop, daemon=True)
        self.motion_thread.start()

        all_fds = list(self.fds.keys())
        # To avoid constant single-event os.read overhead, read up to 64 events at once
        CHUNK_SIZE = EVENT_SIZE * 64

        print("[Info] Edge Motion Daemon started. Waiting for drag events...")
        try:
            while self.running:
                readable, _, _ = select.select(all_fds, [], [])
                now = time.time()

                for r_fd in readable:
                    while True:
                        try:
                            data = os.read(r_fd, CHUNK_SIZE)
                            if not data:
                                break
                            
                            self.motion_wakeup.set()

                            # Parse all read events
                            for sec, usec, etype, ecode, evalue in struct.iter_unpack(EVENT_FORMAT, data):

                                if etype == EV_KEY:
                                    if ecode == BTN_LEFT:
                                        self.is_clicked = (evalue == 1)
                                        if self.debug:
                                            print(f"[Click] BTN_LEFT: {self.is_clicked}")

                                    elif ecode == BTN_TOUCH:
                                        if evalue == 1:
                                            self._handle_touch_down(now)
                                        else:
                                            self._handle_touch_up(now)

                                    elif ecode in (BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP):
                                        if evalue == 1:
                                            self.is_touching = True

                                elif etype == EV_ABS:
                                    if ecode in (ABS_X, ABS_MT_POSITION_X):
                                        self._update_finger_pos(evalue, self.cur_y, now)
                                    elif ecode in (ABS_Y, ABS_MT_POSITION_Y):
                                        self._update_finger_pos(self.cur_x, evalue, now)

                                    elif ecode == ABS_MT_TOOL_TYPE:
                                        if evalue == MT_TOOL_PALM:
                                            self.is_palm = True
                                            self.is_tap_dragging = False
                                            if self.debug:
                                                print("[Palm] Hardware Palm Detected -> Rejected")
                                        elif evalue == MT_TOOL_FINGER:
                                            self.is_palm = False

                                    elif ecode == ABS_MT_TRACKING_ID and evalue == -1:
                                        self._handle_touch_up(now)

                        except BlockingIOError:
                            break

        except KeyboardInterrupt:
            print("\n[Info] Stopping daemon...")
        finally:
            self.running = False
            self.motion_wakeup.set()
            if self.motion_thread:
                self.motion_thread.join(timeout=1.0)
            self.uinput.close()
            for fd in self.fds.keys():
                try:
                    os.close(fd)
                except Exception:
                    pass
            print("[Info] Clean exit completed.")


def main():
    parser = argparse.ArgumentParser(description="Touchpad Edge Motion Daemon for Linux")
    parser.add_argument("--device", help="Path to touchpad event device (e.g. /dev/input/event6)")
    parser.add_argument("--margin", type=float, default=0.04, help="Edge margin ratio (default: 0.04 = 4%%)")
    parser.add_argument("--speed", type=float, default=2.5, help="Movement speed (pixels/frame, default: 2.5)")
    parser.add_argument("--hz", type=int, default=60, help="Update frequency (Hz, default: 60)")
    parser.add_argument("--require-click", action="store_true", default=True, help="Only trigger while dragging (default: True)")
    parser.add_argument("--no-require-click", dest="require_click", action="store_false", help="Trigger even on normal hover")
    parser.add_argument("--debug", action="store_true", help="Print debug logs to console")

    args = parser.parse_args()

    tp_dev, btn_devs = find_touchpad_and_mouse_devices()
    if args.device:
        tp_dev = args.device
        if tp_dev not in btn_devs:
            btn_devs.append(tp_dev)

    if not tp_dev:
        print("[Error] Could not automatically find a touchpad device.")
        sys.exit(1)

    daemon = EdgeMotionDaemon(
        touchpad_path=tp_dev,
        button_paths=btn_devs,
        margin=args.margin,
        speed=args.speed,
        hz=args.hz,
        require_click=args.require_click,
        debug=args.debug
    )
    daemon.run()


if __name__ == "__main__":
    main()
