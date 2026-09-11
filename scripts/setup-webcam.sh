#!/usr/bin/env bash
# ==============================================================================
# scripts/setup-webcam.sh
# 갤럭시 북4 프로(NT960XGK / Meteor Lake) 웹캠 드라이버 & Relay 종합 복원 서브 스크립트
#
# 해결 항목:
#  1. 26MHz 클록 에러: ov02c10-26mhz-fix DKMS 설치
#  2. 180도 뒤집힘 문제: ipu-bridge-fix (v1.4) DKMS 설치 (DMI 기반 센서 180도 고정)
#  3. 크롬/브라우저 인식: v4l2loopback exclusive_caps=1 + udev 캡처 강제 + 원시 노드 은닉
#  4. 부팅 복불복 켜짐: IPU6 펌웨어 initramfs(dracut/initramfs-tools) 사전 번들링
#  5. 전력/발열 최적화: On-Demand camera-relay user service 구성
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/configs/webcam"

# 실행 사용자 판별 (sudo 환경 지원)
ACTUAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo "[*] 갤럭시 북4 프로 웹캠 원클릭 복원을 시작합니다..."
echo "    - 대상 사용자: ${ACTUAL_USER} (${USER_HOME})"
echo "    - 프로젝트 경로: ${PROJECT_ROOT}"

# ------------------------------------------------------------------------------
# [1/10] 필수 빌드 도구 및 라이브러리 의존성 설치
# ------------------------------------------------------------------------------
echo ""
echo "[1/10] 필수 의존성 패키지 확인 및 설치 중..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# 빌드 및 런타임 필수 패키지 목록
# - libdbus-1-dev, libsystemd-dev: PipeWire SPA / Meson 빌드 필수 의존성 (누락 시 빌드 중단)
# - v4l2loopback-dkms, v4l-utils: 가상 웹캠 디바이스 및 제어 도구
# - gstreamer1.0-tools, plugins: libcamerasrc -> v4l2sink 릴레이 파이프라인
# - zstd: 커널 펌웨어 decompress용
REQUIRED_PKGS=(
    build-essential
    cmake
    meson
    ninja-build
    git
    pkg-config
    dkms
    v4l2loopback-dkms
    v4l-utils
    gstreamer1.0-tools
    gstreamer1.0-plugins-base
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
    libdbus-1-dev
    libsystemd-dev
    libevent-dev
    libyaml-dev
    libdrm-dev
    libjpeg-dev
    libtiff-dev
    python3-yaml
    python3-ply
    zstd
)

# 커널 헤더 설치
KERNEL_VER="$(uname -r)"
if apt-cache show "linux-headers-${KERNEL_VER}" &>/dev/null; then
    REQUIRED_PKGS+=("linux-headers-${KERNEL_VER}")
else
    REQUIRED_PKGS+=("linux-headers-generic")
fi

echo "  -> 패키지 설치 진행..."
apt-get install -y --no-install-recommends "${REQUIRED_PKGS[@]}"

# IPU6 OEM 패키지 (Ubuntu 저장소에 제공되는 경우 추가 설치)
for oem_pkg in libcamhal0 libcamhal-ipu6 gstreamer1.0-icamera; do
    if apt-cache show "$oem_pkg" &>/dev/null; then
        apt-get install -y --no-install-recommends "$oem_pkg" || true
    fi
done

echo "  ✓ 필수 패키지 설치 완료"

# ------------------------------------------------------------------------------
# [2/10] IPU6 펌웨어 initramfs 번들링 (부팅 복불복 레이스 컨디션 해결)
# ------------------------------------------------------------------------------
echo ""
echo "[2/10] IPU6 펌웨어 initramfs 번들링 설정 중..."

# 펌웨어 .zst 압축 해제 (.bin 파일 생성)
IPU_FW_DIR="/lib/firmware/intel/ipu"
if [ -d "$IPU_FW_DIR" ]; then
    for zst in "$IPU_FW_DIR"/ipu6epmtl_fw.bin*.zst; do
        if [ -f "$zst" ]; then
            bin_file="${zst%.zst}"
            if [ ! -f "$bin_file" ]; then
                echo "  -> 펌웨어 압축 해제: $(basename "$bin_file")"
                zstd -d -k -q "$zst" -o "$bin_file" || true
            fi
        fi
    done
fi

