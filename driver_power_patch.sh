#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 드라이버 패치 & 전력 최적화 복원"
echo " (driver_power_patch: Intel Xe, Microcode, OpenCL, ASPM, PowerTOP)"
echo "========================================================="

# root 권한 확인 및 자동 승격
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-driver-power-patch.sh"
    exit 0
fi

# 1. 드라이버 및 전력 최적화 설정 적용
bash "${SCRIPT_DIR}/scripts/setup-driver-power-patch.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 드라이버 패치 및 전력 최적화 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 인텔 CPU 마이크로코드 & 써멀 관리:"
echo "    - intel-microcode: 최신 CPU 마이크로코드 보안/안정성 패치"
echo "    - thermald: 하드웨어 맞춤형 써멀 스로틀링 완화 데몬 활성화"
echo " 2. 차세대 Intel Xe 그래픽 드라이버 전환 (i915 -> xe):"
echo "    - i915의 ACPI 부팅 타이밍 레이스 컨디션 및 PSR 프리징 해결"
echo "    - Early KMS dracut 탑재: force_drivers+=\" i915 xe \""
echo "    - 커널 파라미터: i915.force_probe=!7d55 xe.force_probe=7d55"
echo "    - SOF 스피커 오디오 자동 바인딩 및 OLED 다중 주사율 호환 보장"
echo " 3. GPU 하드웨어 연산 가속 (OpenCL Compute Runtime):"
echo "    - intel-opencl-icd & clinfo 탑재 (Arc Xe-LPG GPU 연산 가속 활성화)"
echo " 4. PCIe ASPM 초절전 정책 강제 활성화:"
echo "    - 커널 파라미터: pcie_aspm.policy=powersupersave"
echo "    - NVMe SSD / 무선랜 PCIe 링크 L1.1/L1.2 서브스테이트 진입 보장"
echo "    - CPU 패키지 초저전력 C-state (C10) 진입률 극대화"
echo " 5. PowerTOP Auto-Tune 백그라운드 서비스:"
echo "    - /etc/systemd/system/powertop.service (부팅 시 자동 실행)"
echo "    - 모든 PCI/USB 버스 컨트롤러 Runtime PM 자동 절전(auto) 전환"
echo " 6. 커널 인터럽트 타이머 절전:"
echo "    - /etc/sysctl.d/99-nmi-watchdog.conf: kernel.nmi_watchdog = 0"
echo "========================================================="
echo ""
echo " 🚀 필수 안내:"
echo " 1. 커널 드라이버(xe) 및 PCIe ASPM 설정을 시스템에 완전히 적용하려면"
echo "    재부팅이 필요합니다:"
echo "    sudo reboot"
echo ""
echo " 2. 재부팅 후 적용 상태 확인 명령어:"
echo "    - 그래픽 드라이버 확인: lsmod | grep xe"
echo "    - GPU 연산 드라이버 확인: clinfo -l"
echo "    - ASPM 절전 정책 확인: cat /sys/module/pcie_aspm/parameters/policy"
echo "    - PowerTOP 서비스 확인: systemctl status powertop.service"
echo ""
echo " 3. 언제든지 설정을 순정(기본 i915 드라이버)으로 되돌리려면 아래 명령을 실행하세요:"
echo "    sudo ./driver_power_patch.sh --restore"
echo "========================================================="
