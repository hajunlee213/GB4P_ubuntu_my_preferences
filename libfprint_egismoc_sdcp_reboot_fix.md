# libfprint Egis SDCP Full Fix Patch (Version 2)

## Overview
This patch provides the comprehensive fix for Samsung Galaxy Book 4 Pro / Ultra (and other Egis `1c7a:05a1` sensors) to solve:
1. Enrolled fingerprints being lost/rejected after system reboot.
2. `fprintd` daemon crashing when fingerprint identification is cancelled or interrupted.
3. Fingerprint reader freezing or failing with `65 E0` error after screen lock, sleep, or USB power-down.

Detailed version history is documented in `usable_SDCP_versions_README.md`.

---

## Root Causes & Issues

1. **Host Key Drop on Reboot**:
   - The upstream SDCP driver drops the cached `boot_id` upon reboot, throwing away the Linux `host_public_key` and generating a new one.
   - The Egis sensor binds enrolled fingerprints to the `host_public_key`. When the key changes, the sensor considers the host unknown and hides/clears the fingerprints.
2. **fprintd Daemon Crash on Cancel**:
   - When fingerprint recognition is cancelled (e.g. timeout, user cancellation, screen off), the driver fails to clear its internal state machine (`task_ssm`).
   - The next request hits an assert or invalid state, causing `fprintd` to crash.
3. **Session Amnesia on Sleep/Lock Screen (`65 E0`)**:
   - The sensor hardware drops its volatile session during USB power-save or sleep.
   - Reusing `is_connected = TRUE` leads to protocol mismatch and `65 E0` error.
4. **24-Hour Expiration**:
   - Hardcoded 86400s timer discards session claims after 24 hours.

---

## The Version 2 Fix (`libfprint_egismoc_full_fix.patch`)

1. **`libfprint/drivers/egismoc/egismoc.c`**:
   - Cleans up `task_ssm` in `egismoc_close()` (`fpi_ssm_free(self->task_ssm); self->task_ssm = NULL;`) to eliminate daemon crashes.
   - Sets `claim_expiration_seconds = -1` (infinite) so session keys do not expire after 24 hours.
2. **`libfprint/fpi-sdcp-device.c`**:
   - Prevents discarding cached host keys when `boot_id` changes.
   - Forces `priv->is_connected = FALSE` on claim load so that whenever `fprintd` wakes up (e.g. unlocking screen), it retains the preserved Host Key and negotiates a fresh secure session (`SDCP Connect`).

---

## Quick Install (Recommended)

Use the repository's one-click restore script:
```bash
sudo ./fingerprint_setup.sh
```

---

## Manual Build & Installation

```bash
git clone https://github.com/TenSeventy7/libfprint-egismoc-sdcp.git
cd libfprint-egismoc-sdcp

# Link OpenSSL for egismoc
sed -i "/'uru4000' : \[ 'openssl' \],/a\\    'egismoc' : [ 'openssl' ]," meson.build

# Apply the Version 2 patch
git apply /path/to/GB4P_ubuntu_my_preferences/libfprint_egismoc_full_fix.patch

# Clean old claims
sudo rm -f /var/lib/fprint/sdcp-claim-*

# Build & install
meson setup builddir -Ddrivers=egismoc -Ddoc=false -Dgtk-examples=false --prefix=/usr/local
ninja -C builddir
sudo ninja -C builddir install
sudo ldconfig
sudo systemctl restart fprintd
```
