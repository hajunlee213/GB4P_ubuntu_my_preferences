# libfprint Egis SDCP Reboot Fix Patch

## Overview
This patch fixes the issue on Samsung Galaxy Book 4 Pro (and other Egis `1c7a:05a1` sensors) where fingerprints enrolled in Linux are lost or rejected after a system reboot.

## The Root Cause
1. The original SDCP code drops the cached `boot_id` upon reboot, which causes it to throw away the Linux `host_public_key` and generate a new one.
2. The Egis sensor binds enrolled fingerprints to the `host_public_key`. When the key changes on every boot, the sensor treats the Linux machine as a new host and hides the fingerprints.
3. The sensor's active session is volatile. It requires an `SDCP Connect` command after every power cycle to establish a new session.

## The Fix
This patch modifies:
- `libfprint/fpi-sdcp-device.c`: Prevents the driver from discarding the `host_public_key` on reboot, while explicitly setting `is_connected = FALSE` so that the driver is forced to negotiate a new session (`SDCP Connect`) using the preserved key.
- `libfprint/drivers/egismoc/egismoc.c`: Sets the SDCP claim expiration to `-1` (infinite) so the keys do not expire after 24 hours.

## How to Apply
```bash
cd /path/to/libfprint-egismoc-sdcp
git apply /path/to/libfprint_egismoc_sdcp_reboot_fix.patch
sudo rm -f /var/lib/fprint/sdcp-claim-*
sudo ninja -C builddir
sudo meson install -C builddir
sudo systemctl restart fprintd
```
