#!/usr/bin/env bash
set -euo pipefail

echo "=== Egis SDCP 패치 드라이버 순정 롤백 시작 ==="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

LIB_DIR="/usr/local/lib/x86_64-linux-gnu"

echo "-> /usr/local/lib 내 커스텀 libfprint 파일 제거..."
rm -f "${LIB_DIR}/libfprint-2.so"*

echo "-> ldconfig 갱신..."
ldconfig

echo "-> SDCP 캐시 정리 및 fprintd 재시작..."
rm -f /var/lib/fprint/sdcp-claim-*
systemctl restart fprintd.service || true

echo "[SUCCESS] 순정 libfprint 드라이버로 원상 복구 완료!"
