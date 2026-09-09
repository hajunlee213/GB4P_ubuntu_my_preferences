# Galaxy Book 4 Pro (GB4P) Ubuntu 개인 설정 원클릭 복원

갤럭시 북4 프로(GB4P, NT960XGK / Meteor Lake) 및 유사 기기에서 우분투를 재설치했을 때, **터치패드/키보드 편의 설정**, **전력 소모 최적화(power_consumption)** 및 **OLED 다중 주사율(60Hz, 80Hz 등) 디스플레이 패치** 설정을 명령어 한 줄로 복원하기 위한 프로젝트입니다.

---

## 빠른 시작 (원클릭 복원)

우분투를 새로 설치한 후 터미널에서 원하는 복원 스크립트를 실행합니다:

```bash
git clone https://github.com/your-username/GB4P_ubuntu_my_preferences.git # (또는 로컬 복사본)
cd GB4P_ubuntu_my_preferences
chmod +x *.sh scripts/*.sh
```

### 1. 전력 소모 및 발열 최적화 복원 (`power_consumption.sh`)
```bash
./power_consumption.sh
```

### 2. 터치패드 팜리젝션 & 키보드(한영/한자) 복원 (`touchpad_keyboard.sh`)
```bash
./touchpad_keyboard.sh
```

### 3. 디스플레이 다중 주사율(60Hz, 80Hz 등) 복원 (`display_tuning.sh`)
```bash
./display_tuning.sh
```
> 적용 후 시스템을 재부팅(`sudo reboot`)하면 **설정 → 디스플레이 → 주사율**에서 60Hz, 75Hz, 80Hz, 100Hz, 120Hz를 자유롭게 선택할 수 있습니다. (순정 복구: `sudo ./display_tuning.sh --restore`)

### 4. 전원 연동 주사율 & sdr-native(sRGB) 복원 (`power_refresh_sdr.sh`)
```bash
./power_refresh_sdr.sh
```
> AC 연결 시 80Hz VRR, 배터리 사용 시 60Hz VRR로 자동 전환되며, 주사율 변경이나 절전 모드 해제 시 풀리는 OLED `sdr-native`(sRGB 클램핑) 설정을 항상 유지합니다. (원상 복구: `./power_refresh_sdr.sh --restore`)

### 5. OLED 다크모드 대비 완화 & Eye Care 복원 (`oled_contrast.sh`)
```bash
./oled_contrast.sh
```
> OLED 다크모드의 극단적 명암비로 인한 눈부심을 줄이고, 리얼 블랙(0x000000) 픽셀 소등 지연 잔상(블랙 스미어링)을 완화하는 맞춤형 ICC 프로파일 4종(High/Medium x Contrast/PureBlack)과 CLI 제어 도구(`oled-mode`)를 복원합니다. (순정 복구: `./oled_contrast.sh --restore`)

### 6. 드라이버 패치 & 전력 최적화 복원 (`driver_power_patch.sh`)
```bash
./driver_power_patch.sh
```
> 인텔 차세대 그래픽 드라이버(`xe`) 전환, 마이크로코드/thermald, GPU 연산 가속(OpenCL), PCIe ASPM 초절전(`powersupersave`), PowerTOP 자동 튜닝 서비스를 복원합니다. (순정 복구: `sudo ./driver_power_patch.sh --restore`)

---

## power_consumption (전력 소모 & 발열 튜닝 상세)

인텔 메테오레이크(Meteor Lake Core Ultra 5 125H 등)의 높은 유휴/부하 전력 소모와 피크 발열(90°C+ 쓰로틀링)을 해결하기 위해 최적화된 설정들입니다.

### 1. CPU 하이브리드 아키텍처 토폴로지 최적화 (3P + 4E + 2LP-E 총 9코어 체제)
* **P-core HT (하이퍼스레딩) 차단**:
  * CPU 2, 4, 5, 7번 비활성화 (순수 물리 P-core만 가동하여 스레드 경합/누수 차단)
