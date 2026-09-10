#!/usr/bin/env bash
# ==============================================================================
# Disable P-core HT and P-core 2,3 (Dark Silicon) while enabling all 8 E-cores (2P+8E)
# ==============================================================================

# P-core HT (CPU 2, 4, 5, 7) OFF
echo 0 > /sys/devices/system/cpu/cpu2/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu4/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu5/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu7/online 2>/dev/null || true

# P-core 2 (CPU 3) & P-core 3 (CPU 6) OFF - 2P 체제 및 Dark Silicon 완충구역 생성 (발열 분산 및 피크온도 저감)
echo 0 > /sys/devices/system/cpu/cpu3/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu6/online 2>/dev/null || true

# Ensure all E-cores (CPU 8-15, Cluster 0 & 1) are online for high-efficiency multi-threading
for i in {8..15}; do
    echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null || true
done

# LP-E cores (CPU 16, 17) OFF - SoC 타일 인터커넥트 오버헤드 차단 및 Compute 타일(2P+8E) 단일화
echo 0 > /sys/devices/system/cpu/cpu16/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu17/online 2>/dev/null || true

# Restart power-profiles-daemon to refresh active CPU policy list after offlining cores
systemctl restart power-profiles-daemon 2>/dev/null || true
