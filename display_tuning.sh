#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 디스플레이 다중 주사율 설정 복원"
echo " (display_tuning: 60Hz, 75Hz, 80Hz, 100Hz, 120Hz EDID)"
echo "========================================================="

# root 권한 확인 및 자동 승격
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-display-edid.sh"
    exit 0
fi

# 1. 커스텀 EDID 및 부팅 설정(initramfs, GRUB) 복원
bash "${SCRIPT_DIR}/scripts/setup-display-edid.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 디스플레이 다중 주사율 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 커스텀 EDID 바이너리 설치:"
echo "    - /lib/firmware/edid/gb4p_custom_edid.bin"
echo "    - 2880x1800 고정 픽셀 클럭(655.13 MHz) 및 V-Blank 확장 방식"
echo "    - 지원 주사율: 60Hz, 75Hz, 80Hz, 100Hz, 120Hz (VRR 48~120Hz 및 HDR 유지)"
echo " 2. 부팅 램디스크(initramfs / dracut) 패키징 완료 (Early KMS 로드)"
echo " 3. GRUB 커널 파라미터 등록 (drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin)"
echo "========================================================="
echo ""
echo " 🚀 필수 안내:"
echo " 1. 설정을 시스템에 완전히 적용하려면 재부팅이 필요합니다:"
echo "    sudo reboot"
echo ""
echo " 2. 재부팅 후 우분투 '설정(Settings)' -> '디스플레이(Displays)' ->"
echo "    '주사율(Refresh Rate)' 드롭다운에서 60Hz, 80Hz 등을 선택할 수 있습니다."
echo ""
echo " 3. 언제든지 설정을 순정(120Hz)으로 되돌리려면 아래 명령을 실행하세요:"
echo "    sudo ./display_tuning.sh --restore"
echo "========================================================="
