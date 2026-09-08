# driver_power_patch.sh 설명 문서

이 문서는 **[`driver_power_patch.sh`](./driver_power_patch.sh)** 스크립트가 적용하는 인텔 메테오레이크 차세대 커널 드라이버(`xe`) 전환, 인텔 마이크로코드/써멀 제어, GPU 연산 가속(OpenCL), PCIe ASPM 초절전 정책, 그리고 PowerTOP 자동 튜닝 서비스의 동작 원리와 복원/롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

삼성 갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK / Meteor Lake Core Ultra 5 125H)를 리눅스(우분투)에서 순정 상태로 구동할 때 다음과 같은 드라이버 호환성 및 유휴 전력 누수 문제가 발생합니다:

### (1) 레거시 `i915` 드라이버의 한계 및 부팅 레이스 컨디션 (Race Condition)
* **문제점**:
  * 인텔 메테오레이크(Intel Arc Xe-LPG 아키텍처)는 타일 기반 칩렛 구조로 하드웨어 설계가 완전히 바뀌었습니다.
  * 그러나 초기 리눅스 커널 호환성을 위해 20년 전 915G 시절부터 이어져 온 모놀리식 드라이버인 `i915`가 기본값으로 바인딩되어 왔습니다.
  * 이로 인해 최신 커널 환경에서 부팅 중 ACPI 초기화 타이밍과 그래픽 드라이버 로딩 간의 충돌(Race condition)이 발생하여 부팅 화면에서 멈추거나 정체되는 문제가 잦았습니다.
  * 또한 패널 셀프 리프레시(PSR) 기능 충돌로 인한 화면 프리징/깜빡임, 메모리 관리자(GEM) 경합 현상이 동반되었습니다.
* **해결책**:
  * 메테오레이크 및 이후 세대(Lunar Lake, Battlemage 등)를 위해 커널 DRM의 차세대 드라이버로 새로 작성된 **`xe` 커널 드라이버**로 전환합니다.
  * `xe` 드라이버는 모던 칩렛 구조에 맞춰 메모리 관리와 타이밍이 완전히 재설계되어 부팅 정체와 PSR 깜빡임 버그가 근본적으로 해결됩니다.

### (2) 최신 CPU 마이크로코드 및 써멀 데몬(`thermald`) 부재
* **문제점**:
  * 우분투 기본 설치 시 최신 인텔 마이크로코드 패키지(`intel-microcode`)와 하드웨어 온도/스로틀링 제어 데몬(`thermald`)이 누락되거나 구버전 상태로 방치될 수 있습니다.
  * 최신 메테오레이크 CPUID(`0x000a06a4`)에 대응하는 안정성/보안 마이크로코드와 인텔 DPTF(Dynamic Platform and Thermal Framework) 연동이 없으면 발열 억제 및 코어 부스트 제어가 원활하지 못합니다.
* **해결책**:
  * `intel-microcode` 및 `thermald`를 최신으로 설치하고 상시 서비스로 활성화하여 하드웨어 발열 쓰로틀링과 클럭 안정성을 극대화합니다.

### (3) PCIe 링크 ASPM 정책 기본값(`default`)으로 인한 유휴 전력 낭비
* **문제점**:
  * 우분투 기본 커널의 PCIe ASPM(Active State Power Management) 정책은 바이오스 설정에 의존하는 `[default]` 상태입니다.
  * 메테오레이크의 초저전력 C-state(Package C8, C10 등)에 진입하려면 시스템 내부의 모든 PCIe 버스(NVMe SSD, Intel Wi-Fi 등)가 깊은 L1 절전 서브스테이트(L1.1, L1.2)로 내려가야 합니다.
  * 정책이 `default`인 경우 PCIe 링크가 상위 유휴 상태(L0s 또는 L1.0)에 머물러 패키지 C-state 진입을 방해하고 배터리를 불필요하게 소모합니다.
* **해결책**:
  * 커널 파라미터 `pcie_aspm.policy=powersupersave`를 적용하여 모든 PCIe 링크에 공격적인 L1 서브스테이트 절전을 강제합니다.

### (4) 장치 Runtime PM 미최적화 및 NMI 타이머 인터럽트
* **문제점**:
  * Wi-Fi, SPI 컨트롤러, 센서 허브, GNA(신경망 가속기) 등 다양한 내부 버스 장치가 런타임 전원 관리(Runtime PM) `on` 상태로 유지되어 전력을 계속 소모합니다.
  * 커널 NMI Watchdog 타이머가 1초마다 주기적 인터럽트를 발생시켜 유휴 상태의 CPU 코어를 깨우고 딥 슬립 진입을 방해합니다.