* **P-core 2 (CPU 3) 차단 (Dark Silicon 열 완충구역 생성)**:
  * P코어 블록(CPU 1 — 3 — 0 — 6) 정중앙에 위치한 **CPU 3을 비활성화(OFF)**
  * P코어 사이에 열을 내지 않는 빈 실리콘 완충 지대를 두어 P코어 간 열 간섭(Thermal Coupling) 차단 및 피크 온도 대폭 저감
  * 남은 3개 P코어가 18MB 공유 L3 캐시를 더 넓게 독점(코어당 4.5MB -> 6.0MB로 33% 증가)하여 캐시 적중률 및 체감 반응성 개선
* **E-core 다이 위치 기반 클러스터 분리 최적화**:
  * **Cluster 0 (CPU 8~11)**: P코어와 다이상 인접해 있어 열 집중을 유발하므로 **비활성화(OFF)**
  * **Cluster 1 (CPU 12~15)**: 다이 외곽에 위치하여 방열에 유리하므로 **활성화(ON)** 유지
* **LP-E Core (CPU 16, 17)**: 저전력 아일랜드 코어로 기본 활성화 유지
* **복원 경로**: `~/.local/bin/disable-ht.sh`, `~/.config/autostart/disable-ht.desktop`

### 2. SSD I/O 깨움 주기 지연 (VM Dirty Writeback 최적화)
* **목적**: 디스크(SSD)가 유휴 상태에서 불필요하게 15초마다 깨어나 전력을 낭비하는 현상 방지
* **설정 파일**: `/etc/sysctl.d/99-ssd-power-saving.conf`
  * `vm.dirty_writeback_centisecs = 6000`: 커널 flush 데몬 깨움 주기를 기본 15초에서 60초로 지연
  * `vm.dirty_expire_centisecs = 12000`: 더티 데이터 만료 시간 120초 지정
  * `vm.laptop_mode = 5`: 배터리 모드 시 I/O 쓰기 묶음 처리로 디스크 유휴 상태 극대화

### 3. AC(충전기) vs DC(배터리) 동적 자동 전환 시스템
* **커널 udev 룰**: `/etc/udev/rules.d/99-power-profile-switch.rules`
  * 충전기 어댑터(`ADP1`)의 연결/분리 이벤트를 실시간 감지하여 `handle_power_change.sh` 호출
  * `flock` 기반 중복 실행 방지(Lock) 및 0.3초 디바운스로 안정화 처리
* **AC 모드 (충전기 연결 시)**:
  * **터보 부스트**: ON (`no_turbo = 0`)
  * **클럭 상한선**: 65% (`max_perf_pct = 65`) - "2번 밸런스 터보"
  * **삼성 팬/Gnome 모드**: `Balanced` (성능과 발열 밸런스)
* **DC 모드 (배터리 사용 시)**:
  * **터보 부스트**: OFF (`no_turbo = 1`) - 20W+ 피크 전력 튐 및 급격한 방전 차단
  * **클럭 상한선**: 100% (`max_perf_pct = 100`) - 베이스 클럭 한도 내에서 100% 성능 쾌적하게 유지
  * **삼성 팬/Gnome 모드**: `Balanced` (적극적 쿨링을 유지하여 배터리 모드 발열 누적 원천 차단)

### 4. 부팅 시 자동 감지 & 적용 (Autostart)
* **설정 파일**: `~/.config/autostart/power-options-startup.desktop`
* **동작**: 부팅/로그인 직후 시스템 전원 상태(AC vs DC)를 자동 판별하여 최적 프로필 즉시 적용

### 5. 무암호 전원 제어 sudoers & 바탕화면 원클릭 도구
* **sudoers**: `/etc/sudoers.d/poweroptions` (원클릭 스크립트 실행 시 비밀번호 입력 생략)
* **바탕화면 원클릭 도구 모음 (`~/Desktop/OneClickScripts/PowerOptions/`)**:
  * `00_Full_Power.sh`: 임시 풀파워 세션 (모든 코어 ON / 터보 ON / 80% / 재부팅 시 롤백)
  * `1_unlimited_turbo_on.sh`: 터보 ON / 100% 풀파워
  * `1_unlimited_turbo_off.sh`: 터보 OFF / 100% 베이스 클럭 풀파워
  * `2_balanced_turbo_on.sh`: 터보 ON / 65% 밸런스 터보
  * `3_balanced_turbo_off.sh`: 터보 OFF / 80% 밸런스 절전
  * `4_powersave_turbo_off.sh`: 터보 OFF / 50% 최대 절전
  * `custom_limit.sh`: 대화형 클럭 제한/터보 설정 도구
  * `check_status.sh`: 활성 코어 수, 클럭, 팬모드, 온도 실시간 모니터링

