# power_consumption.sh 설명 문서

이 문서는 **[`power_consumption.sh`](./power_consumption.sh)** 스크립트가 적용하는 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

삼성 갤럭시 북4 프로(GB4P, Intel Core Ultra / Meteor Lake 아키텍처)는 고해상도 OLED 디스플레이와 다핵 하이브리드 CPU를 탑재하고 있어 리눅스 우분투 기본 환경에서 다음과 같은 전력 및 발열 문제가 발생합니다:

1. **NVMe SSD의 잦은 웨이크업(Wakeup)으로 인한 배터리 소모**:
   - 리눅스 기본 커널 설정에서는 디스크 캐시 dirty writeback 주기가 5초 단위로 짧게 돌아가 SSD가 절전 상태(APST / NVMe low power state)에 머무르지 못하고 자주 깨어납니다.
2. **Meteor Lake 하이브리드 CPU(P + E + LP-E)의 고발열 구조**:
   - P코어의 하이퍼스레딩(HT)과 물리적으로 밀집된 E코어 클러스터(Cluster 0)가 동시에 풀가동될 때 쿨링팬 소음 및 발열 스로틀링이 극심해집니다.
3. **충전기(AC) 및 배터리(DC) 전환 시 수동 설정의 번거로움**:
   - 배터리 사용 시에는 인텔 터보 부스트를 꺼서 배터리 수명을 대폭 확보하고, 충전기 연결 시에는 적절한 클럭 제한과 함께 성능을 내도록 자동 감지/전환 시스템이 필요합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 도구들을 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/sysctl.d/99-ssd-power-saving.conf` | SSD 더티 페이지 쓰기 주기 지연 및 laptop_mode 설정 | [`configs/sysctl/99-ssd-power-saving.conf`](./configs/sysctl/99-ssd-power-saving.conf) |
| `/etc/udev/rules.d/99-power-profile-switch.rules` | AC/DC 전원 어댑터 연결/분리 이벤트 감지 udev 룰 | [`configs/udev/99-power-profile-switch.rules`](./configs/udev/99-power-profile-switch.rules) |
| `/etc/sudoers.d/poweroptions` | 전원 스크립트 실행 시 비밀번호 입력을 면제하는 sudoers 설정 | [`configs/sudoers/poweroptions`](./configs/sudoers/poweroptions) |
| `~/.local/bin/disable-ht.sh` | CPU 하이퍼스레딩 및 하이브리드 코어 토폴로지 제어 스크립트 | [`configs/bin/disable-ht.sh`](./configs/bin/disable-ht.sh) |
| `~/.config/autostart/` | 부팅 시 전원 프로필 및 CPU 토폴로지 자동 적용 데스크톱 항목 | [`configs/autostart/`](./configs/autostart/) |
| `~/Desktop/OneClickScripts/PowerOptions/` | 바탕화면에서 원클릭으로 전원/터보 모드를 변경하는 도구 모음 | [`configs/power_options/`](./configs/power_options/) |

---

## 3. 핵심 설정 파라미터 및 동작 원리

### (1) SSD 전력 소모 지연 (`/etc/sysctl.d/99-ssd-power-saving.conf`)
```ini
vm.dirty_writeback_centisecs = 6000
vm.dirty_expire_centisecs = 12000
vm.laptop_mode = 5
```
- writeback 주기를 기존 5초에서 60초(6000 centisecs)로 대폭 늘려 SSD의 불필요한 깨어남을 억제하고 NVMe 깊은 절전 모드를 유지합니다.

### (2) CPU 하이브리드 토폴로지 최적화 (`~/.local/bin/disable-ht.sh`)
- **P코어 HT(보조 논리 스레드) 차단**: CPU 2, 4, 5, 7 비활성화 (순수 물리 P-core 가동 및 스레드 경합/누수 차단)
- **P코어 2 (CPU 3) 및 P코어 3 (CPU 6) 차단 (Dark Silicon 완충구역)**:
  - 2P 체제(CPU 0, 1) 구축으로 P코어 사이의 열 간섭을 차단하고 18MB L3 캐시 독점 및 피크 전력 스파이크 원천 방지
- **E코어 8개 전체 가동 (Cluster 0 & 1, CPU 8~15 ON)**:
  - 브라우저의 수십 개 백그라운드 스레드(JS 엔진, GC, 렌더러 워커)를 고르게 분산하여 1.0GHz 저클럭에서도 병목 없이 일감을 처리
- **LP-E 코어 (CPU 16, 17) 차단**:
  - 실효성 없이 TLB shootdown과 인터럽트로 깨어나는 SoC 타일 코어를 꺼서 SoC-Compute 타일 간 패브릭 인터커넥트 병목 및 슬립 낭비 원천 제거

### (3) AC/DC 자동 전환 시스템 (`/etc/udev/rules.d/99-power-profile-switch.rules`)
- **🔌 충전기(AC) 연결 시**: 터보 부스트 ON (65% 클럭 제한) + 균형 모드
  - P코어 ~2.9GHz / 8E코어 ~2.34GHz로 구동되어 총 24.5 GHz·core의 데스크톱급 멀티코어 성능 발휘
- **🔋 배터리(DC) 전환 시**: 터보 부스트 OFF (기본 클럭 100%) + 균형 모드
  - P코어 ~2.00GHz / 8E코어 ~1.00GHz로 구동되어 동적 스위칭 전력($P=CV^2f$) 최소화 (실측 11.7W 달성)

---

## 4. 실측 벤치마크 및 쇼케이스 (Benchmark Showcase)

실제 웹 브라우징(Chromium/Gecko) 환경에서 배터리(`BAT1`) 방전 전력, CPU 패키지 온도, 실시간 클럭을 1~2분 단위로 정밀 샘플링하여 도출한 데이터입니다.

### 📊 배터리(DC) 모드 설정별 실측 비교표

| 설정 구성 | 코어 토폴로지 | 클럭 상한 | 평균 전력 | 바닥 전력 (Idle) | 피크 전력 | P코어 피크 | E코어 피크 | 평균 온도 | 평가 및 특성 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **터보 ON (50%)** | 2P + 4E (6코어) | 50% 제한 | **15.10 W** | 12.24 W | 19.75 W | 2.30 GHz | 1.80 GHz | 44.0 °C | 고클럭 V/F 전압 급상승으로 전력 소모 큼 |
| **터보 OFF (100%)** | 2P + 4E (6코어) | 100% 베이스 | **14.07 W** | 12.60 W | 17.29 W | 2.01 GHz | 1.01 GHz | 43.6 °C | E코어 4개 1.0GHz 락으로 작업 지연 |
| **터보 ON (40%)** | 2P + 4E (6코어) | 40% 제한 | **12.72 W** | 9.26 W | 18.91 W | 2.01 GHz | 1.51 GHz | 46.2 °C | E코어 1.5GHz 반응성 확보, 4코어 한계로 피크 튐 |
| **터보 OFF (100%) 🏆** | **2P + 8E (10코어)** | **100% 베이스** | **11.70 W** | **8.41 W** | **16.95 W** | **2.01 GHz** | **1.01 GHz** | **45.9 °C** | **최종 선정**: 물리적 저클럭 다코어의 압승 (-3.4W 절감) |

### 💡 핵심 아키텍처 발견 & 튜닝 인사이트

1. **"저클럭 다코어(8E @ 1.0GHz)" vs "고클럭 소수코어(4E @ 1.5GHz)"**:
   - 브라우저는 탭 하나만 열어도 JS V8 엔진, GC, 컴포지터, 네트워크 등 수십 개의 백그라운드 스레드를 생성합니다.
   - 4E 환경에서는 4개 코어에 부하가 몰려 스케줄러가 P코어를 자주 깨워 피크 전력이 18.9W까지 튑니다.
   - 반면 8E 환경에서는 8개 코어가 1.0GHz 극저전력 베이스 클럭으로 일감을 넉넉히 분산 처리하여 P코어 개입을 최소화하고, 피크(16.9W)와 바닥(8.4W)을 모두 낮춥니다.
   - 1.0GHz와 1.5GHz는 인텔 전압 하한선($V_{min}$)에 걸려 전압 차이가 거의 없으므로, 8코어 1.0GHz로 고정하는 것이 전체 동적 스위칭 전력($P=CV^2f$) 절감에 가장 유리합니다.

2. **다이 상의 Dark Silicon 발열 차단**:
   - P코어(CPU 0, 1) 사이에 차가운 실리콘(CPU 3, 6 OFF)을 배치하여 핫스팟 및 열 전도를 원천 차단하고 18MB L3 캐시를 독점합니다.

3. **AC/DC 단일 토폴로지 무지연 전환**:
   - 시스템 전체를 **[2P + 8E]**로 단일화하여, 충전기 탈착 시 CPU Hotplug 오버헤드 없이 `intel_pstate` 레지스터 전환만으로 0.001초 만에 매끄럽게 전환됩니다.

---

## 5. 수동 확인 및 테스트 명령어

- **현재 CPU 코어 활성 상태 및 터보 상태 확인**:
  ```bash
  ~/Desktop/OneClickScripts/PowerOptions/check_status.sh
  ```
- **sysctl 커널 파라미터 확인**:
  ```bash
  sysctl vm.dirty_writeback_centisecs vm.laptop_mode
  ```

---

## 6. 롤백 (설정 원상 복구) 방법

```bash
# 1. sysctl 설정 제거
sudo rm -f /etc/sysctl.d/99-ssd-power-saving.conf
sudo sysctl --system

# 2. udev 룰 및 sudoers 제거
sudo rm -f /etc/udev/rules.d/99-power-profile-switch.rules
sudo rm -f /etc/sudoers.d/poweroptions
sudo udevadm control --reload

# 3. 자동 실행 및 스크립트 파일 제거
rm -f ~/.config/autostart/power-options-startup.desktop
rm -f ~/.config/autostart/disable-ht.desktop
rm -f ~/.local/bin/disable-ht.sh
rm -rf ~/Desktop/OneClickScripts/PowerOptions

# 4. 모든 CPU 코어 다시 켜기
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 | sudo tee "$cpu/online" 2>/dev/null || true
done
```
