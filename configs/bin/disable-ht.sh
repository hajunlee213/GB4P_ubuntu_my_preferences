#!/usr/bin/env bash
# ==============================================================================
# Disable P-core HT and E-core Cluster 0 (CPU 8-11) for thermal/power efficiency
# ==============================================================================

# P-core HT (CPU 2, 4, 5, 7) OFF
echo 0 > /sys/devices/system/cpu/cpu2/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu4/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu5/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu7/online 2>/dev/null || true

# P-core 2 (CPU 3) & P-core 3 (CPU 6) OFF - 2P 체제 및 Dark Silicon 완충구역 생성 (발열 분산 및 피크온도 저감)
echo 0 > /sys/devices/system/cpu/cpu3/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu6/online 2>/dev/null || true

# Ensure E-core cluster 1 (CPU 12-15, outer die) is online
echo 1 > /sys/devices/system/cpu/cpu12/online 2>/dev/null || true
echo 1 > /sys/devices/system/cpu/cpu13/online 2>/dev/null || true
echo 1 > /sys/devices/system/cpu/cpu14/online 2>/dev/null || true
echo 1 > /sys/devices/system/cpu/cpu15/online 2>/dev/null || true

# Disable E-core cluster 0 (CPU 8-11, adjacent to P-cores) for thermal distribution
echo 0 > /sys/devices/system/cpu/cpu8/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu9/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu10/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu11/online 2>/dev/null || true

# LP-E cores (CPU 16, 17) - left enabled
#echo 0 > /sys/devices/system/cpu/cpu16/online
#echo 0 > /sys/devices/system/cpu/cpu17/online

# Restart power-profiles-daemon to refresh active CPU policy list after offlining cores
systemctl restart power-profiles-daemon 2>/dev/null || true