---

## touchpad_keyboard (터치패드 & 키보드 튜닝 상세)

### 1. 터치패드 팜리젝션 & DWT 연동 (`/etc/libinput/local-overrides.quirks`)
- **Zinitix 터치패드 (`14E5:E760`) 튜닝**:
  - `AttrPalmPressureThreshold=100`: 가벼운 손바닥 닿음 압력 감지
  - `AttrPalmSizeThreshold=20`: 접촉 면적이 넓은 손바닥 터치를 포인터 이동에서 제외
- **keyd 가상 키보드 DWT(Disable-While-Typing) 활성화**:
  - `AttrKeyboardIntegration=internal`: keyd 가상 키보드를 '내장 키보드'로 인식시켜 키보드 타이핑 도중 터치패드가 튀는 현상 차단

### 2. keyd 한영/한자 키 리매핑 (`/etc/keyd/default.conf`)
- **리매핑 규칙**:
  - **오른쪽 Alt (Alt_R)** -> **한영 키 (Hangul / KEY_HANGEUL)**
  - **오른쪽 Ctrl (Ctrl_R)** -> **한자 키 (Hanja / KEY_HANJA)**
- **Ubuntu 26.04 패키지 호환**:
  - `/usr/local/bin/keyd` 심볼릭 링크 자동 생성

### 3. GNOME 터치패드 제스처 및 기본값
- `tap-to-click true`: 터치패드 탭하여 클릭
- `natural-scroll true`: 두 손가락 자연스러운 스크롤
- `disable-while-typing true`: 타이핑 중 터치패드 잠금
- `two-finger-scrolling-enabled true`: 두 손가락 스크롤 활성화

---

## display_tuning (디스플레이 다중 주사율 & OLED 패널 최적화 상세)

갤럭시 북4 프로 16인치(Samsung ATNA60CL07-0 2880×1800 AMOLED) 패널의 출고 EDID ROM에는 120Hz 상세 타이밍만 등록되어 있어 우분투에서 60Hz 등 배터리 절약용 주사율을 선택할 수 없습니다. 또한 일반 LCD처럼 픽셀 클럭을 낮추면 OLED TCON 링크가 끊겨 화면이 꺼지는(블랙아웃) 문제가 있습니다.

### 1. 고정 픽셀 클럭(655.13 MHz) & V-Blank 확장
* **원리**: 윈도우/FreeSync VRR 드라이버 방식과 동일하게 도트클럭(655.13 MHz)과 수평 동기 주파수(219.84 kHz)를 120Hz와 100% 동일하게 유지하고, **수직 블랭킹(V-Blank) 라인만 확장**하여 주사율을 낮춥니다.
* **지원 주사율**:
  * **120 Hz**: 1832 lines (Vblank: 32) - 기본 출고 네이티브
  * **100 Hz**: 2198 lines (Vblank: 398) - 부드러움과 절전 절충
  * **80 Hz**: 2748 lines (Vblank: 948) - 체감 고주사율 저발열
  * **75 Hz**: 2931 lines (Vblank: 1131) - 표준 영상용
  * **60 Hz**: 3664 lines (Vblank: 1864) - **최대 배터리 절약**
* **메타데이터 유지**: BT.2020 광색역, HDR Static Metadata (565.7 cd/m²), FreeSync/VRR(48~120Hz) 완전 보존.

### 2. 부팅 통합 및 원클릭 복원/원복
* **Early KMS 패키징**: `dracut` (Ubuntu 26.04+) 및 `initramfs-tools` (Ubuntu 22.04/24.04) 자동 감지하여 램디스크에 주입.
* **GRUB 파라미터**: `drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin` 자동 등록.
* **순정 롤백 지원**: `sudo ./display_tuning.sh --restore` 실행 시 캐시 초기화 및 순정 출고 상태(120Hz)로 즉시 복원.

