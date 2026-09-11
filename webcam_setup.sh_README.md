# webcam_setup.sh 설명 문서

이 문서는 **[`webcam_setup.sh`](./webcam_setup.sh)** 스크립트가 적용하는 삼성 갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK / Meteor Lake)의 **인텔 IPU6 웹캠 드라이버 안정화, 180도 센서 뒤집힘 하드웨어 보정, 크롬/브라우저 웹캠 인식, 부팅 복불복(레이스 컨디션) 방지, 그리고 초절전 On-Demand Relay 서비스**의 동작 원리와 복원/롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 하드웨어 특성

갤럭시 북4 프로(NT960XGK, 인텔 Core Ultra 5 125H)의 웹캠은 일반적인 USB UVC 웹캠이 아니며, 인텔 MIPI CSI-2 기반의 **IPU6(Image Processing Unit 6 / IPU6EP-MTL)**과 **OmniVision OV02C10** 센서, 그리고 **IVSC(Intel Visual Sensing Controller)** 버스로 연결되어 있습니다.

이 하드웨어 구성은 순정 우분투에서 다음과 같은 5가지 치명적인 문제를 일으킵니다:

### (1) 센서 180도 뒤집힘 (거꾸로 나오는 화면)
* **원인**: 삼성 갤럭시 북3/북4 기종은 하드웨어 기구 설계 상 `ov02c10` 웹캠 센서가 180도 거꾸로 뒤집혀 실장되어 있습니다. 정상적인 시스템이라면 메인보드 BIOS ACPI 테이블에 센서 회전 각도가 `180`으로 명시되어야 하나, **삼성 BIOS는 이를 `rotation = 0`으로 잘못 보고**합니다.
* **과거 소프트웨어 해결책의 한계**:
  * 과거 커뮤니티나 블로그(예: dev_hammy 등)에서는 GStreamer 파이프라인에서 `videoflip method=rotate-180` 요소를 추가하여 화면을 회전시키는 방식을 사용했습니다.
  * 그러나 이 방식은 특정 커맨드라인 뷰어에서만 작동할 뿐, **크롬, 파이어폭스, 엣지, 줌, 디스코드, 웹엑스 등 시스템 일반 웹 브라우저 및 화상회의 앱에서는 화면이 여전히 180도 거꾸로 출력**되는 치명적인 한계가 있었습니다.
* **근본적 해결책: `ipu-bridge-fix` (v1.4) DKMS**:
  * 리눅스 커널의 `ipu-bridge` 드라이버는 DMI 테이블을 기반으로 노트북별 센서 특성을 교정하는 쿼크(Quirk) 기능을 가지고 있습니다.
  * Andycodeman 레포의 `ipu-bridge-fix` DKMS 모듈은 갤럭시 북 DMI 모델명(`960XGK`, `940XGK`, `960XFG` 등)을 커널 쿼크 테이블에 등록합니다.
  * 따라서 **커널 및 libcamera 드라이버 계층에서 센서 orientation을 하드웨어 수준에서 180도로 고정**하므로, 브라우저나 디스코드, Cheese 등 시스템 전역의 모든 애플리케이션에서 별도의 필터 없이 완벽하게 바른 방향으로 표시됩니다.

### (2) 크롬/엣지(Chromium 계열) 웹캠 미인식 (`exclusive_caps=1`)
* **원인**: 리눅스 가상 비디오 드라이버인 `v4l2loopback`은 기본적으로 프레임을 캡처하는 기능(`CAPTURE`)과 외부에서 프레임을 주입받는 기능(`OUTPUT`)을 동시에 보고합니다. 파이어폭스는 이를 용인하지만, Chromium 계열 브라우저(Chrome, Edge, Brave 등)는 보안 및 디바이스 사양 엄격성으로 인해 OUTPUT 기능이 섞여 있는 비디오 노드를 웹캠 목록에서 완전히 배제합니다.
* **해결책**:
  * `/etc/modprobe.d/99-camera-relay-loopback.conf`에 `options v4l2loopback devices=1 exclusive_caps=1 card_label="Camera Relay"`를 지정합니다.
  * `exclusive_caps=1` 옵션은 루프백 노드에 프레임이 주입되기 시작하면 장치의 기능을 오직 순수 캡처(`CAPTURE`) 전용으로 전환하여 Chromium 브라우저가 정규 웹캠으로 열거할 수 있게 합니다.
  * `/etc/modules-load.d/v4l2loopback.conf`로 부팅 극초기에 모듈을 선행 로드하여 `/dev/video0` 자리를 선점합니다.
  * `/etc/udev/rules.d/70-camera-relay-capabilities.rules`를 통해 Chromium의 udev 디바이스 열거자가 "Camera Relay" 장치를 즉시 `ID_V4L_CAPABILITIES=":capture:"`로 인식하도록 보장합니다.
  * `/etc/udev/rules.d/90-hide-ipu6-v4l2.rules`로 인텔 IPU6 원시 하드웨어 ISYS 노드(48개 비디오 노드)의 `uaccess` 태그를 제거하여 일반 앱이 엉뚱한 내부 장치를 웹캠으로 여는 것을 차단합니다.