# dracut 환경인 경우
NEEDS_INITRAMFS_REBUILD=0
if [ -d /etc/dracut.conf.d ]; then
    echo "  -> Dracut 펌웨어 번들 설정 복사 (/etc/dracut.conf.d/ipu6-firmware.conf)"
    cp "${CONFIG_DIR}/dracut/ipu6-firmware.conf" /etc/dracut.conf.d/ipu6-firmware.conf
    chmod 644 /etc/dracut.conf.d/ipu6-firmware.conf
    NEEDS_INITRAMFS_REBUILD=1
fi

# initramfs-tools 환경 호환성
if [ -d /etc/initramfs-tools/hooks ]; then
    cat << 'EOF' > /etc/initramfs-tools/hooks/ipu6-firmware
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in
prereqs) prereqs; exit 0;;
esac
. /usr/share/initramfs-tools/hook-functions
for fw in /lib/firmware/intel/ipu/ipu6epmtl_fw.bin*; do
    [ -f "$fw" ] && copy_file firmware "$fw"
done
EOF
    chmod 755 /etc/initramfs-tools/hooks/ipu6-firmware
    NEEDS_INITRAMFS_REBUILD=1
fi

echo "  ✓ IPU6 펌웨어 램디스크 번들링 구성 완료"

# ------------------------------------------------------------------------------
# [3/10] 26MHz 센서 클록 패치 (ov02c10-26mhz-fix DKMS)
# ------------------------------------------------------------------------------
echo ""
echo "[3/10] 26MHz 센서 클록 패치 (ov02c10 DKMS) 설치 중..."

OV02C10_SRC="/usr/src/ov02c10-1.0"
if [ ! -d "$OV02C10_SRC" ] || [ ! -f "$OV02C10_SRC/ov02c10.c" ]; then
    mkdir -p "$OV02C10_SRC"
    cp -r "${CONFIG_DIR}/dkms/ov02c10-1.0/"* "$OV02C10_SRC/"
fi

# dkms 등록 및 빌드
if ! dkms status ov02c10/1.0 2>/dev/null | grep -q "installed"; then
    echo "  -> ov02c10/1.0 DKMS 등록 및 빌드..."
    dkms remove ov02c10/1.0 --all 2>/dev/null || true
    dkms add ov02c10/1.0 2>/dev/null || true
    dkms build ov02c10/1.0
    dkms install ov02c10/1.0
fi
echo "  ✓ ov02c10 26MHz DKMS 패치 완료"

# ------------------------------------------------------------------------------
# [4/10] 180도 뒤집힘 방지 (ipu-bridge-fix DKMS)
# ------------------------------------------------------------------------------
echo ""
echo "[4/10] 180도 센서 회전 보정 (ipu-bridge-fix DKMS) 설치 중..."

IPU_BRIDGE_SRC="/usr/src/ipu-bridge-fix-1.4"
if [ ! -d "$IPU_BRIDGE_SRC" ] || [ ! -f "$IPU_BRIDGE_SRC/ipu-bridge.c" ]; then
    mkdir -p "$IPU_BRIDGE_SRC"
    cp -r "${CONFIG_DIR}/dkms/ipu-bridge-fix-1.4/"* "$IPU_BRIDGE_SRC/"
fi

if ! dkms status ipu-bridge-fix/1.4 2>/dev/null | grep -q "installed"; then
    echo "  -> ipu-bridge-fix/1.4 DKMS 등록 및 빌드..."
    dkms remove ipu-bridge-fix/1.4 --all 2>/dev/null || true
    dkms add ipu-bridge-fix/1.4 2>/dev/null || true
    dkms build ipu-bridge-fix/1.4
    dkms install ipu-bridge-fix/1.4
fi

# 상위 커널 머지 감지 자동 제거 서비스 설치
cp "${CONFIG_DIR}/sbin/ipu-bridge-check-upstream.sh" /usr/local/sbin/ipu-bridge-check-upstream.sh
chmod 755 /usr/local/sbin/ipu-bridge-check-upstream.sh
cp "${CONFIG_DIR}/systemd/ipu-bridge-check-upstream.service" /etc/systemd/system/ipu-bridge-check-upstream.service
chmod 644 /etc/systemd/system/ipu-bridge-check-upstream.service
systemctl daemon-reload
systemctl enable ipu-bridge-check-upstream.service 2>/dev/null || true

echo "  ✓ ipu-bridge-fix 180도 보정 DKMS 설치 완료"

# ------------------------------------------------------------------------------
# [5/10] IVSC 센서 버스 및 v4l2loopback 모듈 설정
# ------------------------------------------------------------------------------
echo ""
echo "[5/10] IVSC 버스 및 v4l2loopback 모듈 로드/파라미터 설정 중..."