---

## power_refresh_sdr (전원 연동 주사율 & sdr-native Governor 상세)

충전기 연결(AC)과 배터리 사용(DC)에 따라 디스플레이 주사율을 지능적으로 전환하고, 주사율 변경이나 부팅/절전 복귀 시 풀려버리는 OLED 광색역 sRGB 클램핑(`sdr-native`)을 항상 자동으로 유지하는 백그라운드 서비스입니다.

### 1. 전원 상태별 주사율 자동 동적 전환
* **AC 연결 시**: **80Hz VRR** (부드러운 화면 체감과 저발열의 균형)
* **DC(배터리) 사용 시**: **60Hz VRR** (OLED 패널 배터리 소모 최소화)
* **물리적 AC 감지**: 삼성 배터리 수명 보호(80% 충전 제한)가 켜져 있어 '충전 중'이 아니더라도 `/sys/class/power_supply/ADP1/online` 등 물리적 전원 어댑터 연결을 직접 감지하여 정확하게 상태를 판별합니다.

### 2. OLED 광색역 sRGB 클램핑 (`sdr-native`) 자동 주입
* **문제점**: GNOME Wayland(Mutter) 환경에서는 주사율을 변경하거나 재부팅, 절전(Suspend) 후 복귀 시 `sdr-native` 설정이 풀려 패널 기본 P3 광색역으로 돌아가며 색이 과포화(Oversaturated)되는 버그가 있습니다.
* **해결책**: Mutter DisplayConfig D-Bus API(`ApplyMonitorsConfig`)를 통해 주사율 전환 시 `"color-mode": 2 (sdr-native)`를 원자적(Atomic)으로 함께 주입하여 언제나 왜곡 없는 표준 sRGB 색역을 보장합니다.

### 3. 무음 전환 및 무부하 (Zero-Overhead) 설계
* **확인 팝업 없음**: `TEMPORARY` (1) 모드로 D-Bus를 호출하여 "Keep these display settings?" 팝업 다이얼로그 없이 백그라운드에서 무음으로 즉시 전환됩니다.
* **이벤트 드리븐 (CPU 0%)**: 주기적 폴링 없이 UPower 및 logind D-Bus 신호(`PropertiesChanged`, `PrepareForSleep`)를 통해서만 반응하므로 유휴 전력 소모가 전혀 없습니다.
* **systemd 사용자 서비스**: `power-refresh-sdr.service`가 그래픽 세션 로그인 시 자동 시작됩니다.

---

## oled_contrast (OLED 다크모드 대비 완화 & Eye Care 상세)

OLED 패널에서 다크모드 사용 시 발생하는 극단적인 명암비(무한대 대비)로 인한 야간 눈부심 및 피로감을 해소하고, 완전한 블랙(0x000000)에서 소등된 픽셀이 켜질 때 발생하는 지연 잔상(Black Smearing / 퍼플 고스팅)을 억제하기 위해 설계된 하드웨어 VCGT 튜닝 패치입니다.

### 1. 16비트 VCGT 기반 무왜곡(0% 틴트) 톤 커브
* **문제점**: CTM(Color Transform Matrix)이나 단순 감마 변경 방식은 패널의 DCI-P3 광색역 및 비선형 감마 특성과 충돌하여 무채색(회색조)이 보라색이나 녹색으로 물드는 색 왜곡(Color Tint)이 발생합니다.
* **해결책**: 원본 EDID의 색상 보정 정보는 100% 보존한 채, **GPU 하드웨어 LUT에 직접 적용되는 16비트 VCGT(Video Card Gamma Table)**에 R, G, B 채널이 1:1:1로 완벽히 동일한 선형 톤 램프($y = \text{black\_offset} + (\text{white\_max} - \text{black\_offset}) \times x$)를 주입하여 틴트 왜곡 없이 정직한 대비 압축을 구현했습니다.