### (3) 26MHz 센서 외부 클록 에러 (`ov02c10-26mhz-fix`)
* **원인**: 인텔 메테오레이크(MTL) IPU6 컨트롤러는 `ov02c10` 센서에 **26 MHz** 외부 클록(mclk)을 인가합니다. 하지만 업스트림 순정 커널의 `ov02c10` 드라이버는 과거 19.2 MHz 클록만을 허용하도록 하드코딩되어 있어, 부팅 시 커널 로그에 `-EINVAL: external clock 26000000 is not supported` 에러를 남기며 센서 바인딩에 실패합니다.
* **해결책**:
  * `ov02c10-26mhz-fix` DKMS 모듈(`ov02c10/1.0`)을 적용하여 19.2 MHz뿐만 아니라 26 MHz 클록도 정상적인 공급 주파수로 수용하도록 probe 함수를 패치합니다.

### (4) 부팅 시 웹캠 복불복 켜짐 문제 (Initramfs 레이스 컨디션)
* **원인**: 우분투 부팅 초기 initramfs 램디스크 단계에서 커널이 IPU6 모듈(`intel_ipu6.ko`)을 로드할 때, 센서 펌웨어 바이너리(`ipu6epmtl_fw.bin`)가 램디스크에 포함되어 있지 않으면 루트 파일시스템이 마운트되기 전에 펌웨어 요청이 타임아웃되어 드라이버 초기화가 영구히 실패합니다. 부팅 속도나 드라이브 마운트 타이밍에 따라 어떨 때는 켜지고 어떨 때는 죽는 "복불복" 현상의 직접적인 원인이었습니다.
* **해결책**:
  * 펌웨어 압축 파일(`/lib/firmware/intel/ipu/ipu6epmtl_fw.bin.zst`)을 미리 압축 해제하여 `.bin` 바이너리를 생성합니다.
  * Dracut 설정(`/etc/dracut.conf.d/ipu6-firmware.conf`)을 등록하여 램디스크 생성 시 IPU6 펌웨어를 필수로 포함(`install_items+=" /lib/firmware/intel/ipu/ipu6epmtl_fw.bin* "`)하도록 강제합니다. (initramfs-tools 환경 호환 훅도 함께 지원)
  * 부팅 시점부터 펌웨어가 램디스크에 상주하므로 100% 안정적으로 웹캠이 초기화됩니다.

### (5) 상시 구동 발열/배터리 누수 방지 (On-Demand Camera Relay)
* **원인**: MIPI 카메라를 백그라운드에서 상시 스트리밍해 두면 센서와 IPU6 하드웨어가 쉬지 않고 전력을 소모하여 시스템 온도가 상승하고 배터리가 시간당 2~4W 이상 추가 소모됩니다.
* **해결책**:
  * 경량 C 모니터 프로그램(`/usr/local/bin/camera-relay-monitor`)과 관리 도구(`/usr/local/bin/camera-relay`)를 연동하여 **On-Demand** 방식으로 동작합니다.
  * 평상시에는 가상 루프백 장치(`/dev/video0`)만 열어두고 대기(Idle)하며, CPU 및 센서 전력 소모가 **0%**로 유지됩니다.
  * 브라우저나 화상회의 앱이 웹캠을 여는 순간 밀리초 단위로 파이프라인(`libcamerasrc → queue → videoconvert → v4l2sink`)을 기동하여 영상을 공급하고, 앱이 웹캠을 닫으면 즉시 센서 작동을 정지합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 시스템의 다음 경로에 설정 파일과 바이너리를 배치합니다:

