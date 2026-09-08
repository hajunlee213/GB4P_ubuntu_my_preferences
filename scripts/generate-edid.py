#!/usr/bin/env python3
"""
Galaxy Book 4 Pro (16" AMOLED, Samsung ATNA60CL07-0) Custom EDID Generator
-------------------------------------------------------------------------
This script takes the native panel EDID and creates a custom EDID binary with
multiple fixed refresh rates (60Hz, 75Hz, 80Hz, 100Hz, 120Hz).

Why V-Blank Extension?
OLED notebook panel TCONs lock to a fixed 655.13 MHz dotclock. Reducing dotclock
(standard LCD approach) drops TCON sync and causes a black screen.
By keeping dotclock (655.13 MHz) and horizontal line rate (219.84 kHz) constant
and stretching vertical blanking (V-Blank lines), the panel refreshes at lower
rates without losing sync.
"""

import os
import sys
import glob

def make_dtd_vblank(h_act, h_blank, h_front, h_sync, v_act, v_blank, v_front, v_sync, pclk_10khz, flags=0x1b):
    """Constructs an 18-byte Detailed Timing Descriptor (DTD)."""
    b = bytearray(18)
    b[0] = pclk_10khz & 0xff
    b[1] = (pclk_10khz >> 8) & 0xff
    b[2] = h_act & 0xff
    b[3] = h_blank & 0xff
    b[4] = ((h_act >> 8) << 4) | (h_blank >> 8)
    b[5] = v_act & 0xff
    b[6] = v_blank & 0xff
    b[7] = ((v_act >> 8) << 4) | (v_blank >> 8)
    b[8] = h_front & 0xff
    b[9] = h_sync & 0xff
    b[10] = ((v_front & 0x0f) << 4) | (v_sync & 0x0f)
    b[11] = (((h_front >> 8) & 0x03) << 6) | (((h_sync >> 8) & 0x03) << 4) | (((v_front >> 4) & 0x03) << 2) | ((v_sync >> 4) & 0x03)
    b[12] = 0x58  # 344mm width
    b[13] = 0xd7  # 215mm height
    b[14] = 0x10
    b[15] = 0x00
    b[16] = 0x00
    b[17] = flags
    return b

def recalc_checksum(block):
    """Calculates EDID 128-byte block checksum so sum(block) % 256 == 0."""
    s = sum(block[:127]) % 256
    block[127] = (256 - s) % 256
    return block

def find_panel_edid():
    """Finds active eDP panel EDID from sysfs."""
    candidates = glob.glob("/sys/class/drm/card*-eDP-1/edid") + glob.glob("/sys/class/drm/card*-eDP-*/edid")
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    default_output = os.path.join(project_root, "configs", "edid", "gb4p_custom_edid.bin")

    input_path = sys.argv[1] if len(sys.argv) > 1 else find_panel_edid()
    output_path = sys.argv[2] if len(sys.argv) > 2 else default_output

    if not input_path or not os.path.isfile(input_path):
        print(f"[!] Error: Could not locate input EDID file.", file=sys.stderr)
        print(f"    Usage: {sys.argv[0]} [input_edid_path] [output_bin_path]", file=sys.stderr)
        sys.exit(1)

    print(f"[*] Reading source EDID from: {input_path}")
    with open(input_path, "rb") as f:
        orig = bytearray(f.read())

    if len(orig) < 256:
        print(f"[!] Error: EDID size {len(orig)} bytes is invalid (expected >= 256).", file=sys.stderr)
        sys.exit(1)

    # Fixed dotclock: 655.13 MHz (65513 in 10kHz units)
    # H-Active: 2880, H-Blank: 100, H-Total: 2980
    # Line Frequency: 655.13 MHz / 2980 = 219.842 kHz
    # V-Total = 219842 / Target_Hz
    # V-Blank = V-Total - 1800
    pclk_fixed = 65513

    # DTD calculations:
    # 60Hz:  V-Total = 3664, V-Blank = 1864 -> 60.00 Hz
    # 75Hz:  V-Total = 2931, V-Blank = 1131 -> 75.01 Hz
    # 80Hz:  V-Total = 2748, V-Blank = 948  -> 80.00 Hz
    # 100Hz: V-Total = 2198, V-Blank = 398  -> 100.02 Hz
    dtd_60  = make_dtd_vblank(2880, 100, 32, 8, 1800, 1864, 8, 8, pclk_fixed)
    dtd_75  = make_dtd_vblank(2880, 100, 32, 8, 1800, 1131, 8, 8, pclk_fixed)
    dtd_80  = make_dtd_vblank(2880, 100, 32, 8, 1800, 948,  8, 8, pclk_fixed)
    dtd_100 = make_dtd_vblank(2880, 100, 32, 8, 1800, 398,  8, 8, pclk_fixed)

    new_edid = bytearray(orig[:256])

    # In Block 0:
    # Keep DTD 1 (0x36..0x47) as Native 120Hz
    # Replace DTD 2 (0x5a..0x6b) with 60Hz
    new_edid[0x5a:0x5a+18] = dtd_60

    # In Block 1 (CTA-861 Extension):
    # DTD area begins at byte offset 30 in CTA block (global offset 0x9e = 128 + 30)
    # Clear DTD area (0x9e..0xfe)
    new_edid[0x9e:0xff] = bytes(0xff - 0x9e)
    dtds_b1 = [dtd_75, dtd_80, dtd_100]
    for i, d in enumerate(dtds_b1):
        pos = 0x9e + i * 18
        new_edid[pos:pos+18] = d

    # Recalculate checksums for both 128-byte blocks
    b0 = recalc_checksum(new_edid[0:128])
    b1 = recalc_checksum(new_edid[128:256])
    final_edid = b0 + b1

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(final_edid)

    print(f"[+] Successfully wrote custom EDID ({len(final_edid)} bytes) to: {output_path}")
    print(f"    Block 0 Checksum: 0x{b0[127]:02x} (Valid: {sum(b0) % 256 == 0})")
    print(f"    Block 1 Checksum: 0x{b1[127]:02x} (Valid: {sum(b1) % 256 == 0})")

if __name__ == "__main__":
    main()
