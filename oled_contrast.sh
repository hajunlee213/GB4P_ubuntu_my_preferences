#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) OLED 다크모드 대비 완화 설정 복원"
echo " (oled_contrast: 화이트포인트 감소 85~90% & 블랙 리프트 +2.0~2.5%)"
echo "========================================================="

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-oled-contrast.sh"
    exit 0
fi

# 1. OLED 맞춤 ICC 프로파일 및 oled-mode CLI 도구 복원
bash "${SCRIPT_DIR}/scripts/setup-oled-contrast.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] OLED 다크모드 대비 완화 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 맞춤형 OLED Eye Care ICC 프로파일 설치 완료:"
echo "    - oled_gentle_contrast.icc: 블랙 +2.0%, 화이트 90.0% (기본 활성화)"
echo "    - oled_medium_contrast.icc: 블랙 +2.5%, 화이트 85.0% (강한 대비 완화)"
echo "    - 위치: ~/.local/share/icc/"
echo " 2. VCGT (Video Card Gamma Table) 1:1:1 무왜곡 하드웨어 LUT:"
echo "    - 색 틴트 왜곡(보라/녹색 변색) 0% 완전 보존"
echo "    - 다크모드 극단적 명암비로 인한 눈부심 및 피로 대폭 감소"
echo "    - OLED 픽셀 완전 소등 회피로 스미어링(잔상/고스팅) 방지"
echo " 3. CLI 제어 명령어 'oled-mode' 제공:"
echo "    - oled-mode gentle : 자연스러운 대비 완화 (블랙 +2.0%, 화이트 90%) [추천]"
echo "    - oled-mode medium : 더 부드러운 대비 완화 (블랙 +2.5%, 화이트 85%)"
echo "    - oled-mode custom <블랙%> <화이트%> : 자유 튜닝 (예: oled-mode custom 2.0 92)"
echo "    - oled-mode reset  : 순정 공장 기본값(100% 화이트 / 0% 리얼블랙) 복원"
echo "    - oled-mode status : 현재 적용된 컬러 프로파일 확인"
echo "========================================================="
echo ""
echo " 🚀 언제든지 순정 상태로 원상 복구하려면 아래 명령을 실행하세요:"
echo "    ./oled_contrast.sh --restore"
echo "========================================================="
