# display_tuning.sh 설명 문서

이 문서는 **[`display_tuning.sh`](./display_tuning.sh)** 스크립트가 적용하는 디스플레이 EDID 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK 16인치, Samsung ATNA60CL07-0 2880×1800 AMOLED 패널)를 우분투(리눅스)에서 사용할 때 다음과 같은 디스플레이 문제가 발생합니다:

### (1) 우분투 디스플레이 설정에 120Hz만 표시되는 문제
- **원인**: 삼성 팩토리 EDID ROM에는 물리적으로 `2880x1800 @ 120.00Hz` 단 1개의 상세 타이밍(DTD, Detailed Timing Descriptor)만 기록되어 있으며, FreeSync/VRR 가변 범위(`48Hz ~ 120Hz`)가 명시되어 있습니다.
- **윈도우(Windows)의 동작**: 인텔 그래픽 드라이버와 WDDM/DWM이 패널의 VRR 범위를 읽고 `24, 30, 48, 60, 75, 80, 100, 120Hz` 등의 표준 주사율 모드를 소프트웨어적으로 가상 생성(Synthesize)하여 노출합니다.
- **우분투(Linux Wayland/DRM)의 동작**: 리눅스 커널 DRM(`i915`/`xe`) 드라이버는 EDID에 실제로 정의된 하드웨어 DTD만 커널 디스플레이 모드로 등록합니다. 따라서 우분투 기본 GNOME Wayland 환경에서는 120Hz 단 하나만 노출되어, 배터리 절약을 위한 60Hz 선택이 불가능합니다.

