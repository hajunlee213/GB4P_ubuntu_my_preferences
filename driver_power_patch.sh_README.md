# driver_power_patch.sh 설명 문서

이 문서는 **[`driver_power_patch.sh`](./driver_power_patch.sh)** 스크립트가 적용하는 인텔 메테오레이크 `i915` 드라이버 안정화(Early KMS), 인텔 마이크로코드/써멀 제어, GPU 연산 가속(OpenCL), PCIe ASPM 초절전 정책, 그리고 PowerTOP 자동 튜닝 서비스의 동작 원리와 복원/롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 드라이버 선정 이유

삼성 갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK / Meteor Lake Core Ultra 5 125H, 7d55)에서 안정적인 리눅스 환경과 극대화된 전성비를 달성하기 위해 검증된 **`i915` 드라이버를 기본으로 안정화**하고 유휴 전력 최적화를 적용합니다.

### (1) 왜 `xe` 대신 `i915`를 선택하는가?
* **메테오레이크에서 `xe` 드라이버의 치명적 한계**:
  * 인텔이 `xe` 드라이버를 공식 기본값으로 채택한 것은 루나레이크(Core Ultra 200V) 및 배틀메이지부터이며, **메테오레이크(Core Ultra 1세대)에서 `xe`는 여전히 "실험적(Experimental)" 상태**입니다. (Mesa 라이브러리 실행 시 경고 문구 출력)
  * 실제로 `xe` 드라이버 구동 시 **GPU TLB Invalidation 타임아웃 오류(`*ERROR* TLB invalidation fence timeout`)**가 빈번하게 발생하여 순간적인 화면 멈칫거림이나 GPU 행(프리징)을 유발합니다.
  * 또한 노트북 덮개를 닫았다 열 때(Lid open/close) 절전 모드 복귀 과정에서 **MCR 락 획득 실패(`WARNING: xe_gt_mcr.c mcr_lock`)**가 발생하여 화면이 켜지지 않는 위험이 있습니다.
  * 이러한 버그는 커널 내부 드라이버 코드의 미완성에서 기인하므로 사용자가 설정으로 제어하기 어렵습니다.
* **`i915`의 검증된 안정성**:
  * `i915`는 20년간 숙성된 드라이버로 절전 모드(Suspend/Resume), ACPI 전원 전환, 멀티태스킹 렌더링에서 가장 신뢰할 수 있는 공식 프로덕션 드라이버입니다.

### (2) 과거 `i915`에서 발생했던 문제의 완벽한 해결 (Early KMS)
* **부팅 레이스 컨디션(정체) 문제**:
  * 커널 7.0 환경에서 `i915` 드라이버 로딩과 ACPI/하드웨어 초기화 간 타이밍 경합(Race condition)이 발생하여, 부팅 중 ACPI 로그 화면에서 멈추는 현상이 있었습니다.
  * **해결책**: Dracut 설정(`/etc/dracut.conf.d/i915.conf`)에 `force_drivers+=" i915 "`를 지정하여 **부팅 램디스크(Early KMS) 단계에서 `i915`를 극초기에 선행 로드**합니다. ACPI 모듈보다 먼저 드라이버가 완전히 안착하므로 부팅 정체 문제가 100% 원천 차단됩니다.
* **스피커 및 디스플레이 연동 보장**:
  * 깃허브에서 빌드한 SOF 내장 스피커/마이크 드라이버(`snd_sof_intel_hda_common`) 및 OLED 다중 주사율(60Hz~120Hz), sdr-native 광색역 클램핑과 완벽하게 호환됩니다.

### (3) PCIe ASPM 초절전 정책 (`pcie_aspm.policy=powersupersave`)
* 기본 커널의 ASPM 정책(`default`)은 NVMe SSD나 무선랜 링크가 깊은 L1 절전(L1.1 / L1.2)으로 내려가는 것을 제한합니다.
* `pcie_aspm.policy=powersupersave`를 적용하여 PCIe 버스 유휴 전력을 최소화하고, CPU 패키지가 최하위 극저전력 유휴 상태인 **`Package C10`**에 원활하게 진입하도록 합니다. (`i915` 드라이버는 `xe`와 달리 깊은 ASPM 절전 상태에서도 TLB 타임아웃 없이 안정적으로 동작합니다.)