* **해결책**:
  * `powertop --auto-tune`을 부팅 시 자동 실행하는 systemd 백그라운드 서비스를 등록하여 모든 장치를 `auto` 절전으로 전환합니다.
  * `kernel.nmi_watchdog = 0`을 sysctl에 영구 등록하여 불필요한 주기적 인터럽트를 차단합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 시스템의 다음 경로에 설정 파일과 서비스를 등록합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/default/grub` | 커널 부팅 파라미터 (`i915.force_probe=!7d55 xe.force_probe=7d55 pcie_aspm.policy=powersupersave`) | 자동 수정 (백업본 자동 생성) |
| `/etc/dracut.conf.d/gpu-drivers.conf` | Early KMS 램디스크 빌드 시 `i915` 및 `xe` 모듈 포함 강제 | [`configs/dracut/gpu-drivers.conf`](./configs/dracut/gpu-drivers.conf) |
| `/etc/systemd/system/powertop.service` | 부팅 시 모든 버스 장치 Runtime PM 자동 튜닝 실행 서비스 | [`configs/systemd/powertop.service`](./configs/systemd/powertop.service) |
| `/etc/sysctl.d/99-nmi-watchdog.conf` | CPU 유휴 수면 방해 인터럽트 차단 (`kernel.nmi_watchdog = 0`) | [`configs/sysctl/99-nmi-watchdog.conf`](./configs/sysctl/99-nmi-watchdog.conf) |

### 설치되는 시스템 패키지 목록
1. `intel-microcode`: 메테오레이크 CPU 마이크로코드 펌웨어 최신 패치
2. `thermald`: 인텔 플랫폼 써멀 데몬 (온도 센서 모니터링 및 선제적 쿨링)
3. `intel-opencl-icd`: 인텔 Arc GPU OpenCL 연산 가속 런타임
4. `clinfo`: OpenCL 플랫폼 및 디바이스 연산 정보 조회 유틸리티
5. `powertop`: 전력 소모 진단 및 런타임 버스 전원 자동 최적화 도구

---

## 3. 주요 파라미터 및 동작 원리

### (1) 차세대 `xe` 그래픽 드라이버 전환 메커니즘
* **디바이스 ID 바인딩 분리**:
  * 메테오레이크-P 내장 그래픽(Intel Arc Graphics)의 PCI 디바이스 ID는 `8086:7d55`입니다.
  * `i915.force_probe=!7d55`: 레거시 `i915` 드라이버가 이 장치를 프로빙하지 못하도록 강제 차단합니다.
  * `xe.force_probe=7d55`: 차세대 `xe` 드라이버가 해당 디바이스를 독점 바인딩하여 초기화하도록 지시합니다.
* **Early KMS (Kernel Mode Setting) 통합**:
  * 부팅 극초기에 드라이버가 교체되는 과정에서 블랙아웃이나 레이스 컨디션이 발생하는 것을 막기 위해, `dracut` 설정(`force_drivers+=" i915 xe "`)을 통해 부팅 램디스크(initramfs) 내부에 `xe.ko` 모듈을 사전 탑재합니다.
* **사운드 및 디스플레이 연동 보장**:
  * 노트북 내장 스피커 드라이버(`snd_sof_intel_hda_common`)는 디스플레이 오디오 링크를 통해 그래픽 드라이버에 악수(Handshake)합니다.
  * 커널 6.8+ 및 7.0에서 `intel_audio_component_bind_ops`가 `xe` 드라이버를 기본 지원하므로, 오디오 및 내장 마이크가 끊김 없이 완벽하게 작동합니다.
  * 고정 픽셀 클럭 기반의 커스텀 EDID(다중 주사율 60Hz~120Hz) 및 sdr-native 클램핑과도 100% 호환됩니다.

### (2) PCIe ASPM `powersupersave` 초절전 정책
* **ASPM 링크 계층 상태**:
  * `L0`: 활성 전송 상태
  * `L0s`: 초단기 유휴 상태 (복귀 시간 수 마이크로초)
  * `L1 / L1.1 / L1.2`: 깊은 링크 비활성화 상태 (클럭 정지 및 전압 강하, 전력 소모 90%+ 절감)
* **`pcie_aspm.policy=powersupersave`**:
  * PCIe 장치가 바이오스 화이트리스트에 명시적으로 등록되어 있지 않더라도, 하드웨어 레벨에서 지원 가능한 가장 깊은 L1.2 서브스테이트로 진입하도록 커널이 강제합니다.
  * 메테오레이크 SoC의 전력 관리 유닛(PMC)이 전체 패키지 유휴 상태를 인지하여 최하위 초저전력 상태인 **`Package C10`**에 도달할 수 있는 핵심 전제 조건을 완성합니다.

### (3) PowerTOP Auto-Tune 서비스 (`powertop.service`)
* 부팅 시 `multi-user.target` 이후 1회 실행(`Type=oneshot`)되어 시스템 내의 모든 PCI/USB 디바이스 제어 디렉토리(`/sys/bus/pci/devices/*/power/control` 등)의 설정을 `auto`로 변경합니다.
* 장치가 데이터 I/O를 수행하지 않을 때 즉시 D3hot / D3cold 슬립 상태로 전환되어 배터리 소모를 즉각적으로 억제합니다.

### (4) NMI Watchdog 비활성화 (`kernel.nmi_watchdog = 0`)
* NMI(Non-Maskable Interrupt) Watchdog은 커널 데드락을 감지하기 위해 주기적으로 하드웨어 인터럽트를 발생시킵니다.
* 일반 랩탑 환경에서는 시스템 락업 감지 실효성보다 매초 발생하는 인터럽트로 인해 CPU 코어가 유휴 C-state에서 강제로 깨어나는 배터리 손실이 더 큽니다.
* 이를 0으로 비활성화하여 코어가 온전하게 C-state 수면을 유지할 수 있도록 합니다.

---

## 4. 사전 요구사항 및 의존성

* **지원 하드웨어**: 삼성 갤럭시 북4 프로 (Intel Core Ultra 5 125H / Core Ultra 7 155H 등 Meteor Lake 계열)
* **지원 운영체제**: Ubuntu 24.04 LTS / Ubuntu 26.04 LTS (Linux Kernel 6.8+ 이상 권장, 7.0 커널 완벽 지원)
* **필수 도구**:
  * `apt-get` 패키지 관리자
  * `dracut` 또는 `initramfs-tools`
  * `grub2` (`update-grub` 또는 `grub-mkconfig`)
  * 관리자 권한(`sudo`)

---

## 5. 수동 확인 및 롤백 (원상 복구) 방법

### (1) 정상 적용 확인 방법 (적용 및 재부팅 후)

1. **`xe` 그래픽 드라이버 활성화 확인**:
   ```bash
   lspci -k -s 00:02.0
   # 출력 결과: Kernel driver in use: xe
   lsmod | grep -E "^xe|^i915"
   # xe 모듈이 높은 카운트로 사용 중이며, i915는 언로드 또는 0 사용
   ```

2. **오디오 드라이버와 xe 바인딩 확인**:
   ```bash
   journalctl -k -b | grep -i "bound 0000:00:02.0"
   # 출력 결과: bound 0000:00:02.0 (ops intel_audio_component_bind_ops [xe])
   ```

3. **GPU OpenCL 연산 장치 확인**:
   ```bash
   clinfo -l
   # 출력 결과: Platform #0: Intel(R) OpenCL Graphics / Device #0: Intel(R) Arc(TM) Graphics
   ```

4. **PCIe ASPM 절전 정책 확인**:
   ```bash
   cat /sys/module/pcie_aspm/parameters/policy
   # 출력 결과: default performance powersave [powersupersave]
   ```

5. **PowerTOP 및 thermald 서비스 상태 확인**:
   ```bash
   systemctl status powertop.service thermald.service
   ```

6. **NMI Watchdog 비활성화 확인**:
   ```bash
   cat /proc/sys/kernel/nmi_watchdog
   # 출력 결과: 0
   ```

---

### (2) 원클릭 롤백 (순정 i915 드라이버 및 기본 설정 복구)

언제든지 패치를 제거하고 우분투 순정 출고 상태로 되돌릴 수 있습니다:

```bash
sudo ./driver_power_patch.sh --restore
```

**롤백 스크립트(`restore-driver-power-patch.sh`)가 수행하는 작업**:
1. `/etc/default/grub`에서 `i915.force_probe=!7d55`, `xe.force_probe=7d55`, `pcie_aspm.policy=powersupersave` 파라미터 완전 제거 후 `update-grub` 실행
2. `/etc/dracut.conf.d/gpu-drivers.conf` 파일 제거 및 램디스크(`dracut` / `update-initramfs`) 재생성
3. `powertop.service` 중지, 비활성화 및 `/etc/systemd/system/powertop.service` 파일 삭제
4. `/etc/sysctl.d/99-nmi-watchdog.conf` 삭제 및 `kernel.nmi_watchdog = 1` 기본값 복구
5. 런타임 PCIe ASPM 정책을 `default`로 복원
6. 작업 완료 후 재부팅(`sudo reboot`)하면 순정 `i915` 드라이버와 기본 절전 설정으로 안전하게 복원됩니다.
