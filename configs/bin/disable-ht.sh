#!/usr/bin/env bash
# ==============================================================================
# E-코어 8개 전용 아키텍처 및 P-코어 0번 식물인간 격리 세팅
# ==============================================================================

# P-코어 (CPU 1~7) OFF (CPU 0은 x86 BSP 커널 제약으로 하드웨어 상주)
for c in 1 2 3 4 5 6 7; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null || true
done

# E-코어 Cluster 0 & 1 (CPU 8~15, 8개 E-코어 전체) ON
for i in {8..15}; do
    echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null || true
done

# LP-E 코어 (CPU 16, 17) OFF - SoC 타일 인터커넥트 오버헤드 차단 및 Compute 타일 단일화
echo 0 > /sys/devices/system/cpu/cpu16/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu17/online 2>/dev/null || true

# CPU 0 식물인간 격리: 사용자 세션 슬라이스의 프로세스를 E-코어(8-15)로 전량 제한
systemctl set-property user.slice AllowedCPUs=8-15 2>/dev/null || true
systemctl set-property user-1000.slice AllowedCPUs=8-15 2>/dev/null || true

# Intel Meteor Lake Workload Type Hints 활성화
if [ -f /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable ]; then
    echo 1 > /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable 2>/dev/null || true
fi

# Restart power-profiles-daemon to refresh active CPU policy list after offlining cores
systemctl restart power-profiles-daemon 2>/dev/null || true