### 2. 제공 프로파일 사양 (2x2 매트릭스)
* **`High Contrast` (추천/기본)**:
  * **화이트 레벨**: **`90.0%`** (8비트 기준 `230/255`, 글자 가독성은 또렷하게 유지하며 찌르는 눈부심 완화)
  * **블랙 리프트**: **`+2.0%`** (8비트 기준 `5/255`, 픽셀 완전 소등을 방지하여 블랙 스미어링 억제 및 대비 완화)
* **`High Pure Black`**:
  * **화이트 레벨**: **`90.0%`** (8비트 기준 `230/255`, 밝은 텍스트 가독성)
  * **블랙 레벨**: **`0.0%`** (8비트 기준 `0/255`, OLED 픽셀 완전 소등으로 다크모드 배터리 절약)
* **`Medium Contrast`**:
  * **화이트 레벨**: **`85.0%`** (8비트 기준 `217/255`, 야간 장시간 코딩 및 문서 작업에 최적화)
  * **블랙 리프트**: **`+4.0%`** (8비트 기준 `10/255`, 확실한 대비 완화 및 스미어링 차단)
* **`Medium Pure Black` (전력/번인 최우선)**:
  * **화이트 레벨**: **`85.0%`** (8비트 기준 `217/255`, 차분한 화이트 밝기)
  * **블랙 레벨**: **`0.0%`** (8비트 기준 `0/255`, OLED 픽셀 완전 소등으로 다크모드 배터리 절약 & 번인 방지 극대화)

### 3. CLI 제어 도구 (`oled-mode`)
* `oled-mode high`        : High Contrast 적용 (화이트 90%, 블랙 +2.0%) [추천]
* `oled-mode high-pure`   : High Pure Black 적용 (화이트 90%, 블랙 0.0%)
* `oled-mode medium`      : Medium Contrast 적용 (화이트 85%, 블랙 +4.0%)
* `oled-mode medium-pure` : Medium Pure Black 적용 (화이트 85%, 블랙 0.0% - 전력/번인 최우선)
* `oled-mode custom <블랙%> <화이트%>` : 원하는 비율로 실시간 ICC 생성 및 적용 (예: `oled-mode custom 2.0 90`)
* `oled-mode status` : 현재 활성 디스플레이 프로파일 확인
* `oled-mode reset` : CTM 초기화 및 패널 순정 공장 출하 상태로 즉시 복원

---

## driver_power_patch (드라이버 패치 & 전력 최적화 상세)

인텔 메테오레이크(Meteor Lake Core Ultra 5 125H)의 차세대 하드웨어 아키텍처에 맞춰 구형 `i915` 드라이버를 최신 `xe` 드라이버로 전환하고, 유휴 전력 누수를 차단하여 배터리 효율과 시스템 안정성을 극대화한 설정들입니다.

### 1. 차세대 Intel Xe 그래픽 드라이버 전환 (`xe`)
* **배경 및 원인**: 메테오레이크의 타일(칩렛) 아키텍처에 20년 전 설계된 구형 `i915` 드라이버를 바인딩하면 부팅 중 ACPI 타이밍 충돌(Race Condition)로 멈추거나, PSR(패널 셀프 리프레시) 충돌로 화면 프리징/깜빡임이 발생합니다.
* **해결책**:
  * 메테오레이크-P iGPU(PCI ID `8086:7d55`)에 최신 **`xe` 드라이버**를 독점 바인딩 (`i915.force_probe=!7d55 xe.force_probe=7d55`)
  * Early KMS 부팅 램디스크(dracut)에 `xe` 모듈을 사전 포함하여 부팅 글리치 원천 차단
  * 노트북 내장 스피커(`snd_sof_intel_hda_common`) 및 OLED 다중 주사율/sdr-native 클램핑과 완벽 호환 보장

### 2. 인텔 CPU 마이크로코드 최신 패치 & 써멀 관리 (`thermald`)
* **`intel-microcode`**: 메테오레이크 CPUID(`0x000a06a4`) 보안 및 전력 제어 마이크로코드 최신 펌웨어 적용
* **`thermald`**: 인텔 DPTF(Dynamic Platform and Thermal Framework) 기반 온도 모니터링 데몬을 상시 가동하여 급격한 온도 상승 및 스로틀링 완화