| 대상 경로 | 설명 | 원본 템플릿 위치 |
| :--- | :--- | :--- |
| `/etc/dracut.conf.d/ipu6-firmware.conf` | initramfs 램디스크에 IPU6 펌웨어 사전 탑재 강제 | [`configs/webcam/dracut/ipu6-firmware.conf`](./configs/webcam/dracut/ipu6-firmware.conf) |
| `/etc/modprobe.d/99-camera-relay-loopback.conf` | v4l2loopback 1번 디바이스 `exclusive_caps=1` 설정 | [`configs/webcam/modprobe.d/99-camera-relay-loopback.conf`](./configs/webcam/modprobe.d/99-camera-relay-loopback.conf) |
| `/etc/modprobe.d/ivsc-camera.conf` | ov02c10 센서 probe 전 IVSC 모듈 의존성 선행 로드 지정 | [`configs/webcam/modprobe.d/ivsc-camera.conf`](./configs/webcam/modprobe.d/ivsc-camera.conf) |
| `/etc/modules-load.d/v4l2loopback.conf` | 부팅 시 v4l2loopback 자동 로드 (video0 선점) | [`configs/webcam/modules-load.d/v4l2loopback.conf`](./configs/webcam/modules-load.d/v4l2loopback.conf) |
| `/etc/modules-load.d/ivsc.conf` | 부팅 시 IVSC 센서 허브 모듈군 자동 로드 | [`configs/webcam/modules-load.d/ivsc.conf`](./configs/webcam/modules-load.d/ivsc.conf) |
| `/etc/udev/rules.d/70-camera-relay-capabilities.rules` | Chromium이 루프백 장치를 캡처 전용 웹캠으로 인식하게 강제 | [`configs/webcam/udev/70-camera-relay-capabilities.rules`](./configs/webcam/udev/70-camera-relay-capabilities.rules) |
| `/etc/udev/rules.d/90-hide-ipu6-v4l2.rules` | 원시 IPU6 ISYS 노드(48개)에서 `uaccess` 제거하여 앱 혼선 방지 | [`configs/webcam/udev/90-hide-ipu6-v4l2.rules`](./configs/webcam/udev/90-hide-ipu6-v4l2.rules) |
| `/etc/udev/rules.d/99-ipu6.rules` | IPU 노드 접근 권한(`video` 그룹, 0660) 지정 | [`configs/webcam/udev/99-ipu6.rules`](./configs/webcam/udev/99-ipu6.rules) |
| `/etc/environment` | GStreamer 및 libcamera 전역 라이브러리 경로 등록 | 시스템 환경변수 자동 병합 |
| `/usr/local/bin/camera-relay` | 웹캠 릴레이 서비스 제어 및 진단 CLI 도구 | [`configs/webcam/camera-relay/camera-relay`](./configs/webcam/camera-relay/camera-relay) |
| `/usr/local/bin/camera-relay-monitor` | On-Demand V4L2 클라이언트 이벤트 모니터링 바이너리 | [`configs/webcam/camera-relay/camera-relay-monitor.c`](./configs/webcam/camera-relay/camera-relay-monitor.c) (C 소스 컴파일) |
| `/usr/local/sbin/ipu-bridge-check-upstream.sh` | 상위 커널에 삼성 쿼크 반영 시 DKMS 자동 제거 스크립트 | [`configs/webcam/sbin/ipu-bridge-check-upstream.sh`](./configs/webcam/sbin/ipu-bridge-check-upstream.sh) |
| `/etc/systemd/system/ipu-bridge-check-upstream.service` | 부팅 시 상위 커널 머지 여부 1회 확인 systemd 서비스 | [`configs/webcam/systemd/ipu-bridge-check-upstream.service`](./configs/webcam/systemd/ipu-bridge-check-upstream.service) |
| `~/.config/systemd/user/camera-relay.service` | 로그인 시 On-Demand 릴레이 백그라운드 구동 서비스 | [`configs/webcam/systemd-user/camera-relay.service`](./configs/webcam/systemd-user/camera-relay.service) |
| `/usr/local/share/libcamera/ipa/simple/ov02c10.yaml` | OV02C10 센서 튜닝 프로파일 (노출/게인 보정) | [`configs/webcam/ipa/ov02c10.yaml`](./configs/webcam/ipa/ov02c10.yaml) |
| `/usr/src/ipu-bridge-fix-1.4/` | 180도 회전 보정 DKMS 소스 트리 | [`configs/webcam/dkms/ipu-bridge-fix-1.4/`](./configs/webcam/dkms/ipu-bridge-fix-1.4/) |
| `/usr/src/ov02c10-1.0/` | 26MHz 외부 클록 허용 DKMS 소스 트리 | [`configs/webcam/dkms/ov02c10-1.0/`](./configs/webcam/dkms/ov02c10-1.0/) |