### (4) 최신 CPU 마이크로코드, 써멀 데몬, PowerTOP, NMI 절전
* `intel-microcode` 및 `thermald`: 최신 CPUID(`0x000a06a4`) 보안/안정성 패치 및 하드웨어 스로틀링 완화
* `intel-opencl-icd`, `clinfo`: Intel Arc Xe-LPG iGPU의 하드웨어 OpenCL 연산 가속 활성화
* `powertop.service`: 부팅 시 모든 PCI/USB 디바이스의 Runtime PM을 `auto`(자동 절전)로 전환
* `kernel.nmi_watchdog = 0`: 1초 주기 하드웨어 인터럽트를 제거하여 CPU 코어 슬립 지속 시간 극대화

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 시스템의 다음 경로에 설정 파일과 서비스를 등록합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/default/grub` | 커널 부팅 파라미터 (`pcie_aspm.policy=powersupersave`) | 자동 수정 (백업본 자동 생성) |
| `/etc/dracut.conf.d/i915.conf` | Early KMS 램디스크에 `i915` 모듈 사전 탑재 강제 | [`configs/dracut/i915.conf`](./configs/dracut/i915.conf) |
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

### (1) Early KMS `i915` 로딩 메커니즘 (`scripts/fix-i915-race-condition.sh`)
* **설정 파일**: `/etc/dracut.conf.d/i915.conf` (`force_drivers+=" i915 "`)
* **전용 스크립트**: [`scripts/fix-i915-race-condition.sh`](./scripts/fix-i915-race-condition.sh) (독립 실행 가능)
* **동작 원리**:
  * 리눅스 부팅 시 커널이 initramfs 램디스크를 풀 때 `i915.ko`를 즉시 메모리에 로드합니다.
  * ACPI 인터럽트 서브시스템 및 사운드/입력 디바이스 드라이버가 초기화되기 전에 디스플레이 파이프라인이 안전하게 기동되므로, 커널 7.0에서 발생하던 초기화 경합(Race Condition)이 완전히 차단됩니다.

### (2) PCIe ASPM `powersupersave` 초절전 정책
* **커널 파라미터**: `pcie_aspm.policy=powersupersave`
* **동작 원리**:
  * 모든 PCIe 링크가 하드웨어적으로 지원 가능한 가장 깊은 L1.2 서브스테이트로 진입하도록 강제합니다.
  * NVMe SSD 및 Wi-Fi의 유휴 소비 전력이 급감하며, CPU SoC 전력 관리 유닛(PMC)이 전체 패키지 유휴 상태를 인지하여 **`Package C10`** 진입률이 극대화됩니다.

### (3) PowerTOP Auto-Tune 서비스 (`powertop.service`)
* 부팅 시 `multi-user.target` 이후 1회 실행(`Type=oneshot`)되어 시스템 내의 모든 PCI/USB 디바이스 제어 디렉토리(`/sys/bus/pci/devices/*/power/control` 등)의 설정을 `auto`로 변경합니다.
* 장치가 데이터 I/O를 수행하지 않을 때 즉시 D3hot / D3cold 슬립 상태로 전환됩니다.

### (4) NMI Watchdog 비활성화 (`kernel.nmi_watchdog = 0`)
* 매초 발생하는 하드웨어 감시 인터럽트를 비활성화하여 유휴 코어가 강제로 깨어나는 것을 방지하고 딥 슬립 상태를 지속시킵니다.

---

## 4. 사전 요구사항 및 의존성

* **지원 하드웨어**: 삼성 갤럭시 북4 프로 (Intel Core Ultra 5 125H / Core Ultra 7 155H 등 Meteor Lake 계열)
* **지원 운영체제**: Ubuntu 24.04 LTS / Ubuntu 26.04 LTS (Linux Kernel 6.8+, 7.0 커널 완벽 지원)
* **필수 도구**:
  * `apt-get` 패키지 관리자
  * `dracut` 또는 `initramfs-tools`
  * `grub2` (`update-grub` 또는 `grub-mkconfig`)
  * 관리자 권한(`sudo`)

---

## 5. 수동 확인 및 롤백 (원상 복구) 방법

### (1) 정상 적용 확인 방법 (적용 및 재부팅 후)

1. **`i915` 그래픽 드라이버 활성화 확인**:
   ```bash
   lspci -k -s 00:02.0
   # 출력 결과: Kernel driver in use: i915
   lsmod | grep i915
   ```

2. **PCIe ASPM 절전 정책 확인**:
   ```bash
   cat /sys/module/pcie_aspm/parameters/policy
   # 출력 결과: default performance powersave [powersupersave]
   ```

3. **GPU OpenCL 연산 장치 확인**:
   ```bash
   clinfo -l
   # 출력 결과: Platform #0: Intel(R) OpenCL Graphics / Device #0: Intel(R) Arc(TM) Graphics
   ```

4. **PowerTOP 및 thermald 서비스 상태 확인**:
   ```bash
   systemctl status powertop.service thermald.service
   ```

5. **NMI Watchdog 비활성화 확인**:
   ```bash
   cat /proc/sys/kernel/nmi_watchdog
   # 출력 결과: 0
   ```

---

### (2) 원클릭 롤백 (순정 출고 상태 복구)

언제든지 패치를 제거하고 우분투 기본 출고 상태로 되돌릴 수 있습니다:

```bash
sudo ./driver_power_patch.sh --restore
```

**롤백 스크립트(`restore-driver-power-patch.sh`)가 수행하는 작업**:
1. `/etc/default/grub`에서 `pcie_aspm.policy=powersupersave` 및 잔존 xe 파라미터 완전 제거 후 `update-grub` 실행
2. `/etc/dracut.conf.d/i915.conf` 파일 제거 및 램디스크(`dracut` / `update-initramfs`) 재생성
3. `powertop.service` 중지, 비활성화 및 `/etc/systemd/system/powertop.service` 파일 삭제
4. `/etc/sysctl.d/99-nmi-watchdog.conf` 삭제 및 `kernel.nmi_watchdog = 1` 기본값 복구
5. 런타임 PCIe ASPM 정책을 `default`로 복원
