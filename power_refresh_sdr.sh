#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 전원 연동 주사율 & sdr-native 설정 복원"
echo " (power_refresh_sdr: AC 80Hz VRR ↔ 배터리 60Hz VRR + sRGB 클램핑)"
echo "========================================================="

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-power-refresh-sdr.sh"
    exit 0
fi

# 1. 전원 연동 주사율 및 sdr-native daemon 복원
bash "${SCRIPT_DIR}/scripts/setup-power-refresh-sdr.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 전원 연동 주사율 & sdr-native 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 자동 주사율 동적 전환:"
echo "    - 🔌 AC(충전기 연결): 80Hz VRR 자동 적용 (부드러움과 저발열의 균형)"
echo "    - 🔋 DC(배터리 사용): 60Hz VRR 자동 적용 (OLED 배터리 소모 최소화)"
echo "    - 물리적 AC 연결(ADP1/sysfs) 직접 감지 (80% 배터리 보호 모드 완벽 호환)"
echo " 2. OLED 광색역 왜곡 방지 (sRGB 클램핑):"
echo "    - 주사율 변경, 부팅, 절전 모드 해제 시 항상 sdr-native (color-mode: 2) 자동 주입"
echo "    - P3 패널의 채도 과포화 현상 완벽 방지"
echo " 3. 무음 전환 및 무부하 설계:"
echo "    - Mutter DisplayConfig D-Bus TEMPORARY 호출로 '설정 유지' 확인 팝업 없음"
echo "    - UPower / logind 순수 이벤트 드리븐 방식 (CPU 점유율 0%)"
echo " 4. systemd 사용자 서비스:"
echo "    - 서비스명: power-refresh-sdr.service (부팅/로그인 시 자동 시작)"
echo "========================================================="
echo ""
echo " 🚀 유용한 명령어 안내:"
echo " 1. 서비스 상태 확인:"
echo "    systemctl --user status power-refresh-sdr.service"
echo ""
echo " 2. 실시간 동작 로그 확인:"
echo "    journalctl --user -u power-refresh-sdr.service -f"
echo ""
echo " 3. 원상 복구 (롤백):"
echo "    ./power_refresh_sdr.sh --restore"
echo "========================================================="
