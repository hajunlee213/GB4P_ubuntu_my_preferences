#!/usr/bin/env bash
# ==============================================================================
# E-코어 8개 전담 + CPU 0번 LPE(1.2GHz) 백그라운드/오디오/IRQ 전담 토폴로지 세팅
# ==============================================================================

# 1. P-코어 (CPU 1~7) OFF (CPU 0은 x86 BSP 커널 제약으로 하드웨어 상주)
for c in 1 2 3 4 5 6 7; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null || true
done

# 2. E-코어 Cluster 0 & 1 (CPU 8~15, 8개 E-코어 전체) ON
for i in {8..15}; do
    echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null || true
done

# 3. LP-E 코어 (CPU 16, 17) OFF - SoC 타일 패브릭 오버헤드 차단 및 Compute 타일 단일화
echo 0 > /sys/devices/system/cpu/cpu16/online 2>/dev/null || true
echo 0 > /sys/devices/system/cpu/cpu17/online 2>/dev/null || true

# 4. CPU 0 터보 차단 및 1.2GHz 베이스 클럭 락 (LPE 저전력 에뮬레이션)
echo 1200000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true
echo power > /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || true

# 5. cgroups v2 계층 슬라이스 분리
# - OS 시스템 데몬 및 PID 1은 CPU 0에 전담
systemctl set-property system.slice AllowedCPUs=0 2>/dev/null || true
systemctl set-property init.scope AllowedCPUs=0 2>/dev/null || true
# - 사용자 세션(모든 앱, 브라우저, 렌더러)은 8E 코어(8~15)로 완전 격리
systemctl set-property user.slice AllowedCPUs=8-15 2>/dev/null || true
systemctl set-property user-1000.slice AllowedCPUs=8-15 2>/dev/null || true

# 6. 하드웨어 인터럽트(IRQ) CPU 0 직결 (AudioDSP & Wi-Fi iwlwifi 큐)
for irq in $(grep -Ei "iwlwifi|snd|sof|audio" /proc/interrupts 2>/dev/null | awk '{print $1}' | tr -d ':'); do
    [ -f "/proc/irq/$irq/smp_affinity_list" ] && echo 0 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
done

# 7. 사용자 세션 오디오 데몬 CPU 0 핀포인트 차출 (taskset -cp 0)
for proc in pipewire wireplumber pipewire-pulse; do
    for pid in $(pgrep -f "$proc" 2>/dev/null); do
        taskset -cp 0 "$pid" 2>/dev/null || true
    done
done

# 8. Intel Meteor Lake Workload Type Hints 활성화
if [ -f /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable ]; then
    echo 1 > /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable 2>/dev/null || true
fi

# 9. 코어 오프라인 정책 갱신을 위해 power-profiles-daemon 재시작
systemctl restart power-profiles-daemon 2>/dev/null || true