mkdir -p /etc/modprobe.d /etc/modules-load.d

# modprobe 설정 복사
cp "${CONFIG_DIR}/modprobe.d/99-camera-relay-loopback.conf" /etc/modprobe.d/99-camera-relay-loopback.conf
cp "${CONFIG_DIR}/modprobe.d/ivsc-camera.conf" /etc/modprobe.d/ivsc-camera.conf

# 부팅 자동 로드 설정 복사
cp "${CONFIG_DIR}/modules-load.d/v4l2loopback.conf" /etc/modules-load.d/v4l2loopback.conf
cp "${CONFIG_DIR}/modules-load.d/ivsc.conf" /etc/modules-load.d/ivsc.conf

chmod 644 /etc/modprobe.d/99-camera-relay-loopback.conf \
          /etc/modprobe.d/ivsc-camera.conf \
          /etc/modules-load.d/v4l2loopback.conf \
          /etc/modules-load.d/ivsc.conf

echo "  ✓ modprobe.d 및 modules-load.d 설정 완료"

# ------------------------------------------------------------------------------
# [6/10] udev 룰 등록 (Chromium 웹캠 인식 & 원시 노드 은닉 & 접근 권한)
# ------------------------------------------------------------------------------
echo ""
echo "[6/10] udev 룰 등록 및 비디오 권한 부여 중..."

mkdir -p /etc/udev/rules.d
cp "${CONFIG_DIR}/udev/70-camera-relay-capabilities.rules" /etc/udev/rules.d/70-camera-relay-capabilities.rules
cp "${CONFIG_DIR}/udev/90-hide-ipu6-v4l2.rules" /etc/udev/rules.d/90-hide-ipu6-v4l2.rules
cp "${CONFIG_DIR}/udev/99-ipu6.rules" /etc/udev/rules.d/99-ipu6.rules

chmod 644 /etc/udev/rules.d/70-camera-relay-capabilities.rules \
          /etc/udev/rules.d/90-hide-ipu6-v4l2.rules \
          /etc/udev/rules.d/99-ipu6.rules

# 사용자를 video 그룹에 추가
usermod -aG video "$ACTUAL_USER"

# udev 규칙 즉시 리로드
udevadm control --reload-rules
udevadm trigger

echo "  ✓ udev 룰 적용 및 ${ACTUAL_USER} 계정 video 그룹 등록 완료"

# ------------------------------------------------------------------------------
# [7/10] 환경변수 등록 (/etc/environment)
# ------------------------------------------------------------------------------
echo ""
echo "[7/10] GStreamer 및 라이브러리 환경변수 설정 (/etc/environment)..."

ENV_FILE="/etc/environment"
if [ -f "$ENV_FILE" ]; then
    if ! grep -q "GST_PLUGIN_PATH" "$ENV_FILE"; then
        echo 'GST_PLUGIN_PATH="/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0"' >> "$ENV_FILE"
    fi
    if ! grep -q "LD_LIBRARY_PATH" "$ENV_FILE"; then
        echo 'LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/local/lib"' >> "$ENV_FILE"
    fi
fi
echo "  ✓ /etc/environment 환경변수 설정 완료"

# ------------------------------------------------------------------------------
# [8/10] libcamera 빌드 및 센서 튜닝 배포
# ------------------------------------------------------------------------------
echo ""
echo "[8/10] libcamera 확인 및 센서 튜닝(ov02c10.yaml) 배포 중..."

mkdir -p /usr/local/share/libcamera/ipa/simple
cp "${CONFIG_DIR}/ipa/ov02c10.yaml" /usr/local/share/libcamera/ipa/simple/ov02c10.yaml
chmod 644 /usr/local/share/libcamera/ipa/simple/ov02c10.yaml