### (2) 단순 픽셀 클럭 분주 시 블랙아웃(Black Screen) 문제
- 일반 LCD 패널 모니터는 60Hz 적용 시 도트클럭(Pixel Clock)을 120Hz(655.13 MHz)의 절반인 327.56 MHz로 낮추는 표준 방식을 사용합니다.
- 그러나 갤럭시 북4 프로의 최신 OLED 패널 TCON(Timing Controller) 및 eDP 링크는 **655.13 MHz 고정 도트클럭에서만 물리적으로 위상 동기화(Clock Lock)**되도록 설계되어 있습니다.
- 도트클럭을 변경하면 TCON이 링크 신호를 즉시 상실하여 화면이 완전히 꺼지는 블랙아웃 현상이 발생합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 펌웨어 바이너리를 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/lib/firmware/edid/gb4p_custom_edid.bin` | 고정 픽셀 클럭 & V-Blank 확장 맞춤형 256B EDID 바이너리 | [`configs/edid/gb4p_custom_edid.bin`](./configs/edid/gb4p_custom_edid.bin) |
| `/usr/lib/firmware/edid/gb4p_custom_edid.bin` | 시스템 펌웨어 보조 경로 동기화 바이너리 | [`configs/edid/gb4p_custom_edid.bin`](./configs/edid/gb4p_custom_edid.bin) |
| `/etc/dracut.conf.d/edid.conf` | Dracut 램디스크 빌드 시 커스텀 EDID 포함 설정 | [`configs/dracut/edid.conf`](./configs/dracut/edid.conf) |
| `/etc/initramfs-tools/hooks/edid` | initramfs-tools 램디스크 빌드 시 EDID 포함 훅 | [`configs/initramfs-tools/edid`](./configs/initramfs-tools/edid) |
| `/etc/default/grub` | 부팅 커널 파라미터 (`drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin`) | 자동 수정 (기존 파일 백업 생성) |

---

## 3. 핵심 파라미터 및 동작 원리

### (1) 고정 픽셀 클럭 (655.13 MHz) & V-Blank 확장 메커니즘
윈도우 드라이버 및 FreeSync/VRR 엔진이 패널 주사율을 낮출 때 사용하는 하드웨어 프로토콜과 동일하게 작동합니다:
- **도트클럭(Pixel Clock)**: `655.13 MHz` (고정)
- **수평 해상도 & 라인 주파수**: `H-Active 2880`, `H-Blank 100` (H-Total: 2980), `H-Sync 219.84 kHz` (고정)
- **주사율 제어**: 수직 블랭킹(V-Blank) 라인 수를 늘려서 프레임 1장을 그리는 주기($V_{\text{total}}$ 라인 수)를 조절함으로써 TCON 동기화 해제 없이 주사율을 낮춥니다.

$$V_{\text{total}} = \frac{655.13 \times 10^6 \text{ Hz}}{2980 \times \text{Target Hz}}$$

$$V_{\text{blank}} = V_{\text{total}} - 1800$$

### (2) 주사율별 세부 하드웨어 타이밍 테이블

| 주사율 | Pixel Clock | H-Sync | V-Total | V-Blank | 실제 계산 주사율 | 비고 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **120 Hz** | 655.13 MHz | 219.84 kHz | 1832 lines | 32 lines | 120.00 Hz | 출고 기본 네이티브 모드 (DTD 1) |
| **100 Hz** | 655.13 MHz | 219.84 kHz | 2198 lines | 398 lines | 100.02 Hz | 부드러움과 절전 절충 모드 (DTD 5) |
| **80 Hz** | 655.13 MHz | 219.84 kHz | 2748 lines | 948 lines | 80.00 Hz | 고주사율 체감 유지 저발열 모드 (DTD 4) |
| **75 Hz** | 655.13 MHz | 219.84 kHz | 2931 lines | 1131 lines | 75.01 Hz | 표준 비디오 주사율 모드 (DTD 3) |
| **60 Hz** | 655.13 MHz | 219.84 kHz | 3664 lines | 1864 lines | 60.00 Hz | **최대 배터리 절약 모드** (DTD 2) |

### (3) OLED 컬러 및 메타데이터 완벽 보존
EDID 바이너리 Block 1 (CTA-861 확장 블록)의 모든 제조사 고유 태그를 온전히 유지합니다:
- **Colorimetry Data Block**: `BT2020RGB` (광색역 지원)
- **HDR Static Metadata**: SMPTE ST2084 규격, 피크 밝기 565.7 cd/m²
- **AMD FreeSync / VRR Block**: `48 Hz ~ 120 Hz` 가변 주사율 대역폭 지원

### (4) Early KMS (Kernel Mode Setting) 통합
- 부팅 극초기(Early KMS)에 그래픽 드라이버가 패널에 접근할 때 해당 EDID 파일이 존재해야 합니다.
- 시스템의 램디스크 빌더(`dracut` 또는 `initramfs-tools`)를 자동 감지하여 램디스크 내부에 펌웨어를 삽입하므로 부팅 시 글리치 없이 부드럽게 초기화됩니다.

---

## 4. 사전 요구사항 및 의존성

- **하드웨어**: 갤럭시 북4 프로 16인치 (Samsung AMOLED ATNA60CL07-0 패널 장착 모델)
- **운영체제**: Ubuntu 22.04 / 24.04 / 26.04+ (Wayland 및 X11 모두 지원)
- **필수 도구**:
  - `grub2` (`update-grub` 또는 `grub-mkconfig`)
  - `dracut` 또는 `initramfs-tools` (우분투 버전에 따라 자동 감지)
  - `root` (sudo) 실행 권한

---

## 5. 수동 확인 및 롤백 (원상 복구) 방법

### (1) 정상 적용 확인 방법 (재부팅 후)

1. **GUI 확인**:
   - 우분투 **설정(Settings)** ➡️ **디스플레이(Displays)** ➡️ **주사율(Refresh Rate)** 드롭다운 클릭
   - `60Hz`, `75Hz`, `80Hz`, `100Hz`, `120Hz`가 정상 목록으로 표시되는지 확인.
2. **커널 적용 여부 확인**:
   ```bash
   cat /proc/cmdline | grep edid
   # 출력 예시: drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin 포함 여부
   ```
3. **하드웨어 V-Sync 실측 검증**:
   - 60Hz 선택 시 화면 렌더링뿐 아니라 실제 하드웨어 CRTC도 60Hz(초당 60회 프레임 갱신)로 동작하여 OLED 소비 전력이 크게 감소합니다.

---

### (2) 원클릭 롤백 (순정 출고 상태 120Hz로 원상 복구)

언제든지 패치를 제거하고 출고 초기 상태(120Hz 단독)로 되돌릴 수 있습니다:

```bash
sudo ./display_tuning.sh --restore
sudo reboot
```

> **`--restore` 동작 내역**:
> 1. 사용자별 GNOME 디스플레이 캐시(`~/.config/monitors.xml`)를 초기화하여 주사율 불일치 방지
> 2. `/etc/dracut.conf.d/edid.conf` 및 `/etc/initramfs-tools/hooks/edid` 삭제
> 3. `/lib/firmware/edid/gb4p_custom_edid.bin` 삭제
> 4. `/etc/default/grub`에서 `drm.edid_firmware` 파라미터 자동 제거
> 5. 램디스크 및 부트로더(GRUB)를 순정 상태로 재빌드

---

### (3) 비상 상황 대처 가이드 (트러블슈팅)

#### 상황 A. 주사율 변경 후 화면이 검게 나오는 경우 (TTY 복구)
1. **TTY 가상 콘솔 진입**: 키보드에서 **`Ctrl + Alt + F3`** (또는 `F4`)를 누릅니다.
2. 계정 아이디와 비밀번호로 로그인합니다.
3. 원복 명령 실행:
   ```bash
   cd ~/projects/GB4P_ubuntu_my_preferences
   sudo ./display_tuning.sh --restore
   sudo reboot
   ```

#### 상황 B. 부팅 단계에서 화면이 멈추거나 안 나오는 경우 (GRUB 임시 복구)
1. 부팅 시 메인보드 로고가 뜰 때 **`Shift`** 키 또는 **`ESC`** 키를 연타하여 GRUB 부팅 메뉴로 진입합니다.
2. 부팅할 우분투 항목에 커서를 두고 **`e`** 키를 누릅니다.
3. `linux /boot/vmlinuz-...` 줄을 찾아 **`drm.edid_firmware=...`** 문구를 삭제합니다.
4. **`Ctrl + X`** 또는 **`F10`**을 누르면 커스텀 EDID 없이 순정 120Hz로 즉시 부팅됩니다.
5. 부팅 후 터미널에서 `sudo ./display_tuning.sh --restore`를 실행하시면 영구 복구됩니다.