---

## 3. 사전 요구사항 및 의존성

본 스크립트는 실행 시 필요한 시스템 패키지를 자동으로 감지하고 설치합니다:

* **빌드 도구 및 헤더**: `build-essential`, `meson`, `ninja-build`, `cmake`, `pkg-config`, `git`, `dkms`, `linux-headers-$(uname -r)`
* **V4L2 및 커널 모듈**: `v4l2loopback-dkms`, `v4l-utils`
* **GStreamer 파이프라인**: `gstreamer1.0-tools`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good`, `gstreamer1.0-plugins-bad`, `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`
* **Meson/PipeWire 필수 개발 라이브러리**: `libdbus-1-dev`, `libsystemd-dev`, `libevent-dev`, `libyaml-dev`, `libdrm-dev`, `libjpeg-dev`, `libtiff-dev`, `zstd`

---

## 4. 사용 방법

### 원클릭 복원 실행
```bash
sudo ./webcam_setup.sh
```
설치가 완료되면 안내 메시지에 따라 시스템을 재부팅(`sudo reboot`)합니다.

### 상태 확인 및 진단
재부팅 후 터미널에서 다음 명령어들을 통해 웹캠이 정상 작동하는지 확인합니다:

1. **릴레이 상태 확인**:
   ```bash
   camera-relay status
   ```
   *정상 출력 예시:*
   ```text
   Camera Relay Status
   ─────────────────────
     State:      ON-DEMAND (idle, PID 2227)
     Persistent: ENABLED (on-demand, auto-starts on login)
     Camera:     \_SB_.PC00.LNK0
     Loopback:   /dev/video0
   ```

2. **종합 진단 리포트 (하드웨어부터 브라우저까지 전수 점검)**:
   ```bash
   camera-relay doctor
   ```

3. **비디오 디바이스 목록 확인**:
   ```bash
   v4l2-ctl --list-devices
   ```
   *`/dev/video0`이 `Camera Relay (platform:v4l2loopback-000)`으로 가장 위에 위치해야 함.*

4. **DKMS 모듈 정상 등록 확인**:
   ```bash
   dkms status
   ```
   *`ipu-bridge-fix/1.4` 및 `ov02c10/1.0`이 `installed` 상태여야 함.*

---

## 5. 수동 확인 및 롤백 (원상 복구)

언제든지 스크립트가 적용한 모든 설정과 DKMS 모듈, systemd 서비스를 제거하고 우분투 순정 상태로 되돌릴 수 있습니다:

```bash
sudo ./webcam_setup.sh --restore
```
*(또는 `sudo ./scripts/restore-webcam.sh` 직접 실행)*

롤백 시 다음 작업이 수행됩니다:
1. `camera-relay` 사용자 서비스 중지 및 자동 시작 비활성화
2. `ipu-bridge-check-upstream` 시스템 서비스 및 검사 스크립트 제거
3. `/usr/local/bin/camera-relay` 및 `camera-relay-monitor` 바이너리 삭제
4. 등록된 udev 룰(70, 90, 99번) 삭제 및 udev 리로드
5. modprobe 및 modules-load 설정 파일 삭제
6. dracut initramfs 펌웨어 번들 설정 제거 및 램디스크 재생성
7. (사용자 선택 시) `ipu-bridge-fix` 및 `ov02c10` DKMS 모듈 언인스톨 및 소스 트리 정리
