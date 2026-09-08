#!/usr/bin/env python3
"""
Power Refresh & SDR Governor Daemon for Galaxy Book 4 Pro (GB4P)
- Automatically switches refresh rate on AC (80Hz VRR) vs Battery (60Hz VRR)
  based on physical AC adapter connection (compatible with 80% battery protection mode)
- Enforces sdr-native color mode (sRGB clamping) across all power states, boots, and resumes
- Pure event-driven (UPower + logind D-Bus), 0 CPU overhead, 0 confirmation popups
- Auto-retries and watches for GNOME Shell DisplayConfig bus readiness on boot
"""
import sys
import os
import glob
import time
import signal
import logging

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
logger = logging.getLogger("power-sdr-daemon")

PREFERRED_CONNECTOR = "eDP-1"
AC_REFRESH_RATE = 80
BATTERY_REFRESH_RATE = 60

class PowerSdrGovernor:
    def __init__(self):
        self.loop = None
        self.session_bus = None
        self.system_bus = None
        self.display_proxy = None
        self.upower_proxy = None
        self._watcher_id = None
        self._retry_timer_id = None
        self._init_dbus()

    def _init_dbus(self):
        try:
            self.session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            # Watch for GNOME Shell / Mutter DisplayConfig service appearing on session bus
            self._watcher_id = Gio.bus_watch_name(
                Gio.BusType.SESSION,
                'org.gnome.Mutter.DisplayConfig',
                Gio.BusNameWatcherFlags.NONE,
                self._on_display_config_appeared,
                self._on_display_config_vanished
            )
        except Exception as e:
            logger.error(f"Failed to connect to session bus: {e}")

        try:
            self.system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            self.upower_proxy = Gio.DBusProxy.new_sync(
                self.system_bus,
                Gio.DBusProxyFlags.NONE,
                None,
                'org.freedesktop.UPower',
                '/org/freedesktop/UPower',
                'org.freedesktop.UPower',
                None
            )
            # Subscribe to UPower property changes
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
            # Subscribe to logind PrepareForSleep signal
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
            logger.error(f"Failed to connect to UPower/logind: {e}")

    def _on_display_config_appeared(self, conn, name, name_owner):
        logger.info(f"GNOME Mutter DisplayConfig service ready (owner: {name_owner})")
        try:
            self.display_proxy = Gio.DBusProxy.new_sync(
                self.session_bus,
                Gio.DBusProxyFlags.NONE,
                None,
                'org.gnome.Mutter.DisplayConfig',
                '/org/gnome/Mutter/DisplayConfig',
                'org.gnome.Mutter.DisplayConfig',
                None
            )
            # Apply initial display state as soon as DisplayConfig is ready
            self.update_display("DisplayConfig service appeared")
        except Exception as e:
            logger.error(f"Failed to create DisplayConfig proxy: {e}")

    def _on_display_config_vanished(self, conn, name):
        logger.warning("GNOME Mutter DisplayConfig service vanished")
        self.display_proxy = None

    def is_ac_connected(self) -> bool:
        """
        Check physical AC adapter online status (ADP1 / AC / USB-C).
        Returns True if AC is physically plugged in, even if battery charge limit
        (e.g., 80% protection mode) stops active charging.
        """
        try:
            # Primary known ACPI adapter paths on Samsung laptops
            for adp in [
                '/sys/class/power_supply/ADP1/online',
                '/sys/class/power_supply/AC/online',
                '/sys/class/power_supply/ACAD/online'
            ]:
                if os.path.exists(adp):
                    with open(adp, 'r') as f:
                        if f.read().strip() == '1':
                            return True

            # Check other non-battery power supplies (e.g. UCSI USB Type-C power sources)
            for p in glob.glob('/sys/class/power_supply/*/online'):
                if 'BAT' not in os.path.basename(p):
                    with open(p, 'r') as f:
                        if f.read().strip() == '1':
                            return True
        except Exception:
            pass

        # Fallback to UPower
        if self.upower_proxy:
            prop = self.upower_proxy.get_cached_property('OnBattery')
            if prop is not None:
                return not bool(prop.unpack())
        return False

    def update_display(self, reason: str = ""):
        if not self.display_proxy:
            # If DisplayConfig proxy is not ready yet, retry in 1s
            if self._retry_timer_id is None:
                self._retry_timer_id = GLib.timeout_add_seconds(1, self._retry_update, reason)
            return False

        ac_plugged = self.is_ac_connected()
        desired_rate = AC_REFRESH_RATE if ac_plugged else BATTERY_REFRESH_RATE
        power_str = "Plugged (AC)" if ac_plugged else "Battery (DC)"

        try:
            state = self.display_proxy.call_sync(
                method_name='GetCurrentState',
                parameters=None,
                flags=Gio.DBusCallFlags.NO_AUTO_START,
                timeout_msec=3000,
                cancellable=None
            )
            serial, monitors, logical_monitors, props = state.unpack()

            current_modes = {}
            current_color_modes = {}
            current_rgb_ranges = {}
            target_connector = None
            target_monitor_modes = []

            for mon in monitors:
                spec, modes, mon_props = mon
                conn = spec[0]
                current_color_modes[conn] = mon_props.get('color-mode', 0)
                if 'rgb-range' in mon_props:
                    current_rgb_ranges[conn] = mon_props.get('rgb-range')

                # Identify built-in panel connector
                if conn == PREFERRED_CONNECTOR:
                    target_connector = conn
                    target_monitor_modes = modes
                elif target_connector is None and (mon_props.get('is-builtin', False) or conn.startswith("eDP")):
                    target_connector = conn
                    target_monitor_modes = modes

                for m in modes:
                    mode_id, w, h, rate, pscale, sscales, m_props = m
                    if m_props.get('is-current', False):
                        current_modes[conn] = (mode_id, w, h, rate, m_props.get('refresh-rate-mode', 'fixed'))
                        break

            if not target_connector or target_connector not in current_modes:
                logger.warning("Target built-in display connector not active in current state")
                return False

            cur_mode_id, cur_w, cur_h, cur_rate, cur_rr_mode = current_modes[target_connector]
            cur_cm = current_color_modes.get(target_connector, 0)

            # Check if already in desired rate and sdr-native (color-mode == 2)
            if round(cur_rate) == desired_rate and cur_cm == 2:
                logger.debug(f"Already at {desired_rate}Hz VRR with sdr-native")
                return False

            # Find target mode matching resolution and desired refresh rate
            candidates = [
                m for m in target_monitor_modes
                if m[1] == cur_w and m[2] == cur_h and round(m[3]) == desired_rate
            ]
            # Prefer matching VRR mode
            target_mode_tuple = next(
                (m for m in candidates if m[6].get('refresh-rate-mode', 'fixed') == cur_rr_mode),
                candidates[0] if candidates else None
            )

            target_mode_id = target_mode_tuple[0] if target_mode_tuple else cur_mode_id

            logger.info(f"Applying {power_str} -> {target_mode_id} + sdr-native [Reason: {reason}]")

            # Build logical monitors config
            new_logical_monitors = []
            for lm in logical_monitors:
                x, y, scale, transform, primary, lm_monitors, lm_props = lm
                new_monitors = []
                for mon_spec in lm_monitors:
                    conn = mon_spec[0]
                    m_id = target_mode_id if conn == target_connector else current_modes.get(conn, ("",""))[0]
                    mon_options = {}
                    if conn == target_connector:
                        mon_options["color-mode"] = GLib.Variant("u", 2)  # sdr-native (sRGB clamping)
                    elif conn in current_color_modes:
                        mon_options["color-mode"] = GLib.Variant("u", current_color_modes[conn])
                    if conn in current_rgb_ranges:
                        mon_options["rgb-range"] = GLib.Variant("u", current_rgb_ranges[conn])
                    new_monitors.append((conn, m_id, mon_options))
                new_logical_monitors.append((x, y, scale, transform, primary, new_monitors))

            params = GLib.Variant(
                "(uua(iiduba(ssa{sv}))a{sv})",
                (
                    serial,
                    1,  # TEMPORARY = 1 (silent, no confirmation popup)
                    new_logical_monitors,
                    {}
                )
            )

            self.display_proxy.call_sync(
                method_name="ApplyMonitorsConfig",
                parameters=params,
                flags=Gio.DBusCallFlags.NO_AUTO_START,
                timeout_msec=5000,
                cancellable=None
            )
            logger.info(f"Successfully applied {desired_rate}Hz VRR + sdr-native")

        except Exception as e:
            logger.error(f"Failed to update display: {e}")
            if self._retry_timer_id is None:
                self._retry_timer_id = GLib.timeout_add_seconds(1, self._retry_update, f"Retry after error ({reason})")

        return False

    def _retry_update(self, reason):
        self._retry_timer_id = None
        self.update_display(reason)
        return False

    def _on_upower_signal(self, conn, sender, path, iface, signal_name, params, data):
        GLib.idle_add(self.update_display, "Power status changed")

    def _on_sleep_signal(self, conn, sender, path, iface, signal_name, params, data):
        try:
            is_about_to_sleep, = params.unpack()
            if not is_about_to_sleep:
                GLib.timeout_add_seconds(1, self.update_display, "Wake from suspend")
        except Exception:
            pass

    def run(self):
        logger.info(f"Starting Power Refresh & SDR Governor Daemon (AC: {AC_REFRESH_RATE}Hz VRR, Battery: {BATTERY_REFRESH_RATE}Hz VRR)...")

        def sig_handler(sig, frame):
            if self.loop and self.loop.is_running():
                self.loop.quit()

        signal.signal(signal.SIGINT, sig_handler)
        signal.signal(signal.SIGTERM, sig_handler)

        self.loop = GLib.MainLoop()
        self.loop.run()

if __name__ == '__main__':
    daemon = PowerSdrGovernor()
    daemon.run()