### 3. GPU 하드웨어 연산 가속 (OpenCL Compute Runtime)
* **패키지**: `intel-opencl-icd`, `clinfo`
* **효과**: Intel Arc Xe-LPG 그래픽 코어의 병렬 연산(GPGPU)을 활성화하여 딥러닝, 미디어 인코딩 및 이미지 처리 가속

### 4. PCIe ASPM 초절전 정책 (`pcie_aspm.policy=powersupersave`)
* **목적**: NVMe SSD, 무선랜 등 시스템 내 모든 PCIe 버스가 가장 깊은 절전 서브스테이트(L1.1 / L1.2)로 강제 진입하도록 커널 정책 지정
* **효과**: 버스 유휴 전력을 최소화하여 CPU 패키지가 최하위 극저전력 유휴 상태인 **`Package C10`**에 원활하게 진입하도록 유도 (배터리 사용 시간 대폭 향상)

### 5. PowerTOP Auto-Tune 백그라운드 서비스 (`powertop.service`)
* **설정 파일**: `/etc/systemd/system/powertop.service`
* **동작**: 부팅 시 `powertop --auto-tune`을 1회 실행하여 Wi-Fi, SPI, 센서 허브, GNA 등 모든 PCI/USB 디바이스의 Runtime PM을 `auto`(자동 절전)로 즉시 전환

### 6. 커널 인터럽트 타이머 절전 (`kernel.nmi_watchdog = 0`)
* **설정 파일**: `/etc/sysctl.d/99-nmi-watchdog.conf`
* **효과**: 1초마다 유휴 코어를 강제로 깨우는 커널 NMI 감시견 타이머를 비활성화하여 코어의 딥 슬립 상태 지속 시간 극대화

---

## 프로젝트 구조