# libcamera가 이미 소스 빌드되어 설치되어 있는지 확인
if ! [ -f /usr/local/lib/x86_64-linux-gnu/libcamera.so.0.7 ] && ! [ -f /usr/local/lib/x86_64-linux-gnu/libcamera.so.0.5 ]; then
    echo "  -> 시스템에 소스 빌드된 libcamera가 없습니다."
    echo "  -> Andycodeman 공식 libcamera 자동 빌드를 시도합니다..."
    BUILD_TMP="/tmp/libcamera-build"
    rm -rf "$BUILD_TMP"
    git clone --depth 1 --branch "v0.7.0" https://git.libcamera.org/libcamera/libcamera.git "$BUILD_TMP" || true
    if [ -d "$BUILD_TMP" ]; then
        cd "$BUILD_TMP"
        # OV02C10 센서 헬퍼 패치 주입
        HELPER_FILE="src/ipa/libipa/camera_sensor_helper.cpp"
        if [ -f "$HELPER_FILE" ] && ! grep -q "CameraSensorHelperOv02c10" "$HELPER_FILE"; then
            sed -i '/#endif.*__DOXYGEN__/i\
class CameraSensorHelperOv02c10 : public CameraSensorHelper\
{\
public:\
\tCameraSensorHelperOv02c10()\
\t{\
\t\tgain_ = AnalogueGainLinear{ 1, 0, 0, 16 };\
\t}\
};\
REGISTER_CAMERA_SENSOR_HELPER("ov02c10", CameraSensorHelperOv02c10)\
' "$HELPER_FILE"
        fi
        meson setup build \
            --prefix=/usr/local \
            --libdir=lib/x86_64-linux-gnu \
            -Dpipelines=simple \
            -Dipas=simple \
            -Dgstreamer=enabled \
            -Dv4l2=false \
            -Dcam=disabled \
            -Dqcam=disabled \
            -Ddocumentation=disabled \
            -Dpycamera=disabled \
            -Dtest=false
        ninja -C build install
        ldconfig
        rm -rf "$BUILD_TMP"
        echo "  ✓ libcamera v0.7.0 빌드 및 설치 완료"
    else
        echo "  [!] libcamera git 클론 실패. 시스템 패키지를 사용합니다."
    fi
else
    echo "  ✓ 이미 최적화된 libcamera 빌드가 설치되어 있습니다."
fi

# ------------------------------------------------------------------------------
# [9/10] camera-relay 및 camera-relay-monitor 설치
# ------------------------------------------------------------------------------
echo ""
echo "[9/10] On-Demand Camera Relay 바이너리 설치 중..."

# C 모니터 컴파일
gcc -O2 "${CONFIG_DIR}/camera-relay/camera-relay-monitor.c" -o /usr/local/bin/camera-relay-monitor
chmod 755 /usr/local/bin/camera-relay-monitor

# 메인 릴레이 스크립트 복사
cp "${CONFIG_DIR}/camera-relay/camera-relay" /usr/local/bin/camera-relay
chmod 755 /usr/local/bin/camera-relay

echo "  ✓ /usr/local/bin/camera-relay & camera-relay-monitor 설치 완료"

# ------------------------------------------------------------------------------
# [10/10] On-Demand camera-relay user service 등록 및 initramfs 빌드
# ------------------------------------------------------------------------------
echo ""
echo "[10/10] On-Demand camera-relay 서비스 등록 및 initramfs 갱신 중..."

USER_SERVICE_DIR="${USER_HOME}/.config/systemd/user"
mkdir -p "$USER_SERVICE_DIR"
cp "${CONFIG_DIR}/systemd-user/camera-relay.service" "${USER_SERVICE_DIR}/camera-relay.service"
chown -R "${ACTUAL_USER}:${ACTUAL_USER}" "${USER_HOME}/.config/systemd"
chmod 644 "${USER_SERVICE_DIR}/camera-relay.service"

# 사용자 systemd 서비스 활성화
if command -v systemctl &>/dev/null; then
    su - "$ACTUAL_USER" -c "systemctl --user daemon-reload && systemctl --user enable camera-relay.service" 2>/dev/null || true
fi

# initramfs 갱신 (부팅 펌웨어 번들링 확정)
if [ "$NEEDS_INITRAMFS_REBUILD" -eq 1 ]; then
    echo "  -> initramfs 램디스크 갱신 중 (약 10~20초 소요)..."
    if command -v dracut &>/dev/null; then
        dracut -f --quiet || true
    elif command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all || true
    fi
    echo "  ✓ initramfs 갱신 완료"
fi

echo ""
echo "========================================================="
echo " [SUCCESS] 웹캠 드라이버 및 On-Demand Relay 복원 완료!"
echo "========================================================="
echo " 1. 26MHz 클록 에러 해결 (ov02c10 DKMS)"
echo " 2. 180도 뒤집힘 하드웨어 보정 (ipu-bridge-fix DKMS)"
echo " 3. 크롬/엣지 웹캠 인식 (exclusive_caps=1 + udev 캡처 강제)"
echo " 4. 부팅 복불복 방지 (IPU6 펌웨어 initramfs 탑재)"
echo " 5. On-Demand 전력 최적화 (camera-relay user service)"
echo "========================================================="
