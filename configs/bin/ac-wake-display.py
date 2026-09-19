#!/usr/bin/env python3
"""
AC Wake Display Daemon for Samsung Galaxy Book
- Listens to UPower for AC adapter attach events.
- Listens to logind PrepareForSleep for suspend resume events.
- Wakes display panel and dismisses screen blanking using:
  1. /dev/uinput virtual key pulse (harmless Shift tap - simulates touching touchpad)
  2. GNOME Mutter DisplayConfig (PowerSaveMode = 0)
  3. GNOME ScreenSaver (SetActive = False)
- 100% event-driven, 0% CPU overhead, completely independent user-space service.
"""
import os
import sys
import glob
import time
import struct
import fcntl
import signal
import logging

# Ensure D-Bus environment
uid = os.getuid()
if "XDG_RUNTIME_DIR" not in os.environ:
    os.environ["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"
if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{uid}/bus"

import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("ac-wake-display")

# Linux uinput constants
UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_DEV_SETUP   = 0x405c5503
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0
KEY_LEFTSHIFT = 42
KEY_WAKEUP = 143

class AcWakeDisplay:
    def __init__(self):
        self.session_bus = None
        self.system_bus = None
        self.uinput_fd = None
        self.last_ac_state = None
        self.loop = None
        self._init_uinput()
        self._init_dbus()

    def _init_uinput(self):
        """Create a virtual input keyboard device to send wake events without root."""
        try:
            fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
            fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
            fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_WAKEUP)
            fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_LEFTSHIFT)

            setup_fmt = 'hhhh80sI'
            setup_data = struct.pack(setup_fmt, 0x03, 0x1234, 0x5678, 1, b'AC-Wake-Virtual-Key', 0)
            fcntl.ioctl(fd, UI_DEV_SETUP, setup_data)
            fcntl.ioctl(fd, UI_DEV_CREATE)
            self.uinput_fd = fd
            logger.info("Virtual uinput device initialized successfully.")
        except Exception as e:
            logger.warning(f"Unable to open /dev/uinput: {e}. Falling back to D-Bus only.")
            self.uinput_fd = None

    def _cleanup_uinput(self):
        if self.uinput_fd is not None:
            try:
                fcntl.ioctl(self.uinput_fd, UI_DEV_DESTROY)
                os.close(self.uinput_fd)
            except Exception:
                pass
            self.uinput_fd = None

    def _send_wake_pulse(self):
        """Emit a momentary harmless Shift key pulse to simulate user touchpad touch."""
        if self.uinput_fd is None:
            return
        try:
            event_fmt = 'llHHI'
            # KEY_LEFTSHIFT press & release
            down = struct.pack(event_fmt, 0, 0, EV_KEY, KEY_LEFTSHIFT, 1)
            syn  = struct.pack(event_fmt, 0, 0, EV_SYN, SYN_REPORT, 0)
            up   = struct.pack(event_fmt, 0, 0, EV_KEY, KEY_LEFTSHIFT, 0)

            os.write(self.uinput_fd, down + syn)
            time.sleep(0.01)
            os.write(self.uinput_fd, up + syn)
            logger.debug("Virtual wake input pulse emitted.")
        except Exception as e:
            logger.warning(f"Error sending uinput pulse: {e}")

    def _init_dbus(self):
        try:
            self.session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except Exception as e:
            logger.error(f"Failed to connect to session bus: {e}")

        try:
            self.system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

            # Subscribe to UPower PropertiesChanged
            self.system_bus.signal_subscribe(
                'org.freedesktop.UPower',
                'org.freedesktop.DBus.Properties',
                'PropertiesChanged',
                '/org/freedesktop/UPower',
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_upower_signal,
                None
            )

            # Subscribe to logind PrepareForSleep
            self.system_bus.signal_subscribe(
                'org.freedesktop.login1',
                'org.freedesktop.login1.Manager',
                'PrepareForSleep',
                '/org/freedesktop/login1',
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_sleep_signal,
                None
            )
        except Exception as e:
            logger.error(f"Failed to connect to system bus: {e}")

        self.last_ac_state = self.is_ac_connected()
        logger.info(f"Initial AC connected state: {self.last_ac_state}")

    def is_ac_connected(self) -> bool:
        """Check if any non-battery power supply reports online == 1."""
        for p in glob.glob('/sys/class/power_supply/*/online'):
            if 'BAT' not in p:
                try:
                    with open(p, 'r') as f:
                        if f.read().strip() == '1':
                            return True
                except Exception:
                    pass
        return False

    def wake_display(self, reason: str = ""):
        logger.info(f"WAKING DISPLAY [Reason: {reason}]")

        # 1. First emit the virtual user activity pulse (hardware-level wake)
        self._send_wake_pulse()

        # 2. Call Mutter DisplayConfig (PowerSaveMode = 0)
        if self.session_bus:
            try:
                self.session_bus.call_sync(
                    'org.gnome.Mutter.DisplayConfig',
                    '/org/gnome/Mutter/DisplayConfig',
                    'org.freedesktop.DBus.Properties',
                    'Set',
                    GLib.Variant('(ssv)', ('org.gnome.Mutter.DisplayConfig', 'PowerSaveMode', GLib.Variant('i', 0))),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1500,
                    None
                )
            except Exception as e:
                logger.debug(f"Mutter PowerSaveMode call: {e}")

            # 3. Call ScreenSaver (SetActive False)
            try:
                self.session_bus.call_sync(
                    'org.gnome.ScreenSaver',
                    '/org/gnome/ScreenSaver',
                    'org.gnome.ScreenSaver',
                    'SetActive',
                    GLib.Variant('(b)', (False,)),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1500,
                    None
                )
            except Exception as e:
                logger.debug(f"ScreenSaver SetActive call: {e}")

    def _on_upower_signal(self, conn, sender, path, iface, signal_name, params, data):
        ac_now = self.is_ac_connected()
        # Trigger when AC transition from unplugged -> plugged occurs
        if ac_now and not self.last_ac_state:
            logger.info("AC adapter plugged in (detected via UPower)")
            self.wake_display("AC plugged in")
        self.last_ac_state = ac_now

    def _on_sleep_signal(self, conn, sender, path, iface, signal_name, params, data):
        try:
            is_about_to_sleep, = params.unpack()
            if not is_about_to_sleep:
                # Resumed from suspend: if AC is connected, wake the screen!
                if self.is_ac_connected():
                    # Wait 300ms for DRM/display driver to settle
                    GLib.timeout_add(300, self._delayed_wake_after_resume)
        except Exception as e:
            logger.error(f"Error handling sleep signal: {e}")

    def _delayed_wake_after_resume(self):
        self.wake_display("Resume from suspend with AC plugged")
        self.last_ac_state = True
        return False

    def run(self):
        logger.info("AC Wake Display Daemon started and running.")

        def sig_handler(sig, frame):
            if self.loop and self.loop.is_running():
                self.loop.quit()

        signal.signal(signal.SIGINT, sig_handler)
        signal.signal(signal.SIGTERM, sig_handler)

        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        finally:
            self._cleanup_uinput()

if __name__ == '__main__':
    daemon = AcWakeDisplay()
    daemon.run()