```
GB4P_ubuntu_my_preferences/
├── AGENT_README.md                # Agent 작업 가이드 및 규칙 지침서
├── touchpad_keyboard.sh           # 터치패드 & 키보드(keyd) 복원 스크립트
├── touchpad_keyboard.sh_README.md # 터치패드 & 키보드 패치 상세 설명서
├── power_consumption.sh           # 전력 소모 최적화 메인 복원 스크립트
├── power_consumption.sh_README.md  # 전력 소모 최적화 패치 상세 설명서
├── display_tuning.sh              # 디스플레이 다중 주사율(60~120Hz) 복원 스크립트
├── display_tuning.sh_README.md    # 디스플레이 주사율 패치 상세 설명서
├── power_refresh_sdr.sh           # 전원 연동 주사율 & sdr-native 복원 스크립트
├── power_refresh_sdr.sh_README.md # 전원 연동 주사율 & sdr-native 패치 상세 설명서
├── oled_contrast.sh               # OLED 다크모드 대비 완화 & Eye Care 복원 스크립트
├── oled_contrast.sh_README.md      # OLED 대비 완화 패치 상세 설명서
├── driver_power_patch.sh          # 드라이버 패치 & 전력 최적화 복원 스크립트
├── driver_power_patch.sh_README.md # 드라이버 패치 & 전력 최적화 상세 설명서
├── configs/
│   ├── edid/
│   │   └── gb4p_custom_edid.bin   # OLED 맞춤형 256B EDID 바이너리
│   ├── icc/
│   │   ├── oled_high_contrast.icc      # 화이트 90.0%, 블랙 +2.0% VCGT (균형형)
│   │   ├── oled_high_pure_black.icc    # 화이트 90.0%, 블랙  0.0% VCGT (밝은 화이트 + 리얼블랙)
│   │   ├── oled_medium_contrast.icc    # 화이트 85.0%, 블랙 +4.0% VCGT (눈 편안함 최우선)
│   │   └── oled_medium_pure_black.icc  # 화이트 85.0%, 블랙  0.0% VCGT (전력/번인 최우선)
│   ├── dracut/
│   │   ├── edid.conf              # Dracut 램디스크 펌웨어 패키징 설정
│   │   └── gpu-drivers.conf       # Dracut i915/xe 램디스크 드라이버 설정
│   ├── initramfs-tools/
│   │   └── edid                   # initramfs-tools 램디스크 펌웨어 훅
│   ├── sysctl/
│   │   ├── 99-nmi-watchdog.conf   # NMI Watchdog 인터럽트 절전 파라미터
│   │   └── 99-ssd-power-saving.conf  # SSD 깨움 지연 커널 파라미터
│   ├── systemd/
│   │   └── powertop.service       # PowerTOP auto-tune systemd 서비스 유닛
│   ├── udev/
│   │   └── 99-power-profile-switch.rules # AC/DC 자동 전환 감지 udev 룰
│   ├── sudoers/
│   │   └── poweroptions              # 무암호 전원 스크립트 실행 sudoers 템플릿
│   ├── autostart/
│   │   ├── power-options-startup.desktop # 부팅 시 전원 프로필 자동 적용
│   │   └── disable-ht.desktop            # 부팅 시 CPU 토폴로지 적용
│   ├── bin/
│   │   ├── disable-ht.sh             # CPU HT 및 E코어 클러스터0 차단 스크립트
│   │   ├── oled-mode                 # OLED Eye Care CLI 전환 및 제어 도구
│   │   └── power-refresh-sdr-daemon.py # 전원 연동 주사율 & sdr-native 데몬
│   ├── systemd-user/
│   │   └── power-refresh-sdr.service # systemd 사용자 서비스 유닛 파일
│   ├── power_options/                # 바탕화면 원클릭 전원 제어 도구 모음
│   │   ├── 00_Full_Power.sh
│   │   ├── 1_unlimited_turbo_off.sh
│   │   ├── 1_unlimited_turbo_on.sh
│   │   ├── 2_balanced_turbo_on.sh
│   │   ├── 3_balanced_turbo_off.sh
│   │   ├── 4_powersave_turbo_off.sh
│   │   ├── apply_on_boot.sh
│   │   ├── check_status.sh
│   │   ├── custom_limit.sh
│   │   ├── enable_all_ecores.sh
│   │   ├── handle_power_change.sh
│   │   └── README.md
│   ├── libinput/
│   │   └── local-overrides.quirks    # 터치패드 팜리젝션 & DWT quirks
│   └── keyd/
│       └── default.conf              # Alt_R/Ctrl_R -> 한영/한자 키 매핑
├── scripts/
│   ├── setup-driver-power-patch.sh   # 드라이버 & 전력 최적화 복원 서브 스크립트
│   ├── restore-driver-power-patch.sh # 드라이버 & 전력 최적화 순정 롤백 스크립트
│   ├── setup-display-edid.sh         # 디스플레이 EDID & 램디스크/GRUB 설정
│   ├── restore-display-edid.sh       # 디스플레이 설정 순정 원복 스크립트
│   ├── generate-edid.py              # EDID 타이밍 계산 및 바이너리 생성기
│   ├── setup-power-refresh-sdr.sh    # 전원 연동 주사율 & sdr-native 복원
│   ├── restore-power-refresh-sdr.sh  # 전원 연동 주사율 & sdr-native 원상 복구
│   ├── setup-oled-contrast.sh        # OLED 맞춤 ICC 및 oled-mode 복원
│   ├── restore-oled-contrast.sh      # OLED 대비 설정 순정 원복 스크립트
│   ├── generate-oled-icc.py          # OLED VCGT ICC 생성 유틸리티
│   ├── setup-power-sysctl.sh         # SSD 절전 sysctl 복원
│   ├── setup-power-options.sh        # 바탕화면 전원 도구 & CPU 제어 복원
│   ├── setup-power-udev.sh           # AC/DC 전환 udev 룰 복원
│   ├── setup-power-autostart.sh      # 부팅 자동 실행 항목 복원
│   ├── setup-power-sudoers.sh        # sudoers 무암호 권한 복원
│   ├── setup-touchpad.sh             # libinput 설정 복원
│   ├── setup-keyd.sh                 # keyd 설치 및 서비스 복원
│   └── setup-gnome.sh                # GNOME 터치패드 옵션 설정
└── README.md
```
