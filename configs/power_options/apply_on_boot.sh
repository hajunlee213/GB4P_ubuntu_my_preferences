#!/usr/bin/env bash
# ==============================================================================
# 부팅 시 자동 실행 스크립트 (Startup Power Settings)
# ==============================================================================
# - 부팅 시 현재 충전기(AC) 연결 여부를 감지하여 적절한 전원 모드 자동 적용
#   - AC 연결 시 : 2번 밸런스 터보 (터보 ON / 65%, EPP: balance_performance) + Balanced
#   - DC 배터리 시 : 터보 OFF / 100% 베이스 클럭 (P: 2.0GHz / 8E: 1.0GHz, EPP: power) + Balanced
#   - CPU 토폴로지 : 2P + 8E 체제 (총 10코어 활성, P-HT/DarkSilicon/LP-E 차단)
# ==============================================================================

LOGFILE="/tmp/power_options_boot.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Power Options Auto-Apply..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. GNOME 전원 데몬 및 세션 로딩 대기 (3초)
sleep 3

# 2. 현재 전원 상태(AC vs DC) 감지 및 모드 자동 적용
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detecting AC/DC state and applying power profile..."
"$DIR/handle_power_change.sh"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-Apply finished successfully."
